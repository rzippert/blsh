#!/bin/bash

QUERY_TIMEOUT=10
TMP_RESULT="/tmp/query.tmp"
SQLITE_DB="dbs/$( date +%Y%m%d )-ipv4bl.sqlite"
DNS_LIST="lists/dnsmt4"
BL_LIST="lists/ipv4/ipv4bl"
IP_LIST="lists/ipv4/ipv4list"
LOG_FILE="logs/$( date +%Y%m%d )-ipblcheck.log"

sqlitestore () {
	echo "INSERT INTO queries VALUES (\"$1\",\"$2\",\"$3\",\"$4\",\"$5\");" | sqlite3 $SQLITE_DB
}

querydns () {
	for dns in $( cat $DNS_LIST )
	do
		echo "[$( date )] Querying $bl with $dns" | tee -a "$LOG_FILE"
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

main () {
	for bl in $( cat $BL_LIST )
	do
		for ip4 in $( cat "$IP_LIST" )
		do
			querydns "$ip4" "$bl"
			wait
		done
	done
}

cp dnsbl.sqlite.empty "$SQLITE_DB"
main

exit 0
