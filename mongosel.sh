#!/bin/bash
# vim: ft=sh ff=unix fenc=utf-8
# file: mongosel.sh

CFGD=""
# system
if [ ! -z "$EX_CONFIG_DIR" -a -d  "$EX_CONFIG_DIR" ];
then
	CFGD="$EX_CONFIG_DIR"
else
	CFGD=$(dirname "$0")
fi
CFGF="$CFGD/config.sh"

# load options
[ -r "$CFGF" ] && . "$CFGF"

# opts default
# mongo host
MONGOHOST=${MONGOHOST-"127.0.0.1:27017"}
MONGOSEL_TMP=${MONGOSEL_TMP-"/tmp/mongosel/sets"}
MONGO_DUMPS=${MONGO_DUMPS-"/tmp/mongodumps"}

# check printf
[ -x "/usr/bin/printf" ] && printf="/usr/bin/printf"
[ -x "/bin/printf" ] && printf="/usr/printf"
eval "printf ''" >/dev/null 2>&1 && alias printf="/bin/echo -n"

printf() {
	if [ x"$TERM" != x"xterm" -o x"$TERM" != x"screen" ];
	then
		$printf $@ | sed -e "s/\x1b\[\([0-9]*\)\?\(;\)\?\([0-9]*\)m//g"
	else
		$printf $@
	fi
}
#

# select mongo's set, create new
selset() {
	R=0
	while true;
	do
		mkdir -p "$MONGOSEL_TMP"
		list=$(find "$MONGOSEL_TMP" -maxdepth 1 -type f\
			| sed -e 's/\(.*\/set_\([a-z0-9@_\.]*\)\|.*\)$/\2 \2/' -e '/^ $/d'\
			| tr '\n' ' ')
		if [ -z "$list" -o x"$1" = x"new" ];
		then
			list="\#new 'create new set list' $list"
		fi
		echo "$list"
		sel=$(eval "dialog --no-tags --stdout --menu \"select mongo's set\" 0 0 0 $list")
		R=$?
		# show dialog with new set
		if [ x"$sel" = x"#new" ];
		then
			new=""
			msg="input new set name"
			while true;
			do
				new=$(dialog --stdout --inputbox "$msg\nsymbols re'[a-z0-9@_\.]'" 0 0 $new)
				[ -z "$new" ] && break
				# check
				xnew=$(echo "$new" | sed -e 's/[^a-z0-9@_\.]/_/g')
				if [ x"$xnew" != x"$new" ];
				then
					msg="check input symbols"
					new="$xnew"
					continue
				elif [ ! -e "$MONGOSEL_TMP/set_$new" ];
				then
					touch "$MONGOSEL_TMP/set_$new"
					break
				elif [ -e "$MONGOSEL_TMP/set_$new" ];
				then
					msg="already exists"
				fi
			done
			continue
		elif [ $R -eq 0 -a -z "$sel" ];
		then
			R=1
		elif [ $R -ne 0 -a ! -z "$sel" ];
		then
			sel=""
		fi
		break
	done
	echo "$sel"
	return $R
}

_genDBCOL() {
	echo "db.adminCommand('listDatabases')['databases']"\
		| mongo --quiet "$MONGOHOST/local" | grep -v '^\(admin\|config\|local\)$'\
		| sed -e 's/[[:space:]]*"name" : "\(.*\)".*\|.*/\1/' -e '/^$/d'\
		| while read dbname;
	do
		echo 'db.setSlaveOk(); db.getCollectionNames()'\
			| mongo --quiet "$MONGOHOST/$dbname"\
			| tr ' ' '\n'\
			| sed -e 's/^[[:space:]]*"\([^ ]*\)".*\|.*/\1/' -e '/^$/d'\
			| xargs -I{} echo "$dbname {}"
	done
}

editset() {
	R=0
	name="$1"
	if [ ! -r "$MONGOSEL_TMP/set_$name" ];
	then
		dialog --msgbox "set '$name' not exists or not readable" 0 0
		return 1
	fi
	tmpf=$(tempfile -p Xongo)
	tmpf_st=$(tempfile -p Xonst)
	_genDBCOL >"$tmpf"
	while true;
	do
		# select databases
		sz=$(stat -c%s "$MONGOSEL_TMP/set_$name" || echo 0)
		if [ $sz -eq 0 ];
		then
			# select only news
			# select dbs
			cat "$tmpf" | cut -d' ' -f 1 | sort | uniq\
				| xargs -I{} echo "{} {} on"\
				| tr '\n' ' ' >"$tmpf_st"
		else
			# compare
			cat "$tmpf" | cut -d' ' -f 1 | sort | uniq\
				| xargs -I{} sh -c "grep '^{}$' \"$MONGOSEL_TMP/set_$name\" >/dev/null 2>&1 && echo '{} {} on' || echo '{} {} off'"\
				| tr '\n' ' ' >"$tmpf_st"
		fi
		cat "$tmpf_st"
		sel=$(dialog --no-tags --stdout --checklist "$name -> databases" 0 0 0 `cat "$tmpf_st"`)
		R=$?
		if [ $R -eq 0 ];
		then
			# if zero select, remove list
			if [ -z "$sel" ];
			then
				rm -f "$MONGOSEL_TMP/set_$name"
			else
				echo "$sel" | tr ' ' '\n' > "$MONGOSEL_TMP/set_$name"
			fi
		else
			break
		fi
		# select collections
		cat "$tmpf"\
			| while read dbname collection;
		do
			grep "^$dbname$" "$MONGOSEL_TMP/set_${name}" >/dev/null 2>&1\
				|| continue
			if [ -e "$MONGOSEL_TMP/set_${name}%$dbname" ];
			then
				grep "^$collection$" "$MONGOSEL_TMP/set_${name}%$dbname" >/dev/null 2>&1\
					&& echo -n "$dbname:$collection $dbname:$collection on "\
					|| echo -n "$dbname:$collection $dbname:$collection off "
			else
				echo -n "$dbname:$collection $dbname:$collection on "
			fi
		done >"$tmpf_st"
		sz=$(stat -c%s "$tmpf_st" || echo "0")
		if [ $sz -eq 0 ];
		then
			R=1
			break
		fi
		sel=$(dialog --no-tags --stdout --checklist "$name -> database:collection" 0 0 0 `cat "$tmpf_st"`)
		R=$?
		# return to db select, if pressed <Cancel>
		[ $R -ne 0 ] && continue
		# return to db selection if no collection selected
		echo "$sel" | tr ' ' '\n' | cut -d':' -f 1\
			| sort\
			| uniq\
			| xargs -I{} rm -f "$MONGOSEL_TMP/set_${name}%{}"
		echo "$sel"\
			| tr ' :' '\n '\
			| while read dbname collection;
		do
			echo "$collection" >> "$MONGOSEL_TMP/set_${name}%$dbname"
			echo "$dbname"
		# remove db with zero collections from set
		done\
			| (cat "$tmpf" | cut -d' ' -f 1 | sort | uniq; cat)\
			| sort\
			| uniq -c\
			| grep -v '^[[:space:]]*1[[:space:]]'\
			| sed -e 's/^[[:space:]]*[0-9]*[[:space:]]\(.*\)/\1/'\
			> "$tmpf_st"
		cat "$tmpf_st" > "$MONGOSEL_TMP/set_${name}"
		# try reselect databases
		sz=$(stat -c%s "$MONGOSEL_TMP/set_${name}" || echo 0)
		[ $sz -eq 0 ] && continue
		# leave, select complete
		break;
	done
	# clean
	rm -f "$tmpf" "$tmpf_st"
	return $R
}

listset() {
	name="$1"
	sz=$(stat -c%s "$MONGOSEL_TMP/set_$name" 2>/dev/null || echo 0)
	[ $sz -eq 0 ] && return 1
	cat "$MONGOSEL_TMP/set_$name"\
		| while read dbname;
	do
		cat "$MONGOSEL_TMP/set_${name}%$dbname" 2>/dev/null\
			| xargs -I{} echo "$dbname {}"
	done
}

# dump all selected databses/collection to $MONGO_DUMPS dir
dumpsetin() {
	# want data on stdin: "$dbname $collection"
	trg="$MONGO_DUMPS/`date +'%d.%m.%YT%TZ%s'`"
	mkdir -p "$trg"
	cd "$trg" || return 1
	cat\
		| while read dbname collection;
	do
		printf "Dump \e[34m$dbname\e[0m[\"\e[33m$collection\e[0m\"]\n"
		mongodump -h "$MONGOHOST" -d "$dbname" -c ""
		R=$?
		[ $R -eq 0 ] && printf "Result \e[32m0\e[0m\n"
		[ $R -ne 0 ] && printf "Result \e[31m$R\e[0m\n"
	done
}

# now
#selset
#editset "ad"
listset ad | dumpsetin

