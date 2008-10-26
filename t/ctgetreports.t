#!perl -- -*- mode: cperl -*-

use Test::More;
use File::Spec;
use CPAN::Testers::ParseReport;
use List::Util qw(sum);
use YAML::Syck;

my $plan;

{
    BEGIN {
        $plan += 5;
    }
    my %Opt = (
               'q' => ["meta:perl", "meta:from", "qr:(Undefined.*)"],
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
    my $undefined = $Y->{'qr:(Undefined.*)'};
    my($the_warning) = grep {length} keys %$undefined;
    ok($undefined,"found warning: '$the_warning'");
    like($the_warning, qr/&main::/, "the ampersand is escaped");
}

{
    BEGIN { $plan += 1 }
    open my $fh, "-|", qq{"$^X" "-Ilib" "bin/ctgetreports" "--local" "--cachedir" "t/var" "--solve" "--quiet" "Scriptalicious" 2>&1} or die "could not fork: $!";
    my @reg;
    while (<$fh>) {
        push @reg, $1 if /^Regression '(.+)'/;
    }
    is "@reg", "mod:Test::Harness id meta:date", "found the top 3 candidates";
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
