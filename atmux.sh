#!/bin/bash
# vim: ft=sh ff=unix fenc=utf-8
# file: atmux.sh

tag=$1

if [ -z "$tag" ];
then
	echo "$0 [tagname] [cmd]"
	echo "Example:"
	echo " $0 bash"
	echo " $0 RUNBASH bash"
	echo " $0 RUNBASH bash -c \"'echo \\\"beep\\\"; sleep 5; exit 42'\""
	exit 1
fi

cmd=$(echo "$@" | sed -e "s/^$tag[[:space:]]*\(.*\)/\1/")

[ -z "$cmd" ] && cmd=${tag}

if [ x"$tag" = x"?" ];
then
	tag="random-tag$RANDOM:$RANDOM"
fi

tag=$(echo "$tag" | sed -e 's/[^a-zA-Z@0-9]/_/g' -e 's/\(.\{0,32\}\).*/\1/')
cfgf="/tmp/tmux-x-$tag"

[ -r "$cfgf" ] \
	&& tmux -f "$cfgf" attach-session -t "$tag"\
	|| (tmux -f "$cfgf" list-sessions 2>/dev/null | grep "^$tag:[[:space:]]")
if [ $? -ne 0 ];
then
	rm -f "${cfgf}.resultcode"
	cat >"$cfgf"<<EOF
# cmd: $cmd
unbind C-b
set -g prefix "C"
set -g mode-mouse off
set-window-option -g window-status-format ""
set-window-option -g window-status-separator ""
set-window-option -g window-status-current-format ""
set-option -g status-bg black
set-option -g status-fg blue
set-option -g pane-border-fg black
set-option -g pane-active-border-fg red
EOF
	tmux -f "$cfgf" new-session -s\
		"$tag" "($cmd) || (echo \$?>${cfgf}.resultcode)"
fi
[ -r "${cfgf}.resultcode" ] && exit `cat ${cfgf}.resultcode`
exit 0

