#!perl -- -*- mode: cperl -*-

use Test::More;
use File::Spec;

my $plan;

BEGIN {
      $plan += 1;
}

{
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
