#!/bin/bash
#
# VERSION 1.5 (2021-10-26)
#
# BETTER TO NOT MODIFY THIS FILE, USE custinstall.sh INSTEAD
#
#
# (c) 2011-2021 Lorenzo Canovi <lorenzo.canovi@kubiclabs.com>
# for copyright see /usr/share/doc/jtools/copyright
#
set -e

. ku/install-functions.sh

[ "x$1" == "xmake_controls" ] && {
	make_control_files
	rm -f $tempinstall
	exit 0
}

check_env || exit 1

install_files

# automatically source custom install script
#
[ -f ku/custinstall.sh ] && {
	echo -e "\nsourcing custom install script: ku/custinstall.sh\n"
	. ku/custinstall.sh
}

exit 0
