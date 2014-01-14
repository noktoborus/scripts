#!/bin/sh
# vim: ft=sh ff=unix fenc=utf-8
# file: menu.sh

scriptd=`dirname $0`
XUSER=${1-"-"}

[ -e "$scriptd/ENV_${USER}.sh" ] && . "$scriptd/ENV_${USER}.sh"
[ -e "$scriptd/ENV_${USER}_${XUSER}.sh" ] && . "$scriptd/ENV_${USER}_${XUSER}.sh"

# usage:
# run_tmux <name> <user> <cmd>
# _SHELL=/bin/sh run_tmux <name> <user> <cmd>
run_tmux() {
	name=$1
	cmd="$3 $4 $5 $6 $7 $8 $9"
	sock="$2"
	if [ x"$sock" != x"-" ];
	then
		name="$sock@$name"
		sock="$sock"
	else
		sock="default"
	fi
	if [ ! -z "$_SHELL" ];
	then
		mkdir -p /tmp/tmux-$UID
		cfgf="/tmp/tmux-$UID/${sock}@$name.conf"
		if [ ! -e "$cfgf" ];
		then
			echo "set -g default-shell $_SHELL" >>"$cfgf"
			echo "set -g default-command $_SHELL" >>"$cfgf"
		fi
		[ -r "$cfgf" ] && touch "$cfgf"
		tmux -L "$sock" -f "$cfgf" attach-session -t "$name" 2>/dev/null\
			|| tmux -L "$sock" -f "$cfgf" new-session -s "$name" "$cmd"
	else
		tmux -L "$sock" attach-session -t "$name" 2>/dev/null\
			|| tmux -L "$sock" new-session -s "$name" "$cmd"
	fi
	tmux -L "$sock" attach-session -t "$name" 2>/dev/null || tmux new-session -s "$name" "$cmd"
	return $?
}

export EDITOR=nano

action() {
	act="$1"
	case "$act" in
	supervisorctl)
		supervisorctl
		;;
	crontab)
		crontab -e
		;;
	shell)
		run_tmux shell "$XUSER" "$SHELL -l"
		;;
	mongoset)
		"$scriptd/mongosel.sh"
		;;
	sshkeys)
		"$scriptd/sshkeys.sh"
		;;
	deploy)
		if [ ! -x "$HOME/etc/deploy.sh" ];
		then
			dialog --msgbox "${HOME}/etc/deploy.sh must be exists and have +x flag\ntouch ~/etc/deploy.sh && chmod +x ~/etc/deploy.sh"\
				0 0
		else
			run_tmux deploy - "$HOME/etc/deploy.sh"
		fi
		;;
	HELP)
		if [ -r "$HOME/README" ];
		then
			dialog --textbox "$HOME/README" 0 0
		elif [ -r "$scriptd/README" ];
		then
			dialog --textbox "$scriptd/README" 0 0
		else
			dialog --msgbox "README file not present :(" 0 0
		fi
		;;
	*)
		return 1
		;;
	esac
	return 0
}

while true;
do
	act=$(dialog --help-button --stdout --menu "Welcome to `hostname`" 0 0 0\
		shell "run shell"\
		supervisorctl "manage supervisord's tasks"\
		crontab "edit crontab"\
		mongoset "configure mongo's sets"\
		sshkeys "manange ssh authorized keys"\
		deploy "run deploy script"
		)
	action $act || break
done
clear
echo "good bye"

