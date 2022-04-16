#!/usr/bin/env perl

use strict;
use warnings;
use utf8;

use Archive::Zip::SimpleZip qw/$SimpleZipError :zip_method/;

my $fh = IO::File->new("> dummy.zip");
$fh->binmode;

my $zip = Archive::Zip::SimpleZip->new($fh, Stream => 1) or die "failed to create streamed zip";
foreach my $file_idx (1..12) {
    my $filename = "dummy.$file_idx";
    $zip->add($filename) or die $SimpleZipError;
}
$zip->close or die $SimpleZipError;
$fh->close;

