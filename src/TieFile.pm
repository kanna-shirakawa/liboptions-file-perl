# (c) 1994-2013 Lorenzo Canovi <lorenzo.canovi@kubiclabs.com>
# released under LGPL v.2
#
package	Options::TieFile;
use	Options::File;
use	Carp;
use	strict;
use	vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

require Exporter;

@ISA		= qw(Exporter);
@EXPORT		= qw();
@EXPORT_OK	= qw();
$VERSION	= "2.8";

1;

sub TIEHASH {
	my $class	= shift;
	my $sect	= shift;
	my $tied	= shift;
	my $self	= {};

	$self->{_sect}	= $sect;
	$self->{_keys}	= [];

	if ($tied->exists( $sect )) {
		$self->{_tied}	= $tied;
		bless $self, $class;
	} else {
		confess( "no section $sect in this $tied object" );
	}
}

sub FETCH {
	my $self	= shift;
	my $key		= shift;
	my $tied	= $self->{_tied};

	return $tied->value( $self->{_sect}, $key );
}

sub STORE {
	my $self	= shift;
	my $key		= shift;
	my $tied	= $self->{_tied};

	$tied->{_modified}	= 1;
	$tied->value( $self->{_sect}, $key, $_[0] );
	return $_[0];
}

sub DELETE {
	my $self	= shift;
	my $key		= shift;
	my $tied	= $self->{_tied};
	my $sect	= $self->{_sect};
	my $val		= $tied->value( $sect, $key );

	if ($tied->is_super()) {
		$self->dtrace( 2, "UNDEFINE (IS SUPER) [$sect] $key] = $val" );
		$tied->{_data}{$sect}{$key}	= undef;
		$tied->{_modified}		= 1;
	} else {
		if (!exists $tied->{_data}{$sect}{$key}) {
			$self->dtrace( 2, "NOT DELETED (NOT EXISTS) [$sect] $key" );
		} else {
			$self->dtrace( 2, "DELETE [$self->{_sect}] $key = $val" );
			delete $tied->{_data}{$sect}{$key};
			$tied->{_modified}	= 1;
		}
	}
}

sub EXISTS {
	my $self	= shift;
	my $key		= shift;
	my $tied	= $self->{_tied};
	return exists $tied->{_data}{$self->{_sect}}{$key};
}

sub FIRSTKEY {
	my $self	= shift;
	my $tied	= $self->{_tied};
	my $sect	= $self->{_sect};
	my $keys	= $self->{_keys};

	@$keys	= $tied->keys( $sect );
	return shift @$keys;
}

sub NEXTKEY {
	my $self	= shift;
	my $keys	= $self->{_keys};
	return shift @$keys;
}

sub CLEAR		{ confess( "CLEAR not implemented" ); }


sub dtrace {
	my $self  = shift;
	my $level = shift;
	my $tied  = $self->{_tied};
	return if ($level > $tied->{DEBUG});
	print STDERR "D> ", @_, "\n";
	$self;
}


=head1 NAME

Options::TieFile - Perl extension to tie hashes to Options::File objects

=head1 SYNOPSIS

  use Options::File;
  use Options::TieFile;
  
  my $cfg = new Options::File( "/etc/smb.conf", TYPE => 'LINUX2' );
  $cfg->read() || die $cfg->{ERROR};

  my %samba;
  tie( %samba, 'Options::TieFile', 'global', $cfg );
  print "workgroup is ", $samba{'workgroup'}, "\n";

  my $newshare = "mydisk";
  my %share;

  $cfg->new_section( $newshare )	|| die $cfg->{ERROR};
  tie( %share, 'Options::TieFile', $newsection, $cfg );

  $share{'comment'}	= "My Disk";
  $share{'browseable'}	= "no";
  $share{'writable'}	= "yes";

  $cfg->save( "/tmp/new-smb.conf" )	|| die $cfg->{ERROR};


=head1 DESCRIPTION

  ... sorry, to be done ...

=head1 AUTHOR

(c) 1994 "Kanna" Lorenzo Canovi <kanna@metodo.net>
(c) 2000-2014 Lorenzo Canovi <lorenzo.canovi@kubiclabs.com>

released under LGPL v.2

=head1 SEE ALSO

perl(1), Options::File(3).

=cut

