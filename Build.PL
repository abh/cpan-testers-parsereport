use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new
    (
     module_name         => 'CPAN::Testers::ParseReport',
     license             => 'perl',
     dist_author         => 'Andreas Koenig <andreas.koenig.7os6VVqR@franz.ak.mind.de>',
     dist_version_from   => 'lib/CPAN/Testers/ParseReport.pm',
     build_requires =>
     {
      'Test::More' => 0,
     },
     requires =>
     {
      'DateTime::Format::Strptime' => 0,
      'File::Path'                 => 0,
      'Getopt::Long'               => 0,
      'LWP::UserAgent'             => 0,
      'HTML::TreeBuilder'          => 0,
      'XML::LibXML'                => 0,
      'XML::LibXML::XPathContext'  => 0,
     },
     add_to_cleanup      => [ 'CPAN-Testers-ParseReport-*' ],
     create_makefile_pl => 'traditional',
);

$builder->create_build_script();
