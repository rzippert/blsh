#!/bin/bash

FULLRESULT="$(cat /tmp/query.tmp | tr '\n' ',' )"
RESULT="${FULLRESULT::-1}"


for line in $( cat $1 )
do
	#echo "INSERT INTO queries VALUES $line;" | sqlite3 bl.sqlite3
	echo "INSERT INTO queries VALUES (\"$line\");" | sqlite3 bl.sqlite3
done

exit 0
