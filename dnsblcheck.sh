#!/bin/bash

QUERY_TIMEOUT=10
TMP_RESULT="/tmp/query2.tmp"
SQLITE_DB="dnsbl2.sqlite"
DNS_LIST="dnsok"
BL_LIST="dnsbl"

sqlitestore () {
	echo "INSERT INTO queries VALUES (\"$1\",\"$2\",\"$3\",\"$4\",\"$5\");" | sqlite3 $SQLITE_DB
}

querydns () {
	for dns in $( cat $DNS_LIST )
	do
		echo "[$( date )] Querying $bl with $dns" | tee -a dnsblcheck.log
		dig +time=$QUERY_TIMEOUT +short @$dns $1.$2 > $TMP_RESULT
		if [[ $? -eq 0 ]]
		then
			if [[ $( cat $TMP_RESULT | wc -l ) -gt 1 ]]
			then
				FULLRESULT="$(cat $TMP_RESULT | tr '\n' ',' )"
				RESULT="${FULLRESULT::-1}"
			else
				RESULT="$(cat $TMP_RESULT)"
			fi
			sqlitestore "$1" "$dns" "$2" "$RESULT" "$(date +%s)"
		else
			sqlitestore "$1" "$dns" "$2" "NULL" "$(date +%s)"
		fi
		sleep 0.1
	done
}

for bl in $( cat $BL_LIST )
do
	querydns "TEST" "$bl"
	querydns "INVALID" "$bl"
	wait
done

exit 0
