dummy:
	dd if=/dev/random of=data bs=1M count=10

dummy12:
	for number in 1 2 3 4 5 6 7 8 9 10 11 12; do \
		dd if=/dev/random of=dummy.$$number bs=1M count=$$number ; \
	done

diff:
	mkdir -p diff-dir/ && \
	cd diff-dir/ && \
	rm -f dummy.* && \
	aws s3 cp s3://__YOUR__S3__BUCKET__/otameshi.dat . && \
	unzip otameshi.dat
	for number in 1 2 3 4 5 6 7 8 9 10 11 12; do \
		diff dummy.$$number diff-dir/dummy.$$number ; \
	done
