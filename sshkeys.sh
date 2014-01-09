#!/bin/sh
# vim: ft=sh ff=unix fenc=utf-8
# file: sshkeys.sh

CFGD=""
# system
CFGD=$(dirname "$0")
CFGF="$CFGD/config.sh"

# load options
[ -r "$CFGF" ] && . "$CFGF"


# ssh_genkeyuser must be return zero, if no argument passed
_ssh_genkeyuser() {
	keytype="$1"
	key="$2"
	comment="$3"
	return 0
}

SSHC_INSERT=""
eval "ssh_genkeyuser" >/dev/null 2>&1
[ $? -eq 0 ] && SSHC_INSERT="ssh_genkeyuser" || SSHC_INSERT="_ssh_genkeyuser"


KEYF="$HOME/.ssh/authorized_keys"
tempf=$(tempfile) # tempfile var
templ=$(tempfile) # templine var

#
act_init() {
	sz=$(stat -c%s "$KEYF" 2>/dev/null || echo 0)
	[ $sz -eq 0 ] && touch "$KEYF"
	cat "$KEYF" >"$tempf"
}

# comment/uncomment marked
_list_post_onoff() {
	[ ! -z "$1" ] && return 0
		# normalize file. remove leading '@' and comment other
	sed -i "$tempf" -e "s/^\([^@#].*\)/#\1/" -e "s/^@[#]*\(.*\)$/\1/"
}

_list_state_onoff() {
	# with double '#': commented lines, single '#': uncommented lines
	case "$1" in
		\#\#) echo off ;;
		\#) echo on ;;
		*) echo off ;;
	esac
}

# delete all marked
_list_post_remove() {
	[ ! -z "$1" ] && return 0
	sed -i "$tempf" -e "/^@.*/d"
}

_list_state_remove() {
	case "$1" in
		\#\#) echo on ;;
		\#) echo off ;;
		*) echo off ;;
	esac
}

act_list() {
	i=0
	dr=$1
	title="$2"
	(echo "" | "_list_post_$dr" ping) 2>/dev/null
	if [ $? -ne 0 ];
	then
		echo "driver '$dr' not found" >/dev/stderr
		return 1
	fi
	cat "$tempf"\
		| sed -e 's/^\(#\)\?.*\(ssh-[^ ]*\) \([A-Za-z0-9+\/=]\{10\}\)[A-Za-z0-9+\/=]*\([A-Za-z0-9+\/=]\{7\}\) \([^ ]*\).*\|.*/\2 \3...\4 \5 #\1 /' -e '/^$/d'\
		| while read keytype key comment state;
	do
		state=$("_list_state_$dr" "$state")
		i=$(expr $i + 1)
		echo -n "$i '$keytype $key $comment' $state "
	done\
		| xargs dialog --stdout --checklist "$title" 0 0 0\
		| sed -e "s/\([0-9]*\)/-e \"\1s\/^\\\(.*\\\)$\/@\\\1\/\" /g"\
		| xargs sed -i "$tempf" -e ""
	"_list_post_$dr"
}

act_commit() {
	if dialog --defaultno --yesno "Accept changes?" 0 0;
	then
		ac=$(grep -v "^[^ ]*#" "$tempf" 2>/dev/null| wc -l)
		if [ $ac -eq 0 ];
		then
			if dialog --defaultno\
				--yesno "You have no active records in file, continue?" 0 0;
			then
				cat "$tempf" > "$KEYF"
				return 0
			else
				dialog --msgbox "good idea" 0 0
			fi
		else
			cat "$tempf" > "$KEYF"
			return 1
		fi
	fi
	return 0
}

act_add() {
	(dialog --stdout --inputbox\
		"type a ssh key with leading ssh-(rsa|dsa) and ending non-spaced comment"\
		0 79; echo)\
		| sed -e 's/.*\(ssh-\(rsa\|dsa\) [A-Za-z0-9+\/=]* [^ ]*\).*\|.*/\1/'\
			-e '/^$/d'\
		| while read line;
	do
		if [ -z "$line" ];
		then
			dialog --msgbox "You key is not correct" 0 0
			return 3
		else
			echo "$line" | while read keytype key comment;
			do
				if grep "$key" "$tempf" >/dev/null;
				then
					dialog --msgbox "Key already exists" 0 0
					return 3
				else
					dialog --msgbox "Key added" 0 0
					(
						insstring=$($SSHC_INSERT "$keytype" "$key" "$comment")
						[ ! -z "$insstring" ] && echo -n "$insstring "
						echo "$keytype $key $comment"
					) >>"$tempf"
				fi
			break
			done
		fi
		break
	done
	return 0
}

action() {
	arg=$(cat)
	case "$arg" in
		add)
			while true;
			do
				act_add
				R=$?
				[ $R -eq 3 ] && continue
				return $R
			done
			;;
		onoff)
			act_list onoff "Set keys state (on/off)"
			;;
		remove)
			act_list remove "Select keys for remove\n"\
				"! All commented lines already marked !"
			;;
		commit)
			act_commit
			return $?
			;;
		discard)
			act_init
			;;
		*)
			return 1
			break;
	esac
	return 0
}

# 1. copy file
act_init

# show menu
while true;
do
	al=$(cat "$tempf" | wc -l)
	ac=$(grep -v '^[^ ]*#' "$tempf" | wc -l)
	dialog --stdout --menu "ssh authorized keys actions\n
		records -> all=$al, active=$ac" 0 0 0\
		add "Add a new key"\
		onoff "Disable/Enable keys"\
		remove "Remove excess keys"\
		commit "Accept changes"\
		discard "Discard changes"\
		| action
	[ $? -ne 0 ] && break
done

#
rm -f "$tempf" "$templ"

