#!perl -T

use strict;
use warnings;
use Test::More;

# Ensure a recent version of Test::Pod
my $min = 0.12;
eval "use Test::CPAN::Meta $min";
plan skip_all => "Test::CPAN::Meta $min required for testing META.yml" if $@;

meta_yaml_ok();
