#!/usr/bin/env perl

use strict;
use warnings;
use utf8;
use v5.10;

use Archive::Zip::SimpleZip qw/$SimpleZipError :zip_method/;
use Data::Dumper;
use Digest::MD5 qw/md5 md5_hex/;
use Digest::SHA qw/sha256/;
use HTTP::Request;
use IO::File;
use LWP::UserAgent;
use MIME::Base64;
use Net::Amazon::Signature::V4;
use Time::HiRes qw/usleep/;
use XML::Simple;

my $access_key = $ENV{AWS_ACCESS_KEY_ID} || die 'AWS_ACCESS_KEY_ID needed';
my $secret_key = $ENV{AWS_SECRET_ACCESS_KEY} || die 'AWS_SECRET_ACCESS_KEY needed';

my $signer = Net::Amazon::Signature::V4->new($access_key, $secret_key, 'ap-northeast-1', 's3');
my $ua     = LWP::UserAgent->new;

my $bucket = '__YOUR__S3__BUCKET__';
my $s3_endpoint = "https://$bucket.s3-ap-northeast-1.amazonaws.com";

# test s3 list objects.
{
    my $request = HTTP::Request->new(GET => "$s3_endpoint/?list-type=2");
    $signer->sign($request);
    my $response = $ua->request($request);
    warn $response->content;
}

# https://docs.aws.amazon.com/AmazonS3/latest/API/API_CreateMultipartUpload.html
my $upload_id = '';
my $key = 'otameshi.dat';
{
    my @headers = ('x-amz-checksum-algorithm' => 'SHA256');
    my $request = HTTP::Request->new(POST => "$s3_endpoint/$key?uploads", \@headers);
    $signer->sign($request);
    my $response = $ua->request($request);
    # content sample.
    # <InitiateMultipartUploadResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Bucket>...</Bucket><Key>...</Key><UploadId>.....</UploadId></InitiateMultipartUploadResult>
    my $xml = XMLin($response->content);
    if ($key ne $xml->{Key}) {
        die 'key is not-equal. ' . $key . ' : ' . $xml->{Key};
    }
    $upload_id = $xml->{UploadId};
}

# https://docs.aws.amazon.com/AmazonS3/latest/API/API_UploadPart.html
my %total_digest = ();
my $idx = 1;

sub upload_part {
    my $data    = shift;
    my $md5     = md5($data);
    my $sha256  = sha256($data);
    my @headers = (
        'Content-Length'                => length($data),
        'Content-MD5'                   => encode_base64($md5),
        'x-amz-sdk-checksum-algorithm'  => 'SHA256',
        'x-amz-checksum-sha256'         => encode_base64($sha256),
    );
    my $request = HTTP::Request->new(PUT => "$s3_endpoint/$key?partNumber=$idx&uploadId=$upload_id", \@headers, $data);
    $signer->sign($request);
    my $response = $ua->request($request);
    $total_digest{ $idx } = +{
        etag    => $response->headers->{etag},
        # below for check aws payload
        md5     => $md5,
        sha256  => $sha256,
    };
    $idx++;
}

{
    my $size = 5 * 1024 * 1024;

    my $fh = IO::File->new_tmpfile;
    $fh->binmode;

    my $zip = Archive::Zip::SimpleZip->new($fh, Stream => 1) or die "failed to create streamed zip";

    my $data;
    foreach my $file_idx (1..12) {
        my $filename = "dummy.$file_idx";
        $zip->add($filename) or die $SimpleZipError;
        usleep(100_000);
    
        say "append file: " . $filename;
        say "buffer size: " . -s $fh;
        if (-s $fh > $size) {
            $fh->seek(0,0);
            while(1) {
                my $bytes_read = read($fh, $data, $size);
                if ($bytes_read < $size) {
                    say "carry over buffer size : " . $bytes_read;
                    truncate($fh, 0);
                    $fh->seek(0,0);
                    $fh->write($data);
                    last;
                }
                say "uploaded size : " . $bytes_read . ", index : " . $idx;
                upload_part($data);
            }
        }
    }
    $zip->close or die $SimpleZipError;
    $fh->seek(0,0);
    my $bytes_read = read($fh, $data, -s $fh);
    say "last buffer size : " . $bytes_read;
    if ($bytes_read > 0) {
        upload_part($data);
    }
}

# https://docs.aws.amazon.com/AmazonS3/latest/API/API_CompleteMultipartUpload.html
{
    my $parts = "";
    foreach my $idx (sort { $a <=> $b } keys %total_digest) {
        my $sha256 = encode_base64($total_digest{ $idx }{sha256});
        $sha256 =~ s/\r|\n|\r\n//g;
        $parts .= sprintf("<Part><ETag>%s</ETag><ChecksumSHA256>%s</ChecksumSHA256><PartNumber>%d</PartNumber></Part>",
            $total_digest{ $idx }{etag},
            $sha256,
            $idx
        );
    }
    my $payload = join "\n",
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<CompleteMultipartUpload xmlns="http://s3.amazonaws.com/doc/2006-03-01/">__PART__</CompleteMultipartUpload>';
    $payload =~ s/__PART__/$parts/;
    my $request = HTTP::Request->new(POST => "$s3_endpoint/$key?uploadId=$upload_id", undef, $payload);
    $signer->sign($request);
    my $response = $ua->request($request);
}

# https://docs.aws.amazon.com/AmazonS3/latest/API/API_GetObjectAttributes.html

my @etag_check;
my @sha256_check;
foreach my $idx (sort { $a <=> $b } keys %total_digest) {
    push @etag_check, $total_digest{$idx}{md5};
    push @sha256_check, $total_digest{$idx}{sha256};
}

my $expected_etag = sprintf "%s-%d",
    md5_hex(join('', @etag_check)),
    scalar(keys %total_digest);

my $expected_sha256 = encode_base64(sha256(join('', @sha256_check)));
$expected_sha256 =~ s/\r|\n|\r\n//g;

{
    my @headers = ('x-amz-object-attributes' => "ETag,Checksum,ObjectSize");
    my $request = HTTP::Request->new(GET => "$s3_endpoint/$key?attributes", \@headers);
    $signer->sign($request);
    my $response = $ua->request($request);
    my $xml = XMLin($response->content);

    die "invalud etag" if $xml->{ETag} ne $expected_etag;
    die "invalud sha256" if $xml->{Checksum}{ChecksumSHA256} ne $expected_sha256;
    warn Dumper $xml;
}

