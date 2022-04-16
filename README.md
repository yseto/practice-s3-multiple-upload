# practice-s3-multiple-upload

please rewrite `$bucket` on upload.pl

## Usage

```
carton install
make
AWS_ACCESS_KEY_ID=....
AWS_SECRET_ACCESS_KEY=....
export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
carton exec -- perl upload.pl
```

### streamed zip file archiver

```
make dummy12
carton exec -- perl zip-upload.pl
make diff
```

#### check diff zip file

```
carton exec -- perl zip.pl
diff diff-dir/otameshi.dat dummy.zip
```

