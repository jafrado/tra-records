#!/bin/sh
./records.pl TripoliRecords2016-Single.csv single
./records.pl TripoliRecords2016-Research.csv research
./records.pl TripoliRecords2016-Complex.csv complex
./records.pl TripoliRecords2016-Hybrid.csv hybrid
./records.pl TripoliRecords2016-Handicapped.csv handicapped
./millions.pl TripoliRecords2016-Millions.csv millions

cp -f approved-gps.html events.html index.html records
