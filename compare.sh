#!/bin/bash

querydns () {
	for dns in $( cat dnslist )
	do
		echo "Summing $bl with $dns"
		echo "$dns	" "$bl	" "$(md5sum $1/$dns/$bl)" >> $1.md5
	done
	wait
}

for bl in $( cat ipv4bl )
do
	querydns "2.0.0.127" "$bl"
	querydns "1.0.0.127" "$bl"
done

exit 0
