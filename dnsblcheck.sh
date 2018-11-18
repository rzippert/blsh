#!/bin/bash

QUERY_TIMEOUT=10
TMP_RESULT="/tmp/querydns.tmp"
TMP_REPORT="/tmp/reportdns.tmp"
SQLITE_DB="/home/rrzippert/Dev/blcheck/dbs/$( date +%Y%m%d )-dnsbl.sqlite"
DNS_LIST="/home/rrzippert/Dev/blcheck/lists/dnslist"
BL_LIST="/home/rrzippert/Dev/blcheck/lists/dns/dnsbl"
HOST_LIST="/home/rrzippert/Dev/blcheck/lists/dns/hostlist"
LOG_FILE="/home/rrzippert/Dev/blcheck/logs/$( date +%Y%m%d )-dnsblcheck.log"

sqlitereport () {
	echo -n "Verificação de blacklists (domínios) concluída com sucesso. " > $TMP_REPORT

	# Busca por listagens positivas
	echo "SELECT host,bl,answer,txt FROM queries WHERE answer != \"\" AND answer != \"NULL\";" | sqlite3 -line $SQLITE_DB > $TMP_RESULT
	if [[ -z $( cat $TMP_RESULT ) ]]
	then
		# Caso nenhuma listagem positiva seja encontrada:
		echo "Nenhuma blacklist reportou os domínios pesquisados." >> $TMP_REPORT
	else
		# Caso 1 ou mais listagens positivas sejam encontradas:
		echo "Foram encontradas as seguintes listagens em blacklists:" >> $TMP_REPORT
		echo "" >> $TMP_REPORT
		cat $TMP_RESULT >> $TMP_REPORT
		/usr/local/bin/telsend "$( cat $TMP_REPORT )"
	fi

	# Envio do relatório via telegram
	#/usr/local/bin/telsend "$( cat $TMP_REPORT )"
}

sqlitestore () {
	# Colunas: host,dns,bl,answer,time,txt
	echo "INSERT INTO queries VALUES (\"$1\",\"$2\",\"$3\",\"$4\",\"$5\",\"$6\");" | sqlite3 $SQLITE_DB
}

querydns () {
	# Repete a query solicitada com cada DNS configurado em DNS_LIST
	for dns in $( cat $DNS_LIST )
	do
		echo "[$( date )] Querying $bl with $dns for $1" | tee -a "$LOG_FILE" 
		dig +time=$QUERY_TIMEOUT +short @$dns $1.$2 > $TMP_RESULT
		if [[ $? -eq 0 ]]
		then
			if [[ $( cat $TMP_RESULT | wc -l ) -gt 1 ]]
			then
				# Resposta com multiplas entradas tem as quebras de linha removidas
				FULLRESULT="$(cat $TMP_RESULT | tr '\n' ',' )"
				RESULT="${FULLRESULT::-1}"
			else
				RESULT="$(cat $TMP_RESULT)"
			fi
			if [[ "$RESULT" != "" ]]
			then
				# Caso a blacklist reporte uma entrada, é solicitada a entrada TXT correspondente
				sqlitestore "$1" "$dns" "$2" "$RESULT" "$(date +%s)" "$( dig TXT +time=$QUERY_TIMEOUT +short @$dns $1.$2 | sed s/\"//g )"
			else
				sqlitestore "$1" "$dns" "$2" "$RESULT" "$(date +%s)" ""
			fi
		else
			# Caso a blacklist não responda com sucesso
			sqlitestore "$1" "$dns" "$2" "NULL" "$(date +%s)" "NULL"
		fi
		sleep 0.1
	done
}

main () {
	# Template sqlite com tables criadas
	cp dnsbl.sqlite.empty "$SQLITE_DB"

	# Questiona cada blacklist por cada host a ser checado
	for bl in $( cat $BL_LIST )
	do
		for dnshost in $( cat $HOST_LIST )
		do
			querydns "$dnshost" "$bl"
			wait
		done
	done
	sqlitereport
}

cd /home/rrzippert/Dev/blcheck
main

exit 0
