#!/bin/bash

QUERY_TIMEOUT=10
TMP_RESULT="/tmp/query.tmp"
SQLITE_DB="dnsbl.sqlite"
DNS_LIST="dnsok"
BL_LIST="ipv4bl"

sqlitestore () {
	echo "INSERT INTO queries VALUES (\"$1\",\"$2\",\"$3\",\"$4\",\"$5\");" | sqlite3 $SQLITE_DB
}

querydns () {
	for dns in $( cat $DNS_LIST )
	do
		#echo "Querying $bl with $dns"
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
	querydns "2.0.0.127" "$bl"
	querydns "1.0.0.127" "$bl"
	wait
done

exit 0
