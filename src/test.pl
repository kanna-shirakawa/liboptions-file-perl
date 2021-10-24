#!/usr/bin/perl -w
#
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'
#
######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..16\n"; }
END { NO() unless $loaded; }

use strict;

use vars qw/$tnum $cfg $status $s $k %tied/;
my $tnum = 0;
my $cfg;
my $status = 0;
my $s;
my $k;

T( 1, "load" );

use Options::File;
use Options::TieFile;

use vars qw/$loaded/;
$loaded = 1;
OK();


######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):



sub T	{ printf( " %2d %-40s ", $_[0], $_[1] ); $tnum = $_[0]; }
sub OK	{ printf( "ok %d\n", $tnum ); }
sub NO	{ printf( "not ok %d", $tnum );
	if (defined $_[0]) { print "  " . $_[0] . "\n" } else { print "\n"; }
	if (defined $cfg->{ERROR} && $cfg->{ERROR} ne "") { print "  ERR: " . $cfg->{ERROR} . "\n"; }
	exit(1);
	}

sub pval
{
	if (defined $cfg->value(@_)) {
		return sprintf( "val='%s'", $cfg->value(@_) );
	} else {
		return "val=(undef)";
	}
}

# File.pm

T( 2, "new()" );
$cfg = new Options::File( "test.cfg",
	TYPE => 'LINUX',
	PATH => '.:/tmp',
	DEBUG => 0 );
if (!defined $cfg) {
	NO();
	exit(1);
}
OK();

T( 3, "read(nonexistent)" );
$cfg->read( "nonexistent" ) && NO() || OK();

T( 4, "read(test.cfg)" );
$cfg->read( "test.cfg" ) && OK() || NO();

$s='sect1'; $k='key1';
T( 5, "$s.$k = 'val1'" );
($cfg->value($s,$k) eq "val1") && OK() || NO( pval($s,$k) );

$s='sect1'; $k='key2';
T( 6, "$s.$k = (undef)" );
(defined $cfg->value($s,$k)) && NO( pval($s,$k) ) || OK();

$s='sect2.sub1'; $k='key2';
T( 7, "$s.$k = val2.sub1" );
($cfg->value($s,$k) eq "val2.sub1") && OK() || NO( pval($s,$k) );

$s='unrelated'; $k='key1';
T( 8, "$s.$k = val1" );
($cfg->value($s,$k) eq "val1") && OK() || NO( pval($s,$k) );

$s='additions'; $k='key2';
T( 9, "$s.$k = val2 ADD" );
($cfg->value($s,$k) eq "val2 ADD") && OK() || NO( pval($s,$k) );

$s='additions'; $k='key3';
T( 10, "$s.$k = val3CAT" );
($cfg->value($s,$k) eq "val3CAT") && OK() || NO( pval($s,$k) );

$s='conditional'; $k='newkey';
T( 11, "$s.$k = newval1" );
($cfg->value($s,$k) eq "newval1") && OK() || NO( pval($s,$k) );

$s='conditional'; $k='key2';
T( 12, "$s.$k = val2" );
($cfg->value($s,$k) eq "val2") && OK() || NO( pval($s,$k) );

# TieFile.pm

$s='sect2';
T( 13, "tie($s)" );
tie( %tied, 'Options::TieFile', $s, $cfg ) && OK() || NO();

$k='key2';
T( 14, "tied{$k} eq val2" );
($tied{$k} eq "val2") && OK() || NO( pval($s,$k) );

$k='key3';
T( 15, "tied{$k} eq val3" );
($tied{$k} eq "val3") && OK() || NO( pval($s,$k) );

T( 15, "tied{$k} eq newval3" );
$tied{$k} = "newval3";
($tied{$k} eq "newval3") && OK() || NO( pval($s,$k) );

T( 16, "tied{$k} (deleted)" );
delete $tied{$k};
(!defined $tied{$k}) && OK() || NO( pval($s,$k) );

