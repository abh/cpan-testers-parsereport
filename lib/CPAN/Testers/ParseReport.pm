package CPAN::Testers::ParseReport;

use warnings;
use strict;

use DateTime::Format::Strptime;
use File::Basename qw(basename);
use File::Path qw(mkpath);
use LWP::UserAgent;
use HTML::TreeBuilder ();
use XML::LibXML;
use XML::LibXML::XPathContext;

our $Signal = 0;

=head1 NAME

CPAN::Testers::ParseReport - parse reports to cpantesters.perl.org from various sources

=head1 VERSION

Version 0.0.4

=cut

use version; our $VERSION = qv('0.0.4');


=head1 SYNOPSIS

Nothing in here is meant for public consumption. Use C<ctgetreports>
from the commandline.

  ctgetreports --q mod:Moose Devel-Events

=head1 DESCRIPTION

This is the core module for CPAN::Testers::ParseReport. If you're not
looking to extend or alter the behaviour of this module, you probably
want to look at C<ctgetreports> instead.

=head1 OPTIONS

Are described in the <ctgetreports> manpage and are passed through to
the functions unaltered.

=head1 FUNCTIONS

=head2 parse_distro($distro,$options)

reads the cpantesters HTML page for the distro and loops through the
reports for the first (usually most recent) version of that distro
found on that page.

=cut

{
    my $ua;
    sub _ua {
        return $ua if $ua;
        $ua = LWP::UserAgent->new;
        $ua->parse_head(0);
        $ua;
    }
}

sub _download_overview {
    my($cts_dir, $distro, %Opt) = @_;
    my $format = $Opt{ctformat} || "html";
    my $ctarget = "$cts_dir/$distro.$format";
    my $cheaders = "$cts_dir/$distro.headers";
    if (! -e $ctarget or (!$Opt{local} && -M $ctarget > .25)) {
        if (-e $ctarget && $Opt{verbose}) {
            my(@stat) = stat _;
            my $timestamp = gmtime $stat[9];
            print "(timestamp $timestamp GMT)\n";
        }
        print "Fetching $ctarget..." if $Opt{verbose};
        my $resp = _ua->mirror("http://cpantesters.perl.org/show/$distro.$format",$ctarget);
        if ($resp->is_success) {
            print "DONE\n" if $Opt{verbose};
            open my $fh, ">", $cheaders or die;
            for ($resp->headers->as_string) {
                print $fh $_;
                if ($Opt{verbose} && $Opt{verbose}>1) {
                    print;
                }
            }
        } elsif (304 == $resp->code) {
            print "DONE (not modified)\n";
            my $atime = my $mtime = time;
            utime $atime, $mtime, $cheaders;
        } else {
            die $resp->status_line;
        }
    }
    return $ctarget;
}

sub _parse_html {
    my($ctarget, %Opt) = @_;
    my $tree = HTML::TreeBuilder->new;
    $tree->implicit_tags(1);
    $tree->p_strict(1);
    $tree->ignore_ignorable_whitespace(0);
    my $ccontent = do { open my $fh, $ctarget or die; local $/; <$fh> };
    $tree->parse_content($ccontent);
    $tree->eof;
    my $content = $tree->as_XML;
    my $parser = XML::LibXML->new;;
    $parser->keep_blanks(0);
    $parser->clean_namespaces(1);
    my $doc = eval { $parser->parse_string($content) };
    my $err = $@;
    unless ($doc) {
        my $distro = basename $ctarget;
        die sprintf "Error while parsing %s\: %s", $distro, $err;
    }
    $parser->clean_namespaces(1);
    my $xc = XML::LibXML::XPathContext->new($doc);
    my $nsu = $doc->documentElement->namespaceURI;
    $xc->registerNs('x', $nsu) if $nsu;
    # $DB::single++;
    my($selected_release_ul,$selected_release_distrov,$excuse_string);
    if ($Opt{vdistro}) {
        $excuse_string = "selected distro '$Opt{vdistro}'";
        ($selected_release_distrov) = $nsu ? $xc->findvalue("/x:html/x:body/x:div[\@id = 'doc']/x:div//x:h2[x:a/\@id = '$Opt{vdistro}']/x:a/\@id") :
            $doc->findvalue("/html/body/div[\@id = 'doc']/div//h2[a/\@id = '$Opt{vdistro}']/a/\@id");
        ($selected_release_ul) = $nsu ? $xc->findnodes("/x:html/x:body/x:div[\@id = 'doc']/x:div//x:h2[x:a/\@id = '$Opt{vdistro}']/following-sibling::ul[1]") :
            $doc->findnodes("/html/body/div[\@id = 'doc']/div//h2[a/\@id = '$Opt{vdistro}']/following-sibling::ul[1]");
    } else {
        $excuse_string = "any distro";
        ($selected_release_distrov) = $nsu ? $xc->findvalue("/x:html/x:body/x:div[\@id = 'doc']/x:div//x:h2[1]/x:a/\@id") :
            $doc->findvalue("/html/body/div[\@id = 'doc']/div//h2[1]/a/\@id");
        ($selected_release_ul) = $nsu ? $xc->findnodes("/x:html/x:body/x:div[\@id = 'doc']/x:div//x:ul[1]") :
            $doc->findnodes("/html/body/div[\@id = 'doc']/div//ul[1]");
    }
    unless ($selected_release_distrov) {
        warn "Warning: could not find $excuse_string in '$ctarget'";
        return;
    }
    print "SELECTED: $selected_release_distrov\n";
    my($ok,$id);
    my @all;
    for my $test ($nsu ? $xc->findnodes("x:li",$selected_release_ul) : $selected_release_ul->findnodes("li")) {
        $ok = $nsu ? $xc->findvalue("x:span[1]/\@class",$test) : $test->findvalue("span[1]/\@class");
        $id = $nsu ? $xc->findvalue("x:a[1]/text()",$test)     : $test->findvalue("a[1]/text()");
        push @all, {id=>$id,ok=>$ok};
        return if $Signal;
    }
    return \@all;
}

sub _parse_yaml {
    my($ctarget, %Opt) = @_;
    require YAML::Syck;
    my $arr = YAML::Syck::LoadFile($ctarget);
    my($selected_release_ul,$selected_release_distrov,$excuse_string);
    if ($Opt{vdistro}) {
        $excuse_string = "selected distro '$Opt{vdistro}'";
        $arr = [grep {$_->{distversion} eq $Opt{vdistro}} @$arr];
        ($selected_release_distrov) = $arr->[0]{distversion};
    } else {
        $excuse_string = "any distro";
        my $last_addition;
        my %seen;
        for my $report (@$arr) {
            unless ($seen{$report->{distversion}}++) {
                $last_addition = $report->{distversion};
            }
        }
        $arr = [grep {$_->{distversion} eq $last_addition} @$arr];
        ($selected_release_distrov) = $last_addition;
    }
    unless ($selected_release_distrov) {
        warn "Warning: could not find $excuse_string in '$ctarget'";
        return;
    }
    print "SELECTED: $selected_release_distrov\n";
    my($ok,$id);
    my @all;
    for my $test (@$arr) {
        $ok = $test->{action};
        $id = $test->{id};
        push @all, {id=>$id,ok=>$ok};
        return if $Signal;
    }
    return \@all;
}

sub _parse_single_report {
    my($report, $dumpvars, %Opt) = @_;
    my($id) = $report->{id};
    my($ok) = $report->{ok};
    my $nnt_dir = "$Opt{cachedir}/nntp-testers";
    mkpath $nnt_dir;
    my $target = "$nnt_dir/$id";
    unless (-e $target) {
        print "Fetching $target..." if $Opt{verbose};
        my $resp = _ua->mirror("http://www.nntp.perl.org/group/perl.cpan.testers/$id",$target);
        if ($resp->is_success) {
            if ($Opt{verbose}) {
                my(@stat) = stat $target;
                my $timestamp = gmtime $stat[9];
                print "(timestamp $timestamp GMT)\n";
                if ($Opt{verbose} > 1) {
                    print $resp->headers->as_string;
                }
            }
            my $headers = "$target.headers";
            open my $fh, ">", $headers or die;
            print $fh $resp->headers->as_string;
        } else {
            die $resp->status_line;
        }
    }
    parse_report($target, $dumpvars, %Opt);
}

sub parse_distro {
    my($distro,%Opt) = @_;
    my %dumpvars;
    $Opt{cachedir} ||= "$ENV{HOME}/var/cpantesters";
    my $cts_dir = "$Opt{cachedir}/cpantesters-show";
    mkpath $cts_dir;
    my $ctarget = _download_overview($cts_dir, $distro, %Opt);
    my $reports;
    $Opt{ctformat} ||= "html";
    if ($Opt{ctformat} eq "html") {
        $reports = _parse_html($ctarget);
    } else {
        $reports = _parse_yaml($ctarget);
    }
    return unless $reports;
    for my $report (@$reports) {
        _parse_single_report($report, \%dumpvars, %Opt);
    }
    if ($Opt{dumpvars}) {
        print YAML::Syck::Dump(\%dumpvars);
    }
}

=head2 parse_report($target,$dumpvars,%Opt)

Reads one report. $target is the local filename to read. $dumpvars is
a hashref which gets filled. %Opt are the options as described in the
C<ctgetreports> manpage.

=cut
sub parse_report {
    my($target,$dumpvars,%Opt) = @_;
    our @q;
    my $id = basename($target);
    my $ok;
    open my $fh, $target or die;
    my(%extract);
    my $report_writer;
    my $moduleunpack = {};
    my $expect_prereq = 0;
    my $expect_toolchain = 0;
    my $expecting_toolchain_soon = 0;

    my $in_summary = 0;
    my $in_prg_output = 0;

    my $current_headline;
    my @previous_line = ""; # so we can neutralize line breaks
  LINE: while (<$fh>) {
        next unless /<title>(\S+)/;
        $ok = $1;
        last;
    }
    seek $fh, 0, 0;
  LINE: while (<$fh>) {
        chomp; # reliable line endings?
        s/&quot;//; # HTML !!!
        if (/^--------/ && $previous_line[-2] && $previous_line[-2] =~ /^--------/) {
            $current_headline = $previous_line[-1];
            if ($current_headline =~ /PROGRAM OUTPUT/) {
                $in_prg_output = 1;
            } else {
                $in_prg_output = 0;
            }
        }
        unless ($extract{"meta:perl"}) {
            my $p5;
            if (0) {
            } elsif (/Summary of my perl5 \((.+)\) configuration:/) {
                $p5 = $1;
                $in_summary = 1;
            }
            if ($p5) {
                my($r,$v,$s,$p);
                if (($r,$v,$s,$p) = $p5 =~ /revision (\S+) version (\S+) subversion (\S+) patch (\S+)/) {
                    $r =~ s/\.0//; # 5.0 6 2!
                    $extract{"meta:perl"} = "$r.$v.$s\@$p";
                } elsif (($r,$v,$s) = $p5 =~ /revision (\S+) version (\S+) subversion (\S+)/) {
                    $r =~ s/\.0//;
                    $extract{"meta:perl"} = "$r.$v.$s";
                } elsif (($r,$v,$s) = $p5 =~ /(\d+\S*) patchlevel (\S+) subversion (\S+)/) {
                    $r =~ s/\.0//;
                    $extract{"meta:perl"} = "$r.$v.$s";
                } else {
                    $extract{"meta:perl"} = $p5;
                }
            }
        }
        unless ($extract{"meta:from"}) {
            if (0) {
            } elsif (m|<div class="h_name">From:</div> <b>(.+?)</b><br/>|) {
                $extract{"meta:from"} = $1;
            }
            $extract{"meta:from"} =~ s/\.$// if $extract{"meta:from"};
        }
        unless ($extract{"meta:date"}) {
            if (0) {
            } elsif (m|<div class="h_name">Date:</div> (.+?)<br/>|) {
                my $date = $1;
                my $p = DateTime::Format::Strptime->new(
                                                        locale => "en",
                                                        time_zone => "UTC",
                                                        # April 13, 2005 23:50
                                                        pattern => "%b %d, %Y %R",
                                                       );
                my $dt = $p->parse_datetime($date);
                $extract{"meta:date"} = $dt->datetime;
            }
            $extract{"meta:date"} =~ s/\.$// if $extract{"meta:date"};
        }
        unless ($extract{"meta:writer"}) {
            for ("$previous_line[-1] $_") {
                if (0) {
                } elsif (/created (?:automatically )?by (\S+)/) {
                    $extract{"meta:writer"} = $1;
                } elsif (/CPANPLUS, version (\S+)/) {
                    $extract{"meta:writer"} = "CPANPLUS $1";
                } elsif (/This report was machine-generated by CPAN::YACSmoke (\S+)/) {
                    $extract{"meta:writer"} = "CPAN::YACSmoke $1";
                }
                $extract{"meta:writer"} =~ s/[\.,]$// if $extract{"meta:writer"};
            }
        }
        if ($in_summary) {
            # we do that first three lines a bit too often
            my $qr = $Opt{dumpvars} || "";
            $qr = qr/$qr/ if $qr;
            unless (@q) {
                @q = @{$Opt{q}||[]};
                @q = qw(meta:perl conf:archname conf:usethreads conf:optimize meta:writer meta:from) unless @q;
            }

            my %conf_vars = map {($_ => 1)} grep { /^conf:/ } @q;

            if (/^\s*$/ || m|</pre>|) {
                $in_summary = 0;
            } else {
                my(%kv) = /\G,?\s*([^=]+)=('[^']+?'|\S+)/gc;
                while (my($k,$v) = each %kv) {
                    my $ck = "conf:$k";
                    $v =~ s/,$//;
                    if ($v =~ /^'(.*)'$/) {
                        $v = $1;
                    }
                    $v =~ s/^\s+//;
                    $v =~ s/\s+$//;
                    # $DB::single = $ck eq "conf:archname";
                    if ($qr && $ck =~ $qr) {
                        $dumpvars->{$ck}{$v}{$ok}++;
                    }
                    if ($conf_vars{$ck}) {
                        $extract{$ck} = $v;
                    }
                }
            }
        }
        if ($in_prg_output) {
            unless ($extract{"meta:output_from"}) {
                if (/Output from (.+):$/) {
                    $extract{"meta:output_from"} = $1
                }
            }
        }
        if ($expect_prereq || $expect_toolchain) {
            if (exists $moduleunpack->{type}) {
                my($module,$v);
                if ($moduleunpack->{type} == 1) {
                    (my $leader,$module,undef,$v) = eval { unpack $moduleunpack->{tpl}, $_; };
                    next LINE if $@;
                    if ($leader =~ /^-/) {
                        $moduleunpack = {};
                        $expect_prereq = 0;
                        next LINE;
                    } elsif ($leader =~ /^(
                                         buil          # build_requires:
                                        )/x) {
                        next LINE;
                    } elsif ($module =~ /^(
                                         -             # line drawing
                                        )/x) {
                        next LINE;
                    }
                } elsif ($moduleunpack->{type} == 2) {
                    (my $leader,$module,$v) = eval { unpack $moduleunpack->{tpl}, $_; };
                    next LINE if $@;
                    if ($leader =~ /^\*/) {
                        $moduleunpack = {};
                        $expect_prereq = 0;
                        next LINE;
                    }
                } elsif ($moduleunpack->{type} == 3) {
                    (my $leader,$module,$v) = eval { unpack $moduleunpack->{tpl}, $_; };
                    next LINE if $@;
                    if (!$module) {
                        $moduleunpack = {};
                        $expect_toolchain = 0;
                        next LINE;
                    } elsif ($module =~ /^-/) {
                        next LINE;
                    }
                }
                $module =~ s/\s+$//;
                if ($module) {
                    $v =~ s/^\s+//;
                    $v =~ s/\s+$//;
                    $extract{"mod:$module"} = $v;
                }
            }
            if (/(\s+)(Module\s+)(Need\s+)Have/) {
                $moduleunpack = {
                                 tpl => 'a'.length($1).'a'.length($2).'a'.length($3).'a*',
                                 type => 1,
                                };
            } elsif (/(\s+)(Module Name\s+)(Have)(\s+)Want/) {
                my $adjust_1 = 0;
                my $adjust_2 = -length($4);
                my $adjust_3 = length($4);
                # two pass would be required to see where the
                # columns really are. Or could we get away with split?
                $moduleunpack = {
                                 tpl => 'a'.length($1).'a'.(length($2)+$adjust_2).'a'.(length($3)+$adjust_3),
                                 type => 2,
                                };
            }
        }
        if (/PREREQUISITES|Prerequisite modules loaded/) {
            $expect_prereq=1;
        }
        if ($expecting_toolchain_soon) {
            if (/(\s+)(Module\s+) Have/) {
                $expect_toolchain=1;
                $expecting_toolchain_soon=0;
                $moduleunpack = {
                                 tpl => 'a'.length($1).'a'.length($2).'a*',
                                 type => 3,
                                };
            }
        }
        if (/toolchain versions installed/) {
            $expecting_toolchain_soon=1;
        }
        push @previous_line, $_;
    }                           # LINE
    my $diag = "";
    if (my $qr = $Opt{dumpvars}) {
        $qr = qr/$qr/;
        while (my($k,$v) = each %extract) {
            if ($k =~ $qr) {
                $dumpvars->{$k}{$v}{$ok}++;
            }
        }
    }
    for my $want (@q) {
        my $have  = $extract{$want} || "";
        $diag .= " $want\[$have]";
    }
    printf " %-4s %8d%s\n", $ok, $id, $diag;
    if ($Opt{interactive}) {
        require IO::Prompt;
        local @ARGV;
        local $ARGV;
        my $ans = IO::Prompt::prompt
            (
             -p => "View $id? ",
             -d => "y",
             -u => qr/[ynq]/,
             -onechar,
            );
        print "\n";
        if ($ans eq "y") {
            open my $ifh, "<", $target or die "Could not open $target: $!";
            $Opt{pager} ||= "less";
            open my $lfh, "|-", $Opt{pager} or die "Could not fork '$Opt{pager}': $!";
            local $/;
            print {$lfh} <$ifh>;
            close $ifh or die "Could not close $target: $!";
            close $lfh or die "Could not close pager: $!"
        } elsif ($ans eq "q") {
            $Signal++;
            return;
        }
    }
}

=head1 AUTHOR

Andreas Koenig, C<< <andreas.koenig.7os6VVqR at franz.ak.mind.de> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-cpan-testers-parsereport at rt.cpan.org>, or through the web
interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=CPAN-Testers-ParseReport>.
I will be notified, and then you'll automatically be notified of
progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc CPAN::Testers::ParseReport


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=CPAN-Testers-ParseReport>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/CPAN-Testers-ParseReport>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/CPAN-Testers-ParseReport>

=item * Search CPAN

L<http://search.cpan.org/dist/CPAN-Testers-ParseReport>

=back


=head1 ACKNOWLEDGEMENTS


=head1 COPYRIGHT & LICENSE

Copyright 2008 Andreas Koenig, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut

1; # End of CPAN::Testers::ParseReport
