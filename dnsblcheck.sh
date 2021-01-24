#!/bin/bash

BASICPATH=~/".local/dnsbl"

QUERY_TIMEOUT=10
TMP_RESULT="$(mktemp)"
TMP_REPORT="$(mktemp)"
SQLITE_DB="$BASICPATH/dnsbl.sqlite"
DNS_LIST="$BASICPATH/lists/dns"
REPORTHISTORYSIZE="2"
if [[ -f "$DNS_LIST" ]]
then
	REPORTHISTORYSIZE="$(( "$(cat "$DNS_LIST" | wc -l)" * 2 ))"
fi
BL_LIST="$BASICPATH/lists/bl"
HOST_LIST="$BASICPATH/lists/host"
UNSENTREPORTS="$BASICPATH/unsentreports"
SENDLIMIT="240"
FULLLOGTIME=$(( "$( date +%s)" - 5184000 )) # full query log for 60 days
NOLOGTIME=$(( "$( date +%s)" - 315360000 )) # positive listings log for 10 years
DEBUG=0

function usage {
      echo "Usage: $0 [-hd] [-q QUERYTIMEOUT] [-D DBPATH] [-s SERVERLISTPATH] [-b BLACKLISTPATH] [-H HOSTSPATH] [-r REPORTRETRY] [-l FULLLOGTIME] [-L NOLOGTIME]
	-h			Print this usage text and exits.
	-d			Debug messages printed to console (default FALSE).
	-q QUERYTIMEOUT		Seconds until a query times out (default 10).
	-D DBPATH		Path the the sqlite DB file.
	-s SERVERLISTPATH	Path to the DNS servers list.
	-b BLACKLISTPATH	Path to the Blacklist servers list.
	-H HOSTSPATH		Path to the list of hosts that should be queried on blacklists.
	-r REPORTRETRY		Minutes to keep retrying to send the reports (once per minute) (default 240).
	-l FULLLOGTIME		Keep full query log for this number of days (previous entries are erased) (default 60 days).
	-L NOLOGTIME		Keep logs for this number of days (previoues entries are erased) (default 10 years)."
}

while getopts "hdq:D:s:b:H:r:l:L:" ARG; do
  case $ARG in
    d)
      DEBUG=1
      ;;
    q)
      QUERY_TIMEOUT="$OPTARG"
      ;;
    D)
      SQLITE_DB="$OPTARG"
      ;;
    s)
      DNS_LIST="$OPTARG"
      ;;
    b)
      BL_LIST="$OPTARG"
      ;;
    H)
      HOST_LIST="$OPTARG"
      ;;
    r)
      SENDLIMIT="$OPTARG"
      ;;
    l)
      FULLLOGTIME=$(( "$( date +%s )" - "$OPTARG" * 86400))
      ;;
    L)
      NOLOGTIME=$(( "$( date +%s )" - "$OPTARG" * 86400))
      ;;
    h)
      usage
      exit 1
      ;;
  esac
done

function displaytime {
	# Thanks http://www.infotinks.com/bash-convert-seconds-to-human-readable/
	local T=$1
	local D=$((T/60/60/24))
	local H=$((T/60/60%24))
	local M=$((T/60%60))
	local S=$((T%60))
	(( $D > 0 )) && printf '%d days ' $D
	(( $H > 0 )) && printf '%d hours ' $H
	(( $M > 0 )) && printf '%d minutes ' $M
	(( $S > 0 )) && { (( $D > 0 || $H > 0 || $M > 0 )) && printf 'and '
	printf '%d seconds\n' $S; } || printf '\n'
}

cleanup () {
	# Remove temp files
	rm $TMP_RESULT $TMP_REPORT
	# Clear old entries
	echo "DELETE FROM queries WHERE answer LIKE \"\" AND time < $FULLLOGTIME;" | sqlite3 $SQLITE_DB
	echo "DELETE FROM queries WHERE answer IS NULL AND time < $FULLLOGTIME;" | sqlite3 $SQLITE_DB
	echo "DELETE FROM queries WHERE time < $NOLOGTIME;" | sqlite3 $SQLITE_DB
	# Optimize and shrink database
	echo "VACUUM;" | sqlite3 $SQLITE_DB
}

sqlitereport () {
	# Sends a report via Telegram if there's a change in stored results
	if [[ -s $TMP_RESULT ]]
	then
		if [ $DEBUG ]; then echo "[$( date )] Sending report."; fi
		# If there are changes to report
		echo -e "Blacklist changes detected:\n" >> $TMP_REPORT
		cat $TMP_RESULT >> $TMP_REPORT
		local SENDCOUNT=0
		while true
		do
			telegram-send "$( cat $TMP_REPORT )"
			if [[ "$?" -eq 0 ]]
			then
				# If able to send, stops trying
				break
			elif [[	"$SENDCOUNT" -ge "$SENDLIMIT" ]]
			then
				# if can't send for some time, store the message as unsent
				cat "$TMP_REPORT" >> "$UNSENTREPORTS"
				cleanup
				break
			fi
			SENDCOUNT=$(( $SENDCOUNT + 1 ))
			sleep 60
		done
	fi
}

querystore () {
	# Store with sqlite the query result for future debugging
	# Colmns: host,dns,bl,answer,time,txt
	echo "INSERT INTO queries VALUES (\"$1\",\"$2\",\"$3\",\"$4\",\"$5\",\"$6\");" | sqlite3 $SQLITE_DB
}

resultstore () {
	# Store with sqlite the result consensus, but only when there are changes
	# Columns: host,bl,time,result
	echo "INSERT INTO results VALUES (\"$1\",\"$2\",\"$3\",\"$4\");" | sqlite3 $SQLITE_DB

	# Try to make a pretty report for when listing changes are detected
	local LISTEDTIME="$(echo "$(echo "SELECT time FROM queries WHERE host LIKE \"$1\" AND bl LIKE \"$2\" ORDER BY time DESC LIMIT 2;" | sqlite3 -csv -noheader $SQLITE_DB)" | tail -n1)"
	if [[ "$4" -gt 0 ]]
	then
		#TODO add some color to this (does Telegram support it somehow?)
		echo "[$( date )] Host $1 listed on $2. Listing sum is now $4." >> $TMP_RESULT
		echo "[$( date )] You may verify with the following commands:" >> $TMP_RESULT
		echo "dig +short $1.$2; dig TXT +short $1.$2" >> $TMP_RESULT
		echo "echo \"SELECT * FROM queries WHERE host LIKE \\\"$1\\\" AND bl LIKE \\\"$2\\\" ORDER BY time DESC LIMIT $REPORTHISTORYSIZE;\\\" | sqlite3 -line $SQLITE_DB" >> $TMP_RESULT
	else 
		echo "[$( date )] Host $1 delisted from $2 after $( displaytime $(($3 - $LISTEDTIME)) ). Listing sum is now $4." >> $TMP_RESULT
	fi
	if [[ $DEBUG -gt 0 ]]; then cat $TMP_RESULT; fi
}

querydns () {
	# Queries the blacklists
	# May use multiple DNS servers if a positive listing is returned (avoid limits)

	local QUERYTMP="$(mktemp)"

	LISTCOUNT=0
	NOTLISTCOUNT=0

	# Spread queries through all allowed servers
	for dns in $( shuf $DNS_LIST )
	do
		if [[ $DEBUG -gt 0 ]]; then echo "[$( date )] Querying $bl with $dns for $1"; fi
		dig +time=$QUERY_TIMEOUT +short @$dns $1.$2 > $QUERYTMP
		if [[ $? -eq 0 ]]
		then
			# if dig is succesful
			if [[ $( cat $QUERYTMP | wc -l ) -gt 1 ]]
			then
				# An answer with multiple entries gets converted to csv
				FULLRESULT="$(cat $QUERYTMP | tr '\n' ',' )"
				RESULT="${FULLRESULT::-1}"
			else
				# If the query returns a single result just keep the result
				RESULT="$(cat $QUERYTMP)"
			fi
			if [[ "$RESULT" != "" ]]
			then
				# If the blacklist answer is not an empty string (possibly a listing)
				# Adds to the count of listings to compare with other DNS server answers
				LISTCOUNT=$(( "$LISTCOUNT" + 1 ))
				# Try to get a description for why it has been listed
				querystore "$1" "$dns" "$2" "$RESULT" "$(date +%s)" "$( dig TXT +time=$QUERY_TIMEOUT +short @$dns $1.$2 | sed s/\"//g )"
				if [[ $DEBUG -gt 0 ]]; then echo "[$( date )] $RESULT"; fi
			else
				# If the blacklist answer is an empty string (not listed)
				# Adds to the count of negatives to compare with other DNS server answers
				NOTLISTCOUNT=$(( "$NOTLISTCOUNT" + 1 ))
				querystore "$1" "$dns" "$2" "$RESULT" "$(date +%s)" ""
				if [[ "$LISTCOUNT" -eq 0 ]]
				then
					# No need to query other DNS servers if the first query result was already negative
					break
				fi
			fi
		else
			# If the dig command fails (probably a timeout from the blacklist or DNS)
			# Store a NULL answer (undetermined)
			querystore "$1" "$dns" "$2" "$RESULT" "$(date +%s)" "NULL"
			if [[ $DEBUG -gt 0 ]]; then echo "[$( date )] $RESULT"; fi
		fi
		sleep 0.1
	done

	# Decide if result is positive or not and store it if appropriate
	
	# Listings sometimes happen due to "rate limiting" on the DNS server IP
	# that is reaching the blacklist. Common whe using public DNS servers.

	# Empty blacklist answers are weighthed as -1, otherwise as +1
	# Query timeouts or undetermined are weighted as 0
	# This way no matter how many DNSs are used, the "majority" decides
	# if a listing may be a false positive or not.

	# Won't store the result if the previous consensus was the same as the current
	# This keeps the database size and performance under control, and makes it a lot easier
	# to query the history
	if [[ "$LISTCOUNT" -eq 0 && "$NOTLISTCOUNT" -eq 0 ]]
	then
		return
	else
		LASTRESULT=$(echo "SELECT result FROM results WHERE host LIKE \"$1\" AND bl LIKE \"$2\" ORDER BY time DESC LIMIT 1;" | sqlite3 -noheader -csv $SQLITE_DB)
		LISTSUM=$(( $LISTCOUNT - $NOTLISTCOUNT ))
		if [[ ($LISTSUM -gt 0 && ($LASTRESULT -lt 0 || -z $LASTRESULT) ) || ($LISTSUM -lt 0 && $LASTRESULT -gt 0) ]]
		then
			if [[ $DEBUG -gt 0 ]]; then echo "Result change: $LASTRESULT to $LISTSUM"; fi
			resultstore "$1" "$2" "$(date +%s)" "$LISTSUM"
		else
			if [[ $DEBUG -gt 0 ]]; then echo "No change: $LASTRESULT to $LISTSUM"; fi
			return
		fi
	fi
	rm $QUERYTMP
}


main () {
	# Create default path for data
	if [[ ! -d $BASICPATH ]];
	then
		mkdir -p "$BASICPATH/lists"

		echo "You should provide a list of blacklists, dns servers and hosts. Consult the README for more information."
		exit 1
	fi

	# Create an empty database if none exists
	if [[ ! -f "$SQLITE_DB" ]]
	then
		sqlite3 "$SQLITE_DB" <<EOF
	CREATE TABLE queries (
	    "host" TEXT NOT NULL,
	    "dns" TEXT,
	    "bl" TEXT NOT NULL,
	    "answer" TEXT,
	    "time" INTEGER NOT NULL,
	    "txt" TEXT);
	CREATE TABLE results (
	     "host" TEXT NOT NULL,
	     "bl" TEXT NOT NULL,
	     "time" INTEGER NOT NULL,
	     "result" INTEGER NOT NULL);
EOF
	fi

	# Every host should be queried on every blacklist
	for bl in $( shuf $BL_LIST )
	do
		for dnshost in $( shuf $HOST_LIST )
		do
			querydns "$dnshost" "$bl"
			wait
		done
	done

	# After all queries are done, go to report phase
	sqlitereport

	# After reports are done, clear temporary and old data
	cleanup
}

main

exit 0
