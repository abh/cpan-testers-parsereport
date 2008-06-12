#!perl -T

use Test::More tests => 1;

BEGIN {
	use_ok( 'CPAN::Testers::ParseReport' );
}

diag( "Testing CPAN::Testers::ParseReport $CPAN::Testers::ParseReport::VERSION, Perl $], $^X" );
