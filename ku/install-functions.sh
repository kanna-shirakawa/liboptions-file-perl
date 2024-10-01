#!/bin/bash
# install-functions.sh - common helpers for installation tasks
#
# VERSION 1.7 (2021-10-26)
#
# BETTER TO NOT MODIFY THIS FILE, USE custinstall.sh INSTEAD
#
# (c) 2011-2021 Lorenzo Canovi <lorenzo.canovi@kubiclabs.com>
# for copyright see /usr/share/doc/jtools/copyright

# global placeholders
#
export TOOLKIT=		# toolkit name (usually same of SOURCE)
export SOURCE=		# package name
export VERSION=		# package version
export RELEASE=		# package release
export SIGNATURE=	# package signature
export drelease=	# package release (debian, "." -> "-")
export prefix=		# installation prefix, default: /usr
export etcdir=		# etc dir, default: /etc
export confdir=		# config dir, default: /etc/$TOOLKIT
export libdir=		# lib dir, default: /usr/lib/$TOOLKIT
export bindir=		# bin dir, default: /usr/bin
export sbindir=		# sbin dir, default: /usr/sbin
export docdir=		# doc dir, default: /usr/share/doc/$TOOLKIT
export sharedir=	# share dir, default: /usr/share/$TOOLKIT
export maintainer=	# maintainer email
export homepage=	# web project homepage
export description=	# package description
export copy1=		# copyright (string 1)
export copy2=		# copyright (string 2)

# actual timestamp
#
export today=$(date)
export dtoday=$(date -R)		# for debian changelog
export rtoday=$(date '+%a %b %d %Y')	# for rpm changelog


# internals
#
default_owner="root:root"
default_mode="644"
tempinstall=$(mktemp /tmp/install-XXXXXXXXXXX)



# (FUNCTIONS)


set_defaults()
{
	[ "$TOOLKIT" == "" ] && {
		echo "error: must define \$TOOLKIT (package name)" >&2
		return 1
	}
	SOURCE=${SOURCE:-$TOOLKIT}

	prefix=${prefix:-/usr}
	confdir=${confdir:-/etc/$TOOLKIT}	# confs always under /etc!
	drelease=$(echo $RELEASE | tr '.' '-')

	if [ "$prefix" == "/" -o "$prefix" == "/usr" ]
	then
		# LSB standards
		#
		etcdir=${etcdir:-/etc}
		libdir=${libdir:-/usr/lib/$TOOLKIT}
		docdir=${docdir:-/usr/share/doc/$TOOLKIT}
		sharedir=${sharedir:-/usr/share/$TOOLKIT}
		bindir=${bindir:-$prefix/bin}		# /bin or /usr/bin
		sbindir=${sbindir:-$prefix/sbin}	# /sbin or /usr/sbin
	else
		# custom destinations, eg: /opt/packagename
		#
		etcdir=${etcdir:-$prefix/etc}
		bindir=${bindir:-$prefix/bin}
		sbindir=${sbindir:-$prefix/sbin}
		libdir=${libdir:-$prefix/lib}
		docdir=${docdir:-$prefix/docs}
		sharedir=${sharedir:-$prefix/share}
	fi
	return 0
}

## === installfile filename dest [owner [mode [NOPARSE]]] ===
##
## copy source filename to dest as target filename; if source
## file is /dev/null an empty destination file will be created
##
## if dest ends with slash (/) it will be used as directory
## with the original filename appended
##
## . owner format is "user:group", defaults to "root:root"
## . mode format is octal perms, defaults to "644"
##
## the content of env $DESTDIR variable, if defined, is
## prepended to dest
##
## source files will be processed and a set of pseudo_variables
## will be substituted with the equivalent environment variables
##
## the syntax of pseudo_vars is __NAME__ ---> $NAME; for
## historical reason some are __name__ ---> $NAME (see sed commmand
## below for details)
## note! this isn't a generic env parser, only a predefined set of
## variables are substituted, again, look at sed command for details
##
## the keyword NOPARSE will prevent this, note that is not
## possibile to pass NOPARSE keyword without passing owner and
## mode parms
## 
installfile()
{
	local file=$1
	local dest=$2
	local own="root:root"
	local perms="644"

	shift 2
	[ $# != 0 ] && { own=$1; shift; }
	[ $# != 0 ] && { perms=$1; shift; }

	local realdest=$dest
	local descdest=$dest
	local nullfile=false
	local dir=
	local parse="true"

	# additional parms
	#
	[ X$1 == X"NOPARSE" ] && { parse="false"; shift; }

	case $file in
	  /dev/null|null)
	  	nullfile=true
		;;
	  *)
		[ -f "$file" ] || {
			echo "(installfile) can't find file '$file'" >&2
			return 1
		}
		;;
	esac

	[ x"$DESTDIR" != "x" ] && {
		realdest="$DESTDIR$dest"
		descdest="<D>$dest"
	}

	# destination is a directory?
	#
	if [ -d "$realdest" ]
	then
		if echo "$realdest" | grep -q "/$"
		then
			$nullfile && {
				echo "error, you must supply a filename if source is /dev/null" >&2
				return 1
			}
			realdest="$realdest$(basename $file)"
		else
			echo "installing file '$file' to '$dest'" >&2
			echo "destination '$realdest' is a directory" >&2
			return 1
		fi
	else
		if echo "$realdest" | grep -q "/$"
		then
			echo -e	"error: you asked to install '$file' into '$realdest'\n" \
				"but destination is not a directory" >&2
			return 1
		fi
	fi

	local flags=
	$nullfile	&& flags="N"
	$parse		&& flags="P"


	printf " %-30s %-1s %-14s -> %s\n" "$file" "$flags" "$perms $own" "$descdest" >&2

	if $nullfile
	then
		:>"$realdest"
	else
		if $parse
		then
		    # parse file to destination
		    #
		    sed \
			-e "s#__maintainer__#$maintainer#g" \
			-e "s#__homepage__#$homepage#g" \
			-e "s#__description__#$description#g" \
			-e "s#__today__#$today#g" \
			-e "s#__dtoday__#$dtoday#g" \
			-e "s#__rtoday__#$rtoday#g" \
			-e "s#__copy1__#$copy1#g" \
			-e "s#__copy2__#$copy2#g" \
			-e "s#__SOURCE__#$SOURCE#g" \
			-e "s#__TOOLKIT__#$TOOLKIT#g" \
			-e "s#__TOOLKIT_VERSION__#$VERSION#g" \
			-e "s#__TOOLKIT_RELEASE__#$RELEASE#g" \
			-e "s#__TOOLKIT_SIGNATURE__#$SIGNATURE#g" \
			-e "s#__drelease__#$drelease#g" \
			-e "s#__PREFIX__#$prefix#g" \
			-e "s#__CONF__#$confdir#g" \
			-e "s#__LIB__#$libdir#g" \
			-e "s#__BIN__#$bindir#g" \
			-e "s#__SBIN__#$sbindir#g" \
			-e "s#__ETC__#$etcdir#g" \
			-e "s#__DOC__#$docdir#g" \
			-e "s#__SHARE__#$sharedir#g" \
			"$file" >"$realdest" || {
				echo "install to '$realdest' failed" >&2
				return 1
			}
		else
			cp "$file" "$realdest" || {
				echo "install(NOPARSE) to '$realdest' failed" >&2
				return 1
			}
		fi
	fi

	chown $own "$realdest"
	chmod $perms "$realdest"

	return 0
}


## === create_dir path user:group [mode] ===
##
## create a directory with parent path if needed
##
## if jtmkpath command is available, use it to create intermediate
## directories in a smart way (obeyng cascade owners/perms), otherwise
## current user and perms are used
##
create_dir()
{
	local path=$DESTDIR$1
	local user=$2
	local mode=${3:-"0750"}
	local dir=

	# first run, create dir if not exists, with full path if needed
	# secon run, fix perms (always executed)
	#
	if [ "$(which jtmkpath)" != "" ]
	then
		jtmkpath -v $fixperms $path $user $mode || return $?
		jtmkpath --fixperms $path $user $mode || return $?
	else
		[ -d "$path" ] || {
			mkdir -p $path || return $?
		}
		chown $user $path || return $?
		chmod $mode $path || return $?
	fi

	return 0
}




# read install file and set vars
#
set_vars()
{
	local remain=
	local file=
	local owner=
	local perms=
	local files=

	# whipe out comments and empty lines
	#
	sed -e 's/[ ,	]*#.*//' -e 's/^[ ,	]*$//' -e '/^$/d' \
		ku/install >$tempinstall

	exec 9<&0 <$tempinstall
	while read tag line
	do
		echo "$line" | fgrep -q '$' && eval line=\"$line\"

		case "$tag" in
		  :TOOLKIT)	TOOLKIT="$line"; continue ;;
		  :SOURCE)	SOURCE="$line"; continue ;;
		  :VERSION)	VERSION="$line"; continue ;;
		  :RELEASE)	RELEASE="$line"; continue ;;
		  :SIGNATURE)	SIGNATURE="$line"; continue ;;
		  :prefix)	prefix="$line"; continue ;;
		  :etcdir)	etcdir="$line"; continue ;;
		  :bindir)	bindir="$line"; continue ;;
		  :libdir)	libdir="$line"; continue ;;
		  :docdir)	docdir="$line"; continue ;;
		  :sharedir)	sharedir="$line"; continue ;;
		  :confdir)	confdir="$line"; continue ;;
		  :maintainer)	maintainer="$line"; continue ;;
		  :homepage)	homepage="$line"; continue ;;
		  :description)	description="$line"; continue ;;
		  :copy1)	copy1="$line"; continue ;;
		  :copy2)	copy2="$line"; continue ;;
		esac
	done
	exec 0<&9 9<&-

	# update vars
	set_defaults || return $?

	echo >&2
	echo "settings" >&2
	echo "  TOOLKIT:     $TOOLKIT $VERSION $RELEASE - $SIGNATURE" >&2
	echo "  SOURCE:      $SOURCE" >&2
	echo "  prefix:      $prefix" >&2
	echo "  etcdir:      $etcdir" >&2
	echo "  confdir:     $confdir" >&2
	echo "  libdir:      $libdir" >&2
	echo "  bindir:      $bindir" >&2
	echo "  sbindir:     $sbindir" >&2
	echo "  docdir:      $docdir" >&2
	echo "  sharedir:    $sharedir" >&2
	echo "  maintainer:  $maintainer" >&2
	echo "  homepage:    $homepage" >&2
	echo "  description: $description" >&2
	echo "  copy1:       $copy1" >&2
	echo "  copy2:       $copy2" >&2
	echo >&2

	return 0
}



# read 'install' file and create directories
#
create_dirs()
{
	local file=
	local owner=
	local perms=
	local files=

	echo -e "\ncreating dirs ..." >&2

	exec 9<&0 <$tempinstall
	while read tag path owner perms remain
	do
		owner=${owner:-$default_owner}
		perms=${perms:-$default_mode}

		eval path=$path

		case "$tag" in
		  :default_owner) default_owner=$path; continue ;;
		  :default_mode) default_mode=$path; continue ;;
		  :dir)		create_dir $path $owner $perms || return $?
				continue
				;;
		esac
	done
	exec 0<&9 9<&-
	return 0
}

# read 'install' and install files
#
install_files()
{
	local default_parse="true"
	local otherparms=
	local file=
	local owner=
	local perms=
	local files=

	create_dirs || return $?

	echo -e "\ninstall files, DESTDIR=$DESTDIR ..." >&2

	exec 9<&0 <$tempinstall
	while read file dest owner perms otherparms
	do
		file=$(echo "$file" | sed -e 's/[ ,	]*#.*//')
		owner=${owner:-$default_owner}
		perms=${perms:-$default_mode}
		line="$dest $owner $perms $otherparms"

		eval dest=$dest

		case "$file" in
		  :default_owner) default_owner=$dest; continue ;;
		  :default_mode) default_mode=$dest; continue ;;
		  :*)		continue ;;
		  *.tmp)	continue ;;
		  "")		continue ;;
		esac
		files=$(ls $file 2>/dev/null) || {
			echo "error: '$file' does not expand to valid filename(s)" >&2
			echo "line: $line" >&2
			return 1
		}
		for file in $files
		do
			installfile "$file" "$dest" "$owner" "$perms" $otherparms || return $?
		done
	done
	exec 0<&9 9<&-

	rm -f $tempinstall
	return 0
}


make_control_files()
{
	local distro=
	local mode=

	[ -f ku/history -a "$(which jtchangelog-build)" != "" ] && jtchangelog-build

	for distro in debian fedora
	do
		if [ -d $distro.in ]
		then
			echo "pre-processing $distro control files ..." >&2
			for file in $(ls $distro.in | grep -v '\.in$')
			do
				if [ -x "$distro.in/$file" ]
				then
					mode=775
				else
					mode=664
				fi

				installfile "$distro.in/$file" $distro/ $LOGNAME $mode || {
					rm -f $tempinstall
					exit $?
				}
			done
		fi
	done
	return 0
}

check_env()
{
	[ x"$DESTDIR" == x ] && {
		echo -e "
	error, you must define \$DESTDIR
	eg: make install DESTDIR=/tmp/abcd
		" >&2
		return 1
	}
	return 0
}




# (MAIN)

trap "rm -f $tempinstall; exit 255" 1 2 3

set_vars || return $?
