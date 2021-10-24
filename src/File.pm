# (c) 1994-2013 Lorenzo Canovi <lorenzo.canovi@kubiclabs.com>
# released under LGPL v.2
#
package	Options::File;
use	Carp;
use	strict;
use	vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

##use	Options::Parser;		# (not yet implemented)
##use	Debug::Tracer;			# (used only on developement)

require Exporter;

@ISA		= qw(Exporter);
@EXPORT		= qw();
@EXPORT_OK	= qw();
$VERSION	= "2.8";

my $CFGFILE	= "";


1;


my $SUPER		= "<super>";	# special keyword for inerithance
my $BLOCKTAG		= "^^BLOCK^^";	# special keyword for block start/stop


#	- l'oggetto e` definito come anonimous hash
#	- i primi valori definiti sono quelli impostabili dall'esterno
#	- i valori preceduti da _ non dovrebbero mai essere modificati a mano
#	- l'elemento con chiave "_data" e` un reference ad un altro anonimous hash
#	  che contiene i dati letti dal/dai profiles
#
#	- l'hash puntato da "_data" e` a sua volta un hash di hashes, un hash per
#	  ogni sezione trovata nel profile, gli elementi sono i valori veri e propri
#	  (vedere la funzione DUMP per l'accesso a questi dati)
#
sub new {
	my $class	= shift;
	my $self	= {};
	confess( "method usage: new( name [, parms] )" )	if ($#_ < 0);
	my $name	= shift;

	bless $self, $class;

	$self->{NAME}		= $name;
	$self->{MERGE}		= 0;
	$self->{CASE}		= '';
	$self->{PRELOAD}	= '';
	$self->{SEPARATOR}	= ' ';
	$self->{SEPEXPR}	= '\s+';
	$self->{COMMENT}	= '#';
	$self->{LCOMMENT}	= ';';
	$self->{INERITH}	= 1;
	$self->{DEFSECTION}	= "common";
	$self->{QUOTEVAL}	= '';

	$self->{ERROR}		= '';		# last error message
	$self->{DEBUG}		= 0;
	$self->{REALSECT}	= '';		# sezione reale se valore ereditato

	$self->{_current}	= '';		# path completo file corrente
	$self->{_path}		= [];		# (lista) directories di search dei profiles
	$self->{_loaded}	= 0;		# flag, true=file caricato
	$self->{_modified}	= 0;		# flag, true=valori modificati dall'ultimo caricamento
	$self->{_data}		= {};		# loaded data hash array
	$self->{_sections}	= [];		# sections list

	my $HOME	= $ENV{HOME} ? $ENV{HOME} : "";
	my $PRJ		= $ENV{PRJ}  ? $ENV{PRJ}  : $HOME;
	my $PATH	= $ENV{PATH} ? $ENV{PATH} : "";

	while (@_) {
		confess( "no value for parameter '$_[0]'" )	if (@_ == 1);
		my $opt	= shift;
		my $val	= shift;

		if ($opt eq "TYPE" && $val eq "LINUX") {
			unshift( @_,
				'PATH',		"$HOME:$PRJ/etc:/etc:$PATH", 
				'MERGE',	1
			);
			next;
		}
		if ($opt eq "TYPE" && $val eq "LINUX2") {
			unshift( @_,
				'PATH',		"$HOME:$PRJ/etc/:etc:$PATH",
				'MERGE',	1,
				'SEPARATOR',	' = ',
				'SEPEXPR',	'\s*=\s*',
				'DEFSECTION',	'global',
			);
			next;
		}
		if ($opt eq "TYPE" && $val eq "SHELL") {
     			unshift( @_,
				'PATH',		"$HOME:$PRJ/etc:/etc:$PATH",
				'MERGE',	0,
				'SEPARATOR',	"=",
     				'SEPEXPR',	"=",
     				'QUOTEVAL',	"'",
     				'DEFSECTION',	"",
			);
			next;
		}
		if ($opt eq "TYPE" && $val eq "WIN") {
			unshift( @_,
				'PATH',		"c:/windows:c:/etc:$PATH",
				'INERITH',	0,
				'CASE',		'upcase',
				'SEPARATOR',	'=',
			);
			next;
		}
		if ($opt eq "TYPE") {
			confess( "invalid TYPE '$val'" );
		}


		if ($opt eq "PATH") {
			$self->path_unshift( 'RESET', split( /[:;]/, $val ) );
			next;
		}

		if ($opt eq "CASE") {
			$self->{DEFSECTION}	= "COMMON";
		}
			
		confess( "invalid parameter '$opt'" )		if (!exists $self->{$opt});

		$self->{$opt}	= $val;
	}

	if ($self->{PRELOAD}) {
		if (! -f $self->{PRELOAD} || ! -r _) {
			confess( "preload file $self->{PRELOAD} not found or not readable" );
		}
		$self->{'_current'}	= $self->{PRELOAD};
		$self->_parse_current();
		$self->{'_current'}	= '';
	}
	$self->dtrace( 2, "object created" );
	$self->dtrace( 2, " env proposals:" );
	$self->dtrace( 2, "  HOME: '$HOME'" );
	$self->dtrace( 2, "  PRJ:  '$PRJ'" );
	$self->dtrace( 2, "  PATH: '$PATH'" );
	$self->dtrace( 2, " _path: " . join( ", ", @{$self->{_path}} ) );

	return $self;
}




#	aggiunge o append lista a path di ricerca, se 1o parametro = RESET
#	resetta prima la lista
#
sub path_unshift {
	_path_add_append( @_, 'add' );
	$_[0];
}
sub path_push {
	_path_add_append( @_, 'append' );
	$_[0];
}
sub _path_add_append {
	my $self	= shift;
	my $mode	= pop;

	if ($_[0] eq "RESET") {
		$self->dtrace( 6, "searchpath, resetting" );
		$self->{_path}	= [];
		shift;
	}
	if ($mode eq "add") {
		$self->dtrace( 6, "searchpath, insert at begin: " . join(",",@_) );
		unshift( @{ $self->{_path} }, @_ );
	} else {
		$self->dtrace( 6, "searchpath, appending: " . join(",",@_) );
		push( @{ $self->{_path} }, @_ ) ;
	}
	$self->_normalize_path();
	$self;
}
sub _normalize_path {
	my $self	= shift;
	my $dir;
	my $newpath	= [];
	my %check;

	$self->dtrace( 1, "normalizing search path ..." );
	$self->dtrace( 2, "  before=" . join( " ", @{$self->{_path}} ) );

	for $dir (@{$self->{_path}}) {
		if (defined $check{$dir}) {
			$self->dtrace( 2, "   skip $dir, already in list" );
			next;
		}
		if (! -d $dir) {
			$self->dtrace( 2, "   skip $dir, not existent" );
			next;
		}
		if (! -r $dir) {
			$self->dtrace( 2, "   skip $dir, not readable" );
			next;
		}
		push( @$newpath, $dir );
		$check{$dir}	= 1;
	}
	$self->{_path}	= $newpath;
	$self->dtrace( 2, "   after=" . join( ", ", @$newpath ) );

	$self->{ERROR} = "no dirs in searchpath"	if (!scalar(@$newpath));
	$self;
}


#	cerca il file da leggere, se passato array usa questo come path di ricerca,
#	altrimenti usa il path definito internamente
#
sub search {
	my $self	= shift;
	my (@path)	= @_;
	my $file;

	$self->{ERROR}		= "";
	$self->{_current}	= undef;

	foreach $file ($self->_filelist( $self->{'NAME'}, @path )) {
		if (-f $file) {
			$self->{_current}	= $file;
			$self->dtrace( 3, "  found   $file" );
			return $self;	# OK
		}
		$self->dtrace( 4, "  notfnd  $file" );
	}
	$self->{ERROR}	= "$self->{NAME}: file not found";
	return undef;			# not found
}


sub current {
	return $_[0]->{_current} ? $_[0]->{_current} : undef;
}

sub _filelist {
	my $self	= shift;
	my $name	= shift;
	my $path	= \@_;
	   $path	= $self->{_path}	if (!@_);
	
	my @outpath	= ();
	
	#	absolute pathname, returns itself
	#
	if ($name =~ /^\//) {
		push( @outpath, $name );
		return @outpath;
	}

	if (!scalar(@$path)) {
		$self->{ERROR} = "no searchpath defined or no valid dirs found in searchpath";
		return;
	}

	my $dir;
	my $file;
	my $HOME	= $ENV{HOME} ? $ENV{HOME} : "";

	for $dir (@$path) {
		if ($dir eq $HOME) {
			$file	= $name;
			$file	=~ s/\.[^.]+$//;
			$file	= "$dir/.$file";
		} else {
			$file	= "$dir/$name";
		}
		push( @outpath, $file );
	}
	return @outpath;
}




#	Legge il file, se merge=0 cerca il primo nel path, altrimenti
#	legge in sequenza tutti quelli che trova, usando il path di
#	ricerca all'indietro (quindi da quello piu` generico a quello
#	piu` specifico).
#	In {_current} si trova il nome dell'ultimo file letto.
#
sub read {
	my $self	= shift;
	my $status	= 0;

	if (@_ == 1) {
		$self->{'NAME'}	= $_[0];
		$self->{_current} = undef;
	}

	$self->dtrace( 3, "try file  $self->{'NAME'} ..." );

	if (!$self->{MERGE} || $self->{'NAME'} =~ /^\//) {
		if (!$self->{_current} && !$self->search()) {
			$self->dtrace( 3, " direct read, file not found (not loaded)" );
			return undef;	# not found, so not loaded!
		}
		$self->dtrace( 3, " current= $self->{_current}" );
		$self->_parse_current();
		$status = 1;
	} else {
		my $path;
		my @spath	= @{ $self->{_path} };
		if (!scalar(@spath)) {
			$self->{ERROR} = "no searchpath defined or no valid dirs found in searchpath";
			return undef;
		}
		while ($path = pop(@spath)) {
			if ($self->search( $path )) {
				$self->_parse_current();
				$status	= 1;
			}
		}
	}
	$self->dtrace( 8, $self->DUMP() );
	return $self	if ($status);
	return undef;
}

sub _parse_current {
	my $self	= shift;

	open( CFGFILE, $self->{_current} )	or confess( "can't read $self->{_current}: $!" );

	$self->dtrace( 1, " parsing  $self->{_current}" );

	my $comment	= $self->{'COMMENT'};
	my $escomnt	= "<__EsC_CoMmEnT__>";
	my $section	= $self->new_section();
	my $lineno	= 0;
	my $separator	= $self->{'SEPARATOR'};
	my $sepexpr	= $self->{'SEPEXPR'} ? $self->{'SEPEXPR'} : $separator;
	my $in_block	= 0;

	# 2014.02 kanna
	#	key modifiers
	#
	my $f_def	= 0;	# - assign value only if not yet defined
	my $f_add	= 0;	# + append value to existing one, prepended by one space 
	my $f_cat	= 0;	# > append value to existing one, no prepended space

	my $inbuf	= "";

	$self->{ERROR}	= "";

	while (<CFGFILE>) {
		++$lineno;
		chomp();
		chop()	if (/\015$/);			# MSDOG >:-)

		$self->dtrace( 7, sprintf( "#%d eval >>>%s<<<", $lineno, $_ )  );

		next	if ($self->{'LCOMMENT'} && /^$self->{'LCOMMENT'}/);

		$_	=~ s/\\$comment/$escomnt/g;	# escapes comments chars
		$_	=~ s/${comment}.*//;		# strip comments
		$_	=~ s/^[ \t]+//;			# strip leading spaces/tabs
		$_	=~ s/[ \t]+$//;			# strip trailing spaces/tabs
		$_	=~ s/$escomnt/$comment/g;	# restore escaped comments chars

		next	if (!$_);

		if ($_ eq $BLOCKTAG) {
			if ($in_block) {
				$self->dtrace( 5, "#$lineno closed block" );
				$in_block = 0;		# mark block closed
				$_ = '';		# clear line buffer
				chop( $inbuf );		# removes last newline from block
			} else {
				confess( "file $self->{_current} line $lineno: block closing tag found, but block not opened" );
			}
		}

		# add current processed line to inbuf
		$self->dtrace( 7, sprintf( "#%d add inbuf  >>>%s<<<", $lineno, $_ )  );
		$inbuf	.= "$_";

		# multiple lines splitting, keeps toghether litereally
		#
		if ($in_block)	{ $inbuf .= "\n"; next; }	# in block, restores newline
		if (/\\$/)	{ chop( $inbuf ); next; }	# escaped, chop out backslash

		$self->dtrace( 7, sprintf( "#%d eval inbuf >>>%s<<<", $lineno, $inbuf )  );
		$_	= $inbuf;
		$inbuf	= "";

		if (/^\[/) {
			if (!/\]$/) {
				confess( "file $self->{_current} line $lineno: section syntax error, missing closing ']'\n$_\n" );
			}
			$section	= $self->new_section( $_ );
			next;
		}
		my @temp	= split( /$sepexpr/, $_ );
		my $key		= $temp[0];
		my $val		= "";

		# 2014.02 (key modifiers)
		#
		$f_def	= 0;
		$f_add	= 0;
		$f_cat	= 0;
		if ($key =~ /^-/) {
			$key	=~ s/^-//;	# remove - from key
			$_	=~ s/^-//;	# remove - from linebuffer
			$f_def	= 1;
		}
		if ($key =~ /^\+/) {
			$key	=~ s/^\+//;	# remove + from key
			$_	=~ s/^\+//;	# remove + from linebuffer
			$f_add	= 1;
		}
		if ($key =~ /^>/) {
			$key	=~ s/^>//;	# remove + from key
			$_	=~ s/^>//;	# remove + from linebuffer
			$f_cat	= 1;
		}

		if ($f_def) {
			if (defined $self->value( $section, $key ) ) {
				$self->dtrace( 3, "#$lineno $section.$key f_def modifier, already defined -> skip" );
				next;
			}
		}

		if (defined $temp[1]) {
			$val	= $_;
			$val	=~ s/^$key$sepexpr//;
		}

		$val	= $self->_unescapechars( $val );

		if ($val eq $BLOCKTAG) {
			$self->dtrace( 5, "#$lineno opened block" );
			$in_block = 1;			# mark block opening
			$inbuf = $key . $separator;	# rebuild input buffer and continue
			next;
		}

		if ($key eq $SUPER) {
			$val	=~ tr/a-z/A-Z/		if ($self->{CASE} eq "upcase");
			$val	=~ tr/A-Z/a-z/		if ($self->{CASE} eq "locase");
		} else {
			$key	=~ tr/a-z/A-Z/		if ($self->{CASE} eq "upcase");
			$key	=~ tr/A-Z/a-z/		if ($self->{CASE} eq "locase");
		}

		if ($self->{QUOTEVAL}) {
			$val	=~ s/^$self->{QUOTEVAL}//;
			$val	=~ s/$self->{QUOTEVAL}$//;
		}

		# 2014.02 (key modifiers)
		#
		if ($f_add || $f_cat) {
			if (defined $self->value( $section, $key ) ) {
				$self->dtrace( 3, "#$lineno $section.$key, f_add/f_cat modifier, defined -> add" );
				if ($f_add) {
					$val = $self->value( $section, $key ) . " " . $val;
				} else {
					$val = $self->value( $section, $key ) . $val;
				}
			} else {
				$self->dtrace( 3, "#$lineno $section.$key, f_add/f_cat modifier, not defined -> assign" );
			}
		}

		$self->{_data}{$section}{$key}	= $val;
		$self->dtrace( 5, sprintf( "#%d %-20s -> '%s'", $lineno, $key, $val ) );
	}
	close( CFGFILE );
	$self->{_loaded}	= 1;
	$self->{_modified}	= 0;
	$self;	# OK
}


sub new_section {
	my $self	= shift;
	my $section	= shift || $self->{'DEFSECTION'};

	$section	=~ s/^\[//;
	$section	=~ s/\]$//;
	$section	=~ tr/a-z/A-Z/		if ($self->{CASE} eq "upcase");
	$section	=~ tr/A-Z/a-z/		if ($self->{CASE} eq "locase");

	return $section		if ($self->{_data}{$section});	# already exists

	$self->dtrace( 4, "[$section] section created" );

	push( @{ $self->{_sections} }, $section );

	$self->{_data}{$section}	= {};

	if ($self->{INERITH} && $section =~ /\./) {
		my @temp	= split( '\.', $section );
		pop( @temp );
		my $val		= join( '.', @temp );
		$self->{_data}{$section}{$SUPER}	= $val;
		$self->dtrace( 4, sprintf( " %-20s -> '%s' (IMPLICIT FROM SECTION NAME)",
			$SUPER, $val ) );
	}
	return $section;
}

sub sections {
	return @{ $_[0]->{_sections} };
}





sub keys {
	my $self	= shift;
	my ($sect, $local)	= @_;

	if ( !defined $sect || (defined $local && $local ne "LOCAL") ) {
		confess( "usage: OBJ->keys( section [, LOCAL] )" );
	}

	$sect	=~ tr/a-z/A-Z/		if ($self->{CASE} eq "upcase");
	$sect	=~ tr/A-Z/a-z/		if ($self->{CASE} eq "locase");

	if (!defined $self->{_data}{$sect}) {
		$self->{ERROR}	= "no section $sect";
		return undef;
	}
	my %keys;
	my $super;

	while ($sect) {
		$super	= "";
		for $_ (CORE::keys( %{ $self->{_data}{$sect} } )) {
			if ($_ eq $SUPER) {
				if (!defined $local) {
					if (!defined $self->{_data}{$sect}) {
						$self->{ERROR}	= "no $SUPER section $sect";
						return undef;
					}
					$super	= $self->{_data}{$sect}{$_};
				}
				next;
			}
			$keys{$_}	= 1;
		}
		$sect	= $super;
	}
	return CORE::keys( %keys );
}




sub value {
	my $self		= shift;

	if (@_ != 2 && @_ != 3) {
		confess( "usage: OBJ->value( section, key [, newvalue] )" );
	}

	my $setval		= (@_ == 3 ? 1 : 0);
	my ($sect, $key, $val)	= @_;



	$self->{ERROR}		= "";
	$self->{REALSECT}	= "";


	if ($self->{CASE} eq "upcase") {
		$sect	=~ tr/a-z/A-Z/;
		$key	=~ tr/a-z/A-Z/;
	} elsif ($self->{CASE} eq "locase") {
		$sect	=~ tr/A-Z/a-z/;
		$key	=~ tr/A-Z/a-z/;
	}

	if (!defined $self->{_data}{$sect}) {
		$self->{ERROR}	= "no section $sect";
		return undef;
	}


	if ($setval) {
		$self->{_data}{$sect}{$key}	= defined $val ? $val : undef ;
		return $val ? $val : undef;
	}

	if (exists $self->{_data}{$sect}{$key}) {
		return $self->{_data}{$sect}{$key};
	}

	#	da qui inizia a controllare inerithance
	#
	$self->{ERROR}	= "no such key '$key'";
	$val	= undef;
	if (!$self->{INERITH}) {						# no inerithance
		return undef;
	}

	while (defined $self->{_data}{$sect}{$SUPER}) {
		$sect	= $self->{_data}{$sect}{$SUPER};

		if (!defined $self->{_data}{$sect}) {
			$self->{ERROR}	= "no $SUPER section $sect";
			return undef;
		}
		$self->{REALSECT}	= $sect;
		if (exists $self->{_data}{$sect}{$key}) {
			$self->{ERROR}	= "";
			return $self->{_data}{$sect}{$key};
		}
	}
	$self->{REALSECT}	= "";
	$self->{ERROR}		= "no such key '$key'";
	return undef;
}


sub is_super {
	return ($_[0]->{REALSECT} ? 1 : 0);
}


#	scrive il contenuto nel file {_current}
#
sub save {
	my $self	= shift;
	my $create	= 0;
	my $local	= 0;
	my $expand	= 0;
	my $ok		= 0;
	my $ofile;

	while (@_) {
		$_	= shift;
		/^CREATE$/	&& do { $create = 1 ; next; };
		/^LOCAL$/	&& do { $local = 1; next; };
		/^EXPAND$/	&& do { $expand = 1; next; };

		$ofile = $_;
		$create = 0;
	}

	if ($ofile) {
		if (open( CFGFILE, ">$ofile" )) {
			close( CFGFILE );
		} else {
			$self->{ERROR}	= "cannot save ('$ofile': $!)";
			return undef;
		}
	}
	if (!$ofile && $self->{_current}) {
		$ofile	= $self->{_current};
	}
	if (!$ofile && !$create) {
		$self->{ERROR}	= "cannot save (no current file defined)";
		return undef;
	}
	if ($ofile && ! -w $ofile && !$create) {
		$self->{ERROR}	= "cannot save ('$ofile' not writeable)";
		return undef;
	}

	if (!$ofile) {
		for $_ ( $self->_filelist( $self->{'NAME'} ) ) {
			$self->dtrace( 3, "trying to write on '$_' ..." );
			if (open( CFGFILE, ">$_" )) {
				$ok	= 1;
				$ofile	= $_;
				last;
			}
		}
		if ($ok) {
			$self->dtrace( 3, "ok, writable '$ofile' found" );
			close(CFGFILE);
			$self->{_current}	= $ofile;
		} else {
			$self->dtrace( 3, "unable to find" );
			$self->{ERROR}	= "unable to create file in current path";
			return $self;
		}
	}

	$self->dtrace( 1, "writing file '$ofile' ..." );

	open( CFGFILE, ">$ofile" )	or do {
		$self->{ERROR}	= "cannot save: $!";
		return undef;
	};

	printf( CFGFILE "#	configuration file saved by %s on %s\n",
				$ENV{LOGNAME}, scalar localtime(time()) );
	printf( CFGFILE "#	(written by Options::File v.%s)\n#", $VERSION );

	my $sect;
	my $key;
	my $val;

	for $sect ($self->sections()) {
		print CFGFILE "\n[$sect]\n"	if ($sect);
		for $key ($self->keys($sect)) {
			$val	= $self->value( $sect, $key );
			if (!defined $val) {
				print STDERR "(save) " . $self->{'ERROR'} . "\n";
			} else {
				if (!$self->is_super()) {
					printf( CFGFILE "  %s%s%s\n", $key, $self->{'SEPARATOR'},
						$self->_escapechars( $val ) );
				}
			}
		}
	}
	close( CFGFILE );

	$self->dtrace( 1, "file written" );

	$self;
}


sub _unescapechars {
	my $self	= shift;
	my $val		= shift;
	$val	=~ s/\\$self->{'COMMENT'}/$self->{'COMMENT'}/g;
	$val	=~ s/\\n/\n/g;
	$val	=~ s/\\r/\r/g;
	$val	=~ s/\\t/\t/g;
	$val	=~ s/\\s/ /g;
	$val;
}

sub _escapechars {
	my $self	= shift;
	my $val		= shift;

	$val	=~ s/$self->{'COMMENT'}/\\$self->{'COMMENT'}/g;
	$val	=~ s/\n/\\n/g;
	$val	=~ s/\r/\\r/g;
	$val	=~ s/\t/\\t/g;
	$val	=~ s/^ /\\s/g;	# only at start of line, to avoid clutter

	if ($self->{QUOTEVAL}) {
		$val	=~ s/$self->{QUOTEVAL}/\\$self->{QUOTEVAL}/g;
		$val	= "$self->{QUOTEVAL}$val$self->{QUOTEVAL}";
	}
	$val;
}


sub exists {
	my $self	= shift;
	my $sect	= shift;
	if (@_) {
		return $self	if (exists $self->{_data}{$sect}{$_[0]});
	} else {
		return $self	if (exists $self->{_data}{$sect});
	}
	return undef;
	
}

sub set_super
{
	my $self	= shift;
	my $section	= shift;
	my $value	= shift;
	return $self->value( $section, $SUPER, $value );
}



#########################
#	 DEBUG		#
#########################


sub DUMP {
	my $self	= shift;
	my $out		= "$self Object Dump\n";
	my $fmt		= "  %-20s = '%s'\n";

	my $key;
	for $key (reverse sort(CORE::keys %$self)) {
		$out	.= sprintf( $fmt, $key, defined $self->{$key} ? $self->{$key} : "(undef)" );
	}

	$out .= sprintf( $fmt, 'searchpath', join( ", ", @{ $self->{_path} } ) );

	$out .= "\n-| DATAS |-------------------------------------------------\n\n";

	my $sec;
	for $sec ($self->sections()) {
		$out	.= "[$sec]\n";
		my $tag;
		for $tag (reverse sort(CORE::keys %{$self->{_data}{$sec}})) {
			if (defined $self->{_data}{$sec}{$tag}) {
				$out	.= "  $tag$self->{'SEPARATOR'}$self->{_data}{$sec}{$tag}\n";
			} else {
				$out	.= "  $tag$self->{'SEPARATOR'}(undef)\n";
			}
		}
	}

	return $out;
}



sub dtrace {
	my $self  = shift;
	my $level = shift;
	return if ($level > $self->{DEBUG});
	print STDERR "D> ", @_, "\n";
	$self;
}

__END__



=head1 NAME

Options::File - Perl extension for reading configuration files

=head1 SYNOPSIS

  use Options::File;

  my $Config	= new Options::File( "test",	MERGE	=> 1,
  						TYPE	=> 'LINUX',
  						PRELOAD => "test.preload" );

  $Config->path_unshift( 'RESET', $ENV{'HOME'}, "/tmp", "/etc" );
  $Config->read();

  @sections	= $Config->sections();
  $value	= $Config->value( "section1", "key1" );
  $Config->value( "section1", "key1", "new value" );

  $Config->read( "test2" );

=head1 DESCRIPTION

Lo scopo primario di questo package e` quello di leggere files di configurazione
in modo agevole. Un file di configurazione e` composto tipicamente da coppie di
chiave - valore.
Il package trova il suo naturale completamento nel package Options::TieFile, che
permette di legare files di configurazione ad hashes per una consultazione piu`
semplice.

Questo package in particolare permette di leggere files i cui elementi sono
suddivisi in sezioni. Una sezione viene indicata da una riga che contiene una
keyword racchiusa tra parentesi quadre.

Le coppie di chiave - valore sono dichiarate una per riga, e sono separate dal
carattere "=" o da uno (o piu`) spazi o tabs. Il primo formato e` comunemente
usato nei file .INI di windoze, il secondo e` un formato che si trova spesso
sui sistemi Linux:

	windoze				linux
	------------------		-----------------------
	[section1]			[section1]
	key1=value 1 ...		  key1	value 1 ...
	key2=value 2 ...		  key2	value 2 ...

	[section2]			[section2]
	key1=value 1/2 ...		  key1	value 1/2 ...


Passando al metodo di creazione il parametro 'TYPE' e` possibile preimpostare
i parametri di interpretazione a valori di default, valori che possono comunqu
essere modificati passando al metodo new() le opportune opzioni, che vengono
inserite nell'hash dell'oggetto in modo literal dopo gli opportuni controlli.

Se non viene definita nessuna sezione nel file di configurazione nell'oggetto
le coppie chiave-valore sono comunque assegnate alla sezione di default, che
e` preimpostata a "common". E` possibile cambiare la sezione di default
passando al metodo new() il parametro DEFSECTION.

La stringa di separazione tra chiave e valore e` contenuta nel parametro
SEPARATOR. Nel caso non sia una stringa ma una regular expression viene
passata col parametro SEPEXPR, ma deve comunque essere indicato una stringa
congruente in SEPARATOR nel caso si voglia utilizzare i metodi save() o
DUMP() perche` e` usata per la formattazione dell'output.

Options::File ignora le rige vuote o che contengono solo spazi.

Il carattere pound ("#") indica l'inizio di un commento, tutto quello che
segue, compreso il pound ed eventuali spaces prima di questo, viene
ignorato.
Per poter inserire quindi un carattere pound in un valore occorre farlo
precedere dal backslash.
Il carattere di inizio commento puo` essere ridefinito passando il
parametro COMMENT.

Sono del tutto ignorate anche le righe che iniziano con il carattere ";"
(che deve quindi essere nella prima colonna), che e` una consuetudine
nel mondo Linux. Questo carattere puo` essere modificato con il 
parametro LCOMMENT.

Eventuali spaces all'inizio delle righe o alla fine vengono ignorati, e`
quindi possibile indentare le definizioni per una maggiore leggibilita`
(non e` quindi possibile per una chiave avere degli spaces nel nome
come primi caratteri). 

E` possibile inserire nei valori (non nelle chiavi) alcuni caratteri
non printabili usando la notazione usuale del backslash-char:
sono riconosciuti \n, \r, \t, \s.

Se una riga termina con il carattere backslash viene automaticamente
incollata a quella dopo (spanning su piu` righe). In questo caso occorre
notare che comunque gli spaces iniziali vengono ignorati, quindi se
avete la necessita` di avere comunque degli spazi ad inizio riga potete
usare il trucco di metterli nella riga prima: essendo il backslash di
continuazione l'ultimo carattere della riga, gli spaces che lo precedono
non saranno considerati "trailing", e quindi non saranno rimossi.

La continuazione tramite backslash finale e` comoda per poche righe,
in caso di blocchi piu` estesi vedere il paragrafo BLOCCHI.

E` possibile forzare l'interpretazione delle chiavi (e dei nome di sezione)
ignorando il case, ovvero forzando tutto in maiuscolo o in minuscolo,
impostando il parametro CASE.

Gia` con queste carattestiche il package Options::File e` uno strumento
veloce e comodo da utilizzare, ad esempio per il trattamento massivo o per
modifiche batch di files di configurazione, ma i comportamenti avanzati
permettono una flessibilita` estremamente utile per la configurazione,
ad esempio, di tools o comandi utente.

=head1 ADVANCED FEATURES

=head2 KEY MODIFIERS

Nelle definizioni, composte dalla coppia key e value, possono essere
utilizzati dei modificatori nel nome della key, inserendo un carattere
prima del nome:

  - (minus) default value, il valore viene assegnato alla chiave key
    solo se questa non e` gia` definita

  + (plus) append, il valore viene appeso all'eventuale valore gia`
    esistente, preceduto da uno spazio (utile per testi e liste); se
    la chiave non ha gia` un valore definito, allora il nuovo valore
    sara` definito normalmente

  > (major) concatenate, come append, ma senza spazio iniziale (as-is)

Ovviamente la key viene definita con il proprio nome, senza il carattere
modificatore iniziale.


=head2 SEARCHPATH

Il caricamento dei files di configurazione avviene attraverso un path
di ricerca, detto searchpath, che e` una lista di directories. Il parametro
da utilizzare per impostare il searchpath al momento di creare un nuovo
oggetto e` SEARCHPATH, che accetta come valore uno scalare contenente le
directories separate da spazi o dai caratteri ":" o ";".
Nel caso si utilizzi un searchpath il primo parametro del metodo new()
non e` un pathname completo ma solo un nome di file.

E` importante tenere a mente questo, nel caso di SEARCHPATH, il nome
del file da caricare viene sempre cercato nella lista, e quindi preceduto
dai nomi delle directories elencate nel searchpath. Al momento non c'e`
modo di passare un path assoluto, un workaround consiste nel disabilitare
temporaneamente la search impostando nullo il SEARCHPATH.

Ci sono due modi di caricamento, a file singolo (one-shot) o a files multipli
(merged). Il parametro che indica il tipo di caricamento e` MERGE.

Nel caso di caricamento one-shot il searchpath viene percorso dal primo
elemento in avanti, ed il caricamento si ferma al primo file incontrato.

Nel caso di caricamento merged il searchpath viene percorso al contrario,
ed ogni file incontrato viene caricato in memoria. Le definizioni vanno
cosi` a sommarsi (o a ricoprire quelle gia` in memoria) fino ad ottenere
una situazione che e`, appunto, un merge dei files caricati.

Questo permette di definire, impostando in modo opportuno il searchpath,
una serie, ad esempio, di opzioni globali per comando, che possono essere
integrate o modificate da un profilo personale dell'utente, o del progetto
corrente.

L'oggetto mantiene al proprio interno il puntatore al file corrente, che e`
l'ultimo file ad essere stato caricato. Ogni modifica eseguita in seguito
sui valori in memoria viene virtualemente eseguita sul file corrente.

Una nota riguardante il searchpath: se in questo compare la homedir
dell'utente (il contenuto dell'environment $HOME) al nome del file da
caricare viene preposto automaticamente un punto, e ogni eventuale estensione
viene eliminata ("prova.conf" diventa quindi ".prova"). Questo per
seguire la consuetidine (che io in genere detesto) di utilizzare i
cosiddetti dotfiles come files di configurazione utente.


=head2 SECTIONS INERITHANCE

Le sezioni possono utilizzare il concetto di ereditarieta`, possono cioe`
essere organizzate con una struttura parent-child, ed il metodo value()
ricerca un valore nella catena dei parents nel caso questo non sia
definito nella sezione correntemente sotto esame.

L'ereditarieta`, attivata impostando a true il parametro INERITH del
metodo new(), viene espressa usando nel nome delle sezioni il concetto
di pathname: la sezione [sect1.sect2] e` percio` la "sect2" child della
"sect1". Ogni valore non trovato direttamete in questa sezione viene
ricercato in quella superiore, "sect1".

Il metodo is_super() puo` essere usato per sapere, in questo caso, la
reale provenieza di un certo valore.

E' possibile in questo modo creare configurazioni particolarmente
complesse ma strutturalmente molto semplici e lineari, sopratutto se
si combina l'ereditarieta` delle definizioni con il caricamento in
modalita` merged di piu` files.

E` possibile forzare una ereditarieta` trasversale, cioe` non definita
esplicitamente dal nome della sezione, indicando tra i valori della
sezione la keyword riservata "<super>", il cui valore deve essere
quella di un'altra sezione che diventa cosi` la parent di quella
corrente. Dato che non vi puo` essere piu` di un parent per una sezione,
questa definizione ricopre quella eventualmente dedotta dal nome.

Sottilneo il concetto, non on e` possibile, al momento, definire
ereditarieta` multiple.

E` possibile mescolare le definizioni delle sezioni ripetendo (ed
alternando) all'interno dello stesso file il tag di inizio sezione
"[sezione]". Alla fine del caricamento il database di informazioni
risultante sara` comunque omogeneo.

La cosa importante e` che in caso di sezioni con ereditarieta` alla
fine del caricamento la situazione sia congruente. Non e` cioe`
importante che "[sect1]" sia definito prima di "[sect1.sect2]", ma
terminato il caricamento "[sect1]" deve essere definita come
sezione, altrimenti cercando di accedere ad un valore non definito
della sezione child Options::File ritorna uno stato di errore, non
potendo risalire in modo corretto al parent.

=head2 PRELOAD

Uno dei problemi che si incontrano nel gestire files di configurazione
complessi e` il controllo (sintattico e di merito) dei valori descritti.

Questo tipo di controlli non viene per ora gestito da Options::File, i
miei piani di sviluppo prevedono infatti la creazione di un package per
la gestione di Strict Objects, oggetti basati sul classico concetto di
hash anonimo ma i cui elementi vengono assogettati a controlli, non
ultimo quello, ad esempio, di poter impedire la valorizzazione di elementi
non previsti in fase di progettazione dell'oggetto, o di elementi
read-only.

Quello pero` che Options::File puo` fare e` quello di precaricare un
file di configurazione al momento stesso della creazione di un nuovo
oggetto col metodo new().

In questo file lo sviluppatore puo` cosi` inserire definizioni di
default, oppure definizioni di base necessarie alla struttura di
configurazioni complesse, praticamente le cosiddette definitioni built-in.

In questo modo modificando il file (o i files) di configurazione veri e
propri vengono comunque mantenute le definizioni built-in.

Il preload viene attivato passando un pathname completo al metodo new()
attraverso il parametro PRELOAD. Il file specificato deve esistere e deve
essere leggibile, in caso contrario il package genera un abort via confess().

Lo stesso effetto del preload puo` essere ottenuto manualmente con una
sequenza di caricamenti modificando in modo opportuno il nome del file da
caricare e/o il searchpath.


=head2 PRESETS (TYPE)

Per presets si intendono alcune configurazioni di default dei parametri
di creazione dell'oggetto, in modo da semplificarne l'uso. Il preset si
abilita impostando l'opzione TYPE del metodo new(). Questi sono i presets
attualmente disponibili con le conseguenti impostazioni (il primo sono i
valori di default):

   default:
     MERGE	0
     PATH	nessuno
     CASE	undef
     SEPARATOR	" "
     SEPEXPR	"\s+"
     COMMENT	"#"
     LCOMMENT	";"
     INERITH	1

   LINUX:
     PATH	$HOME:$PRJ/etc:/etc:$PATH
     MERGE	1

   LINUX2:
     PATH	$HOME:$PRJ/etc:/etc:$PATH
     MERGE	1
     SEPARATOR	" = "
     SEPEXPR	"\s*=\s*"
     DEFSECTION	"global"

   SHELL:
     PATH	$HOME:$PRJ/etc:/etc:$PATH
     MERGE	0
     SEPARATOR	"="
     SEPEXPR	"="
     QUOTEVAL	'
     DEFSECTION	""
     

   WIN:
     PATH:	c:/windows:c:/etc:$PATH
     INERITH	0
     CASE	upcase
     SEPARATOR	"="


Il tipo 'LINUX' e` in pratica il default di Options::File, tranne per il
searchpath preimpostato e la modalita` merge attivata. Per $HOME e $PRJ si
intendono il valore delle omonime environment, se definite (l'ultima e`
frutto della struttura da noi utilizzata per la suddivisione in progetti
delle attivita` di sviluppo).

Il tipo 'LINUX2' e` simile al precedente, ma utilizza il carattere "=" come
separatore per le definizioni, accettando pero` eventuali spaces tra la
key ed il valore (un esempio e` il config file di samba, /etc/smb.conf).

Il tipo SHELL serve a leggere (e scrivere) files che contengono variabili
definite in formato compatibile con la bourne shell, quindi con var=valore,
dove valore puo` essere incluso tra apici, sia singoli che doppi.
In scrittura il valore viene sempre racchiuso tra apici, definiti
dall'attributo QUOTEVAL; il contenuto del valore viene controllato,
e i caratteri uguali a QUOTEVAL vengono preceduti da backslash.

Infine, il tipo 'WIN' e` il formato di un tipico .INI windoze.

Le opzioni passate al metodo new() vengono processate sequenzialmente,
quindi passando come primo parametro TYPE e` possibile impostare a piacere
altri parametri specificandoli dopo TYPE.


=head2 BLOCCHI

Nel caso sia necessario inserire come valore una serie di righe puo`
essere conventiene utilizzare il concetto di blocco. La parola chiave
"^^BLOCK^^" viene usata per identificare sia l'inizio che la fine di
un gruppo di righe che deve essere utilizzato come unica definizione.

Per aprire un blocco, la keyword deve essere il solo valore presente,
a fianco della chiave. Per chiudere il blocck la keywork deve essere
l'unico valore, ad inizio riga.

Esempio:

  chiave  ^^BLOCK^^
          riga1
          riga2
	  riga3
  ^^BLOCK^^

Il blocco viene inserito rispettando i newline, ma valgono le stesse
regole di interpretazione (rimozione commenti, leading e trailing spaces,
ecc) delle righe normali, quindi nel caso sia necessario mantenere,
ad esempio, la spaziatura iniziale, occorre utilizzare i caratteri
speciali \t o \s.

Notare che in caso di riscrittura del file i blocchi e le righe multiple
non saranno preservati, ogni coppia chiave/valore verra` riscritta come
singola riga.

=head 2 ESCAPES

Esempi di utilizzzo dei caratteri di escape:

  key	   aaa		produce 'aaa'
  key	\s bbb		produce '  bbb'
  key	\tccc		produce '\tccc'
  key	R1\nR2		produce 'R1\nR2' (2 righe)
  key	R1\n\		identico a sopra
  	R2
  key	R1\		produce 'R1R2' (1 riga)
  	R2
  key	R1\n   \	produce 'R1\n  R2'
  	R2		(notare gli spazi)

=head1 METHODS

=over

=item new( name [, options] )

Crea un nuovo oggetto ed lo inizializza con i defaults in relazione anche
ai parametri passati come opzioni, che sono passate come hash (oppure come
lista di coppie opzione, valore).

Le opzioni riconosciute sono:

   MERGE	1 o 0
   TYPE		LINUX, LINUX2, SHELL, WIN
   PRELOAD	filename
   PATH		searchpath
   CASE		undef, locase, upcase
   SEPARATOR	char
   SEPEXPR	regexpr
   COMMENT	char
   LCOMMENT	char
   QUOTEVAL	char
   INERITH	1 o 0

=item read( [name] );

Legge il file (o i files in caso di lettura merged) e li carica in memoria.
In caso di lettura ok (almeno un file trovato e correttamente caricato)
viene ritornato l'oggetto stesso, altrimenti undef.
In caso di errore viene ritornato un messaggio in $oggetto->{'ERROR'}.
Se passato il parametro "name" reimposta il nome inf $oggetto->{'NAME'}.

=item save( [outputfile], [options] )

Salva il contenuto dell'oggetto nel file specificato, oppure nel file
corrente (l'ultimo caricato dal metodo read()).
Se il file corrente non e` definito o se non e` scrivibile, e viene
passato il parametro CREATE viene tentata la scrittura del file nel
searchpath.

Ritorna l'oggetto stesso in caso di successo, o undef in caso di errore.
Il metodo accetta queste opzioni:

    CREATE	tenta di scrivere il file nella prima directory indicata
    		nel searchpath, se il file non esiste viene creato

    EXPAND	solo per oggetti con ereditarieta` attivata, scrive le
    		definizioni complete di quelle ereditata dalle sezioni
		parents. Utile per esportare il database di configurazione
		verso utilities che non supportano l'ereditarieta`;
		ovviamente ogni concetto di ereditarieta` viene perso
		nel file riscritto

    LOCAL	scrive solo le definizioni correnti, cioe` quelle non 
    		ereditate da precedenti caricamenti (questa opzione ha
		senso solo per oggetti di tipo MERGE)
		**** NON ANCORA IMPLEMENTATO ****

=item search( [path] )

Cerca nel searchpath o nel path passato il file, ritorna l'oggetto stesso
al primo file trovato o undef in caso contrario ($oggetto->{'ERROR'}
impostato). Il path del file trovato viene memorizzato ed e` disponibile
tramite il metodo current();

=item current()

Ritorna il path dell'ultimo file caricato (o trovato dall'invocazione del
metodo search()), oppure undef.

=item path_unshift( [RESET,] lista )

Aggiunge in testa al path di ricerca la lista di directories specificate.
Se come primo parametro viene passato il literal RESET il path di ricerca
viene preventivamente azzerato.
E' possibile passare come elementi della lista anche scalari che contengono
a loro volta liste di pathnames separati dal carattere ";". In questo modo
si puo`, ad esempio, aggiungere l'intero path ricerca $PATH passando a questo
metodo la variabile $ENV{'PATH'}.

=item path_push( [RESET,] lista )

Come il metodo path_unshift() ma appende al searchpath invece che aggiugere in
testa.

=item new_section( [section] )

Aggiunge la sezione "section" (o quella di default se non passata) al
database di definizioni, ritorna il puntatore alla sezione stessa.
Se la sezione esiste gia` la chiamata viene silenziosamente ignorata.
Attenzione, e` obbligatorio passare per questo metodo per creare una
nuova sezione, perche` in questo modo viene aggiornato l'elenco interno
delle sezioni esistenti, e perche` viene interpretato correttamente
l'eventuale mangling minuscole/maiuscole nel nome (vedi TYPE).

=item sections()

Ritorna una lista delle sezioni contenute nel profile.

=item keys( section )

Ritorna una lista delle chiavi contenute nella sezione <section> del profile.

=item value( section, key, [newvalue] )

Ritorna il valore per la chiave <key> nella sezione <section>. Se passato un
terzo parametro imposta il nuovo valore; attenzione, in questo caso viene
comunque ritornato il valore precedente.
Il metodo fallisce se non esiste la sezione indicata o se non esiste la chiave
indicata per la sezione. In questo caso viene ritornato undef e viene
caricato un messaggio opportuno in $oggetto->{'ERROR'}. Notare che la chiave
indicata puo` anche puntare ad un elemento che ha come valore proprio 'undef',
quindi l'unico modo di sapere se il metodo fallisce o meno in questo caso e`
controllare il messaggio di errore, oppure usare il metodo exists();

=item exists( section [, key] )

Controlla se esiste la sezione indicata o, se passato il secondo parametro, se
esiste l'elemento puntato dalla chiave "key" per la sezione indicata.
In caso positivo ritorna l'oggetto stesso, altrimenti undef e viene caricato
l'opportuno codice di errore.

=item set_super( section, supersection )

Forza l'ereditarieta` per la sezione "section" a quella "supersection".

=item is_super()

Controlla se il valore corrente (l'ultimo ritornato dal metodo value) e`
stato ereditato da una definizione di livello superiore o meno. Ritorna
l'oggetto stesso in caso positivo, undef in caso contrario oppure se
l'ultima operazione del metodo non e` andata a buon fine.

=item is_loaded()

Ritorna true (l'oggetto stesso) se e` stato eseguito con successo almeno
una operazione di caricamento, undef altrimenti.

=item is_modified()

Ritorna true (l'oggetto stesso) se il contenuto dell'oggetto e` stato
modificato, undef altrimeniti.

=back

=head1 DEBUG METHODS

=over

=item DUMP()

Ritorna una stringa contenente il dump completo dell'oggetto.

=back

=head1 BUGS

L'oggetto memorizza solo le definizioni, non i commenti, quindi il metodo
save() riscrive un file leggibile ma ripulito. Inoltre la sequenza di
scrittura dei dati non e` garantita, in quanto ininfluente per come
Option::File gestisce il database di informazioni.

Questo package non e` quindi, almeno per ora, indicato per l'editing di
files che devono essere manutenuti anche manualmente, o che per qualche
motivo devono rispettare una certa struttura formale.

Altri bugs per ora non ne ho trovati, fatemi sapere se ne scovate.

=head1 AUTHOR

(c) 1994 "Kanna" Lorenzo Canovi <kanna@metodo.net>
(c) 2000-2014 Lorenzo Canovi <lorenzo.canovi@kubiclabs.com>

released under LGPL v.2

=head1 SEE ALSO

perl(1), Options::TieFile(3).

=cut

