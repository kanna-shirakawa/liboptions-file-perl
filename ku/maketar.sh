#!/bin/bash
#
CMD=$(basename $0)
CMDVER="1.0"

set -e -u


# (MAIN)

cfgfile="ku/install"
srcdir="src"

err=false

[ -f "$cfgfile" ] || {
	echo "$CMD: config file '$cfgfile' not found" >&2
	err=true
}
[ -d "$srcdir" ] || {
	echo "$CMD: source dir '$srcdir' not found" >&2
	err=true
}
$err && {
	echo "  (wrong launch dir? you muse be in the main package dir)" >&2
	exit 1
}

name=$(grep "^:TOOLKIT\s" $cfgfile | sed -e 's/.*\s//')

VERSION=$(grep "^:VERSION\s" $cfgfile | sed -e 's/.*\s//')
RELEASE=$(grep "^:RELEASE\s" $cfgfile | sed -e 's/.*\s//')
SIGNATURE=$(grep "^:SIGNATURE\s" $cfgfile | sed -e 's/^:SIGNATURE\s*//' -e 's/[()]//g' -e 's/ /_/g')

tarfile=$(eval echo "${name}_${SIGNATURE}.tar")
out="/tmp/$tarfile.gz"

cd "$srcdir"

echo -en "\n creating tarfile ... "
tar cfz "$out" *
echo "ok"
set -- $(ls -l "$out"); shift 4
echo -e "\n $*\n"

exit 0
