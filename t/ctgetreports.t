#!perl -- -*- mode: cperl -*-

use Test::More;
use File::Spec;
use CPAN::Testers::ParseReport;
use List::Util qw(sum);
use YAML::Syck;

my $plan;

{
    BEGIN {
        $plan += 3;
    }
    my %Opt = (
               'q' => ["meta:perl", "meta:from"],
               'local' => 1,
               'cachedir' => 't/var',
               'quiet' => 1,
               'dumpvars' => ".",
              );
    CPAN::Testers::ParseReport::parse_distro
          (
           "Scriptalicious",
           %Opt,
          );
    my $Y = YAML::Syck::LoadFile("ctgetreports.out");
    my $count = sum map {values %{$Y->{"meta:from"}{$_}}} keys %{$Y->{"meta:from"}};
    is($count, 130, "found 130 report via meta:from");
    is($Y->{"meta:ok"}{PASS}{PASS}, 79, "found 79 PASS");
    ok(!$Y->{"env:alignbytes"}, "there is no such thing as an environment alignbytes");
}

unlink "ctgetreports.out";

BEGIN {
      plan tests => $plan;
}

__END__

# Local Variables:
# mode: cperl
# cperl-indent-level: 4
# End:
