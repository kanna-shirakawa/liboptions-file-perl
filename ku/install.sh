#!/bin/bash
#
# KUBiC Labs package install file
# based on template 1.4 (2012/10)

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

# add custom tasks here (better use custinstall.sh)

exit 0
