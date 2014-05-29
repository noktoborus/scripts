#!/bin/sh
# vim: ft=sh ff=unix fenc=utf-8
# file: /httpsh.sh

if [ x"$X_BEGIN" != x"yes" ];
then
	export X_BEGIN=yes
	timeout 5 $0 $@
	exit $?
fi

while read line;
do
	echo "$line" | grep "^\(.\)\?$" >/dev/null && break
	_FILE=$(echo "$line" | sed -e 's/^\(GET \(.*\) HTTP\/.*\|.*\)\(\r\|$\)/\2/')
	_HOST=$(echo "$line" | sed -e 's/^\(Host: \(.*\)\|.*\)\(\r\|$\)/\2/')
	_AENC=$(echo "$line" | sed -e 's/^\(Accept-Encoding: \(.*\)\|.*\)\(\r\|$\)/\2/')
	_ALANG=$(echo "$line" | sed -e 's/^\(Accept-Language: \(.*\)\|.*\)\(\r\|\n\)/\2/')
	_COOKIE=$(echo "$line" | sed -e 's/^\(Cookie: \(.*\)\|.*\)\(\r\|$\)/\2/')
	[ -z "$FILE" -a ! -z "$_FILE" ] && FILE=$_FILE
	[ -z "$HOST" -a ! -z "$_HOST" ] && HOST=$_HOST
	[ -z "$AENC" -a ! -z "$_AENC" ] && AENC=$_AENC
	[ -z "$ALANG" -a ! -z "$_ALANG" ] && ALANG=$_ALANG
	[ -z "$COOKIE" -a ! -z "$_COOKIE" ] && COOKIE=$_COOKIE
done

enc_gzip=$(echo "$AENC" | grep '\([^a-z]\|^\)gzip\([^a-z]\|$\)')
_lang=$(echo "$ALANG" | sed -e 's/\([a-zA-Z\-]*\).*\|.*/\1/' -e 's/-/_/')
_locale=$(locale -a | grep -im1 "^${_lang}.*\.\(utf8\|UTF-8\|UTF_8\)$")
if [ ! -z "$_locale" ];
then
	export LC_ALL=$_locale
	export LANG=$_locale
fi

printf "HTTP/1.0 200 OK\r\n"
printf "Content-Type: text/plain; charset=utf8\r\n"
[ ! -z "$enc_gzip" ] && printf "Content-Encoding: gzip\r\n"
printf "\r\n"


mongosel() {
# options
CFGF="$(dirname $0)/config.sh"
[ -r "$CFGF" ] && . "$CFGF"
MONGO_DUMPREST_STATUS=${MONGO_DUMPREST_STATUS-"/tmp/xxx"}

if [ ! -r "$MONGO_DUMPREST_STATUS" ];
then
	echo "no data"
else
	starttime=$(cat "$MONGO_DUMPREST_STATUS" | sed -e 's/^BEGIN \([0-9]*\)\|.*/\1/' -e '/^$/d' | head -n1)
	endtime=$(cat "$MONGO_DUMPREST_STATUS" | sed -e 's/^END \([0-9]*\)\|.*/\1/' -e '/^$/d' | head -n1)
	if [ -z "$starttime" ];
	then
		echo "empty syncs"
		return
	fi
	echo -n "begin time: "
	date +'%D %T' "-d@$starttime"
	# body
	cat "$MONGO_DUMPREST_STATUS"\
		| sed -e 's/^\(RESTORE\|DUMP\) \(.*\)\|.*/\2/'\
			-e '/^$/d'\
		| sort | uniq -c\
		| sed -e 's/[[:space:]]*2 \(.*\)/	<span color="green">\1<\/span>/'\
			-e 's/[[:space:]]*1 \(.*\)/	<span color="red">\1<\/span>/'
	# second uncompleted
	# end
	if [ -n "$endtime" ];
	then
		echo -n "end time: "
		date +'%D %T' "-d@$endtime"
	fi
fi
}

case "$FILE" in
	/cal)
		cal -y
		;;
	/)
cat <<EFO
<HTML>
<HEAD>
<META HTTP-EQUIV="REFRESH" CONTENT="3">
</HEAD>
<BODY>
<pre>
EFO
		mongosel
cat <<EFO
</pre>
</BODY>
</HTML>
EFO
		;;
	*)
		echo "go to http://$HOST/cal for cal for this year"
		;;
esac | ([ ! -z "$enc_gzip" ] && gzip -9 || cat)

