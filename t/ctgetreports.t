#!perl -- -*- mode: cperl -*-

use Test::More;
use File::Spec;
use CPAN::Testers::ParseReport;

my $plan;

{
    BEGIN {
        $plan += 1;
    }
    my %Opt = (
               'q' => ["meta:perl", "meta:from"],
               'local' => 1,
               'cachedir' => 't/var',
               'quiet' => 1,
              );
    CPAN::Testers::ParseReport::parse_distro
          (
           "Scriptalicious",
           %Opt,
          );
    ok(1);
}

BEGIN {
      plan tests => $plan;
}

__END__

# Local Variables:
# mode: cperl
# cperl-indent-level: 4
# End:
