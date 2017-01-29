records:
	./runall.sh
	tar -cvf ./records.tar ./records ./records.pl ./README
	gzip -vf9 records.tar
clean:
	rm -fr records records.tar.gz


