#!perl -- -*- mode: cperl -*-

use Test::More;
use File::Spec;
use CPAN::Testers::ParseReport;
use List::Util qw(sum);
use YAML::Syck;

my $plan;

{
    BEGIN { $plan += 1 }
    open my $fh, "<", qq{t/var/nntp-testers/1581994} or die "could not open: $!";
    local $/;
    my $article = <$fh>;
    close $fh;
    my $dump = {};
    $DB::single++;
    CPAN::Testers::ParseReport::parse_report(1234567, $dump, article => $article, solve => 1, quiet => 1);
    $DB::single++;
    my $keys = keys %{$dump->{"==DATA=="}[0]};
    ok($keys >= 39, "found at least 39, actually [$keys] keys");
}

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
    is($count, 130, "found $count==130 reports via meta:from");
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
    is "@reg", "meta:writer mod:Test::Harness id", "found the top 3 candidates";

# Up to 0.0.15:

# State after regression testing: 68 results, showing top 3
# 
# (1)
# ****************************************************************
# Regression 'mod:Test::Harness'
# ****************************************************************
# Name                         Theta          StdErr     T-stat
# [0='const']                 1.0000          0.1021       9.80
# [1='eq_2.64']              -0.3846          0.1328      -2.90
# [2='eq_3.09']               0.0000          0.3228       0.00
# [3='eq_3.10']              -0.0200          0.1109      -0.18
# [4='eq_3.11']              -0.0000          0.2042      -0.00
# [5='eq_3.12']              -0.7143          0.1309      -5.46
# [6='eq_3.13']              -0.8696          0.1204      -7.22
# [7='eq_3.14']              -0.8667          0.1291      -6.71
# 
# R^2= 0.628, N= 128, K= 8
# ****************************************************************
# (2)
# ****************************************************************
# Regression 'id'
# ****************************************************************
# Name                         Theta          StdErr     T-stat
# [0='const']                 2.4992          0.1514      16.51
# [1='n_id']                 -0.0000          0.0000     -12.66
# 
# R^2= 0.560, N= 128, K= 2
# ****************************************************************
# (3)
# ****************************************************************
# Regression 'meta:date'
# ****************************************************************
# Name                         Theta          StdErr     T-stat
# [0='const']                93.9116          7.3952      12.70
# [1='n_meta:date']          -0.0000          0.0000     -12.62
# 
# R^2= 0.558, N= 128, K= 2
# ****************************************************************

# From 0.0.16:

# State after regression testing: 110 results, showing top 3
# 
# (1)
# ****************************************************************
# Regression 'meta:writer'
# ****************************************************************
# Name                         Theta          StdErr     T-stat
# [0='const']                 0.8929          0.0509      17.54
# [1='eq_CPAN-Reporter-1.1404']       0.1071          0.0992       1.08
# [2='eq_CPAN-Reporter-1.15']         0.1071          0.0720       1.49
# [3='eq_CPAN-Reporter-1.1556']      -0.8929          0.1440      -6.20
# [4='eq_CPAN-Reporter-1.16']        -0.8929          0.2741      -3.26
# [5='eq_CPAN-Reporter-1.1601']      -0.6929          0.1308      -5.30
# [6='eq_CPAN-Reporter-1.1651']      -0.7679          0.0844      -9.10
# [7='eq_CPAN-Reporter-1.17']        -0.6706          0.1032      -6.50
# [8='eq_CPAN-Reporter-1.1702']      -0.7817          0.0814      -9.61
# [9='eq_CPAN::YACSmoke 0.0307']              0.1071          0.1032       1.04
# 
# R^2= 0.717, N= 128, K= 10
# ****************************************************************
# (2)
# ****************************************************************
# Regression 'mod:Test::Harness'
# ****************************************************************
# Name                         Theta          StdErr     T-stat
# [0='const']                 1.0000          0.1021       9.80
# [1='eq_2.64']              -0.3846          0.1328      -2.90
# [2='eq_3.09']               0.0000          0.3228       0.00
# [3='eq_3.10']              -0.0200          0.1109      -0.18
# [4='eq_3.11']              -0.0000          0.2042      -0.00
# [5='eq_3.12']              -0.7143          0.1309      -5.46
# [6='eq_3.13']              -0.8696          0.1204      -7.22
# [7='eq_3.14']              -0.8667          0.1291      -6.71
# 
# R^2= 0.628, N= 128, K= 8
# ****************************************************************
# (3)
# ****************************************************************
# Regression 'id'
# ****************************************************************
# Name                         Theta          StdErr     T-stat
# [0='const']                 2.4992          0.1514      16.51
# [1='n_id']                 -0.0000          0.0000     -12.66
# 
# R^2= 0.560, N= 128, K= 2
# ****************************************************************


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

