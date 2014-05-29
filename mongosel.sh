#!/bin/bash
# vim: ft=sh ff=unix fenc=utf-8
# file: mongosel.sh

CFGD=""
FPWD="`pwd`"
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
MONGORHOST=${MONGORHOST-"$MONGOHOST"}
MONGOSEL_TMP=${MONGOSEL_TMP-"/tmp/mongosel/sets"}
MONGO_DUMPS=${MONGO_DUMPS-"/tmp/mongodumps"}
MONGO_MENU=${MONGO_MENU-"edit dump sync lrest rest"}
MONGO_DUMPREST_STATUS=${MONGO_DUMPREST_STATUS-""}

# check printf
[ -x "/usr/bin/printf" ] && printf="/usr/bin/printf"
[ -x "/bin/printf" ] && printf="/usr/printf"
eval "printf ''" >/dev/null 2>&1 && alias printf="/bin/echo -n"

pause() {
	echo "Press Enter to continue..." >&2
	read _x
}

xisterm() {
	[ x"$TERM" = x"xterm" -o x"$TERM" = x"screen" ]
	return $?
}

xprintf() {
	if xisterm;
	then
		$printf "$*"
	else
		$printf "$*" | sed -e "s/\x1b\[\([0-9]*\)\?\(;\)\?\([0-9]*\)m//g"
	fi
}

#
initfirst() {
	cd "$FPWD"
}

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
		| mongo --quiet "$MONGOHOST/local"\
		| sed -e 's/[[:space:]]*"name" : "\(.*\)".*\|.*/\1/' -e '/^$/d'\
		| grep -v '^\(admin\|config\|local\)$'\
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
	xprintf "Listing \e[34m$name\e[0m\n" >&2
	cat "$MONGOSEL_TMP/set_$name"\
		| while read dbname;
	do
		cat "$MONGOSEL_TMP/set_${name}%$dbname" 2>/dev/null\
			| xargs -I{} echo "$dbname {}"
	done
	xprintf "End listing \e[34m$name\e[0m\n" >&2
}

seldump() {
	cd "$MONGO_DUMPS" || return 1
	find -maxdepth 1 -type d -name '*T*Z*_*' | sed 's/^\.\///' | sort -rh\
		| while read name;
	do
		echo -n "$name "
		echo "$name" | sed -e 's/.*Z\([0-9]*\)_\(.*\)/\1 \2/'\
			| while read z n;
		do
			z=$(date +"%T %D" "-d@$z")
			echo "'$n [$z]'"
		done
	done | xargs dialog --stdout --no-tags --menu "select dump" 0 0 0 && echo
}

# dump all selected databses/collection to $MONGO_DUMPS dir
dumpsetin() {
	sel="$1"
	# want data on stdin: "$dbname $collection"
	tdir="`date +'%d.%m.%YT%TZ%s'`_$sel"
	trg="$MONGO_DUMPS/$tdir"
	R=0
	mkdir -p "$trg"
	cd "$trg" || return 1
	cat\
		| while read dbname collection;
	do
		xprintf "Dump \e[34m$dbname\e[0m[\"\e[33m$collection\e[0m\"]\n" >&2
		mongodump -h "$MONGOHOST" -d "$dbname" -c "$collection" >&2
		R=$?
		[ $R -eq 0 ] && xprintf "Result \e[32m0\e[0m\n" >&2
		if [ $R -ne 0 ];
		then
			echo "FAIL"
			xprintf "Result \e[31m$R\e[0m\n" >&2
			break
		fi
		# set statuses
		echo "DUMP ${dbname}:${collection}" >> "dumprest"
	done | grep 'FAIL' >/dev/null && R=1
	if [ $R -eq 0 ];
	then
		echo "$tdir"
	else
		cd
		rm -rf "$trg"
	fi
	return $R
}

restore() {
	trg="$MONGO_DUMPS/$1"
	host="$2"
	_logf="$MONGOSEL_TMP/restore_`date +%s`.log"
	tpid=""
	echo "Q $trg : $host" >&2
	cd "$trg" || return 1
	echo "db.hostInfo()" | mongo "$host/local" >/dev/null || return 1
	# get ns `in work`
	if [ -n "$MONGO_DUMPREST_STATUS" ];
	then
		[ -r "dumprest" ] && cat dumprest > "$MONGO_DUMPREST_STATUS"
		(tail -F "$_logf"\
			| sed -u -e 's/.*going into namespace \[\(.*\)\]\|.*/\1/'\
				-e '/^$/d'\
				-e 's/\([^\.]*\)\.\(.*\)/RESTORE \1:\2/'\
				>> "$MONGO_DUMPREST_STATUS") 2>&1 | cat >/dev/null &
		tpid="$!"
	fi
	tail -F "$_logf" >&2&
	tpid="$tpid $!"
	# restore
	if xisterm;
	then
		# add colors
		mongorestore --drop -h "$host"\
			| sed -ue 's/^\([0-9\-]\{10\}\)T\([0-9:\.]\{12\}\)/\x1b[33m\1\x1b[0mT\x1b[32m\2\x1b[0m/'\
				-e 's/\([+-][0-9]*\) \([^ ]*\)$/\1 \x1b[0m\x1b[34m\2\x1b[0m/'\
				-e 's/\([ ]*dropping\)$/\x1b[35m\1\x1b[0m/'\
			> "$_logf" 2>&1
	else
		# simple restoring
		mongorestore --drop -h "$host" > "$_logf" 2>&1
	fi
	R=$?
	# drop garbage
	[ -n "$tpid" ] && kill -9 $tpid
	echo "$_logf" >&2
	rm -f "$_logf"
	# exit
	return $R
}

xrest() {
	host="$1"
	sel=$(seldump)
	if [ ! -z "$sel" ];
	then
		restore "$sel" "$host"
		if [ $? -ne 0 ];
		then
			echo "fail on $sel"
			pause
			break
		else
			pause
		fi
		echo "restoration completed"
	fi
}

menu() {
	act="$1"
	case "$act" in
		edit)
			sel=$(selset new)
			[ ! -z "$sel" ] && editset "$sel"
			;;
		dump)
			sel=$(selset)
			if [ ! -z "$sel" ];
			then
				listset "$sel" | dumpsetin "$sel" || pause
				echo "dump atata"
			fi
			;;
		sync)
			# 1. select set
			sel=$(selset new)
			if [ ! -z "$sel" ];
			then
				# 2. dump
				sel=$(listset "$sel" | dumpsetin "$sel")
				if [ ! -z "$sel" ];
				then
					# 3. restore
					restore "$sel" "$MONGORHOST" || pause
					echo "sync complete"
				else
					echo "dump fail" >&2
					pause
				fi
			fi
			;;
		rest)
			xrest "$MONGOHOST"
			;;
		lrest)
			xrest "$MONGORHOST"
			;;
		*)
			return 1
			;;
	esac
	return 0
}

genmenu() {
	MENU="$1"
	_SR="edit 'Editing/Create dump sets'
		dump 'Begin dump select set'
		sync 'Sync data on slave server to master'
		lrest 'Restore to slave server'
		rest 'Restore to master server'"
	for q in $MENU;
	do
		echo $q >&2
		echo $_SR | sed "s/.*\($q[[:space:]]'[^']*'\).*\|.*/\1/" | tr '\n' ' '
	done
}

if [ -z "$1" ];
then
	XRE="cheese"
	while true;
	do
		_n=$(genmenu "$MONGO_MENU")
		initfirst
		sel=$(eval "dialog --stdout --menu '$XRE' 0 0 0 $_n")
		_XRE=$(menu "$sel")
		[ $? -ne 0 ] && break
		[ ! -z "$_XRE" ] && XRE="$_XRE"
	done
	exit 0
elif [ x"$1" = x"dump" -a ! -z "$2" ];
then
	listset "$sel" | dumpsetin "$sel"
else
	echo "Usage:"
	echo "$0 [dump <setname>]"
	echo "Example:"
	echo "$0"
	echo "$0 dump set1"
fi

