#!/bin/sh
# vim: ft=sh ff=unix fenc=utf-8
# file: menu.sh

scriptd=`dirname $0`
XUSER=${1-"-"}

run_tmux() {
	name=$1
	cmd="$3 $4 $5 $6 $7 $8 $9"
	[ x"$2" != x"-" ] && name="$2@$name"
	tmux attach-session -t $name 2>/dev/null || tmux new-session -s $name "${cmd}"
	return $?
}

export EDITOR=nano

action() {
	act="$1"
	case "$act" in
	crontab)
		crontab -e
		;;
	shell)
		run_tmux shell "$XUSER" "$SHELL"
		;;
	mongoset)
		"$scriptd/mongosel.sh"
		echo $?
		sleep 50123123
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
		crontab "edit crontab"\
		mongoset "configure mongo's sets"\
		sshkeys "manange ssh authorized keys"\
		deploy "run deploy script"
		)
	action $act || break
done
clear
echo "good bye"

