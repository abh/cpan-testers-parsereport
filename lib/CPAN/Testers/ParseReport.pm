package CPAN::Testers::ParseReport;

use warnings;
use strict;

use DateTime::Format::Strptime;
use File::Basename qw(basename);
use File::Path qw(mkpath);
use HTML::Entities qw(decode_entities);
use LWP::UserAgent;
use List::Util qw(max sum);
use Time::Local ();
use XML::LibXML;
use XML::LibXML::XPathContext;

our $default_ctformat = "html";
our $default_cturl = "http://www.cpantesters.org/show";
our $Signal = 0;

=encoding utf-8

=head1 NAME

CPAN::Testers::ParseReport - parse reports to www.cpantesters.org from various sources

=cut

use version; our $VERSION = qv('0.0.14');

=head1 SYNOPSIS

The documentation in here is normally not needed because the code is
meant to be run from a standalone program, L<ctgetreports>.

  ctgetreports --q mod:Moose Devel-Events

=head1 DESCRIPTION

This is the core module for CPAN::Testers::ParseReport. If you're not
looking to extend or alter the behaviour of this module, you probably
want to look at L<ctgetreports> instead.

=head1 OPTIONS

Are described in the L<ctgetreports> manpage and are passed through to
the functions unaltered.

=head1 FUNCTIONS

=head2 parse_distro($distro,$options)

reads the cpantesters HTML page or the YAML file for the distro and
loops through the reports for the specified or most recent version of
that distro found in these data.

=head2 parse_single_report($report,$dumpvars,$options)

mirrors and reads this report. $report is of the for

  { id => number }

$dumpvar is a hashreference that gets filled with data.

=cut

{
    my $ua;
    sub _ua {
        return $ua if $ua;
        $ua = LWP::UserAgent->new
            (
             keep_alive => 1,
            );
        $ua->parse_head(0);
        $ua;
    }
}

{
    my $xp;
    sub _xp {
        return $xp if $xp;
        $xp = XML::LibXML->new;
        $xp->keep_blanks(0);
        $xp->clean_namespaces(1);
        my $catalog = __FILE__;
        $catalog =~ s|ParseReport.pm$|ParseReport/catalog|;
        $xp->load_catalog($catalog);
        return $xp;
    }
}

sub _download_overview {
    my($cts_dir, $distro, %Opt) = @_;
    my $format = $Opt{ctformat} ||= $default_ctformat;
    my $cturl = $Opt{cturl} ||= $default_cturl;
    my $ctarget = "$cts_dir/$distro.$format";
    my $cheaders = "$cts_dir/$distro.headers";
    if ($Opt{local}) {
        unless (-e $ctarget) {
            die "Alert: No local file '$ctarget' found, cannot continue\n";
        }
    } else {
        if (! -e $ctarget or -M $ctarget > .25) {
            if (-e $ctarget && $Opt{verbose}) {
                my(@stat) = stat _;
                my $timestamp = gmtime $stat[9];
                print STDERR "(timestamp $timestamp GMT)\n" unless $Opt{quiet};
            }
            print STDERR "Fetching $ctarget..." if $Opt{verbose} && !$Opt{quiet};
            my $uri = "$cturl/$distro.$format";
            my $resp = _ua->mirror($uri,$ctarget);
            if ($resp->is_success) {
                print STDERR "DONE\n" if $Opt{verbose} && !$Opt{quiet};
                open my $fh, ">", $cheaders or die;
                for ($resp->headers->as_string) {
                    print $fh $_;
                    if ($Opt{verbose} && $Opt{verbose}>1) {
                        print STDERR $_ unless $Opt{quiet};
                    }
                }
            } elsif (304 == $resp->code) {
                print STDERR "DONE (not modified)\n" if $Opt{verbose} && !$Opt{quiet};
                my $atime = my $mtime = time;
                utime $atime, $mtime, $cheaders;
            } else {
                die sprintf
                    (
                     "No success downloading %s: %s",
                     $uri,
                     $resp->status_line,
                    );
            }
        }
    }
    return $ctarget;
}

sub _parse_html {
    my($ctarget, %Opt) = @_;
    my $content = do { open my $fh, $ctarget or die; local $/; <$fh> };
    my $preprocesswithtreebuilder = 0; # not needed since barbie switched to XHTML
    if ($preprocesswithtreebuilder) {
        require HTML::TreeBuilder;
        my $tree = HTML::TreeBuilder->new;
        $tree->implicit_tags(1);
        $tree->p_strict(1);
        $tree->ignore_ignorable_whitespace(0);
        $tree->parse_content($content);
        $tree->eof;
        $content = $tree->as_XML;
    }
    my $parser = _xp();
    my $doc = eval { $parser->parse_string($content) };
    my $err = $@;
    unless ($doc) {
        my $distro = basename $ctarget;
        die sprintf "Error while parsing %s\: %s", $distro, $err;
    }
    my $xc = XML::LibXML::XPathContext->new($doc);
    my $nsu = $doc->documentElement->namespaceURI;
    $xc->registerNs('x', $nsu) if $nsu;
    my($selected_release_ul,$selected_release_distrov,$excuse_string);
    my($cparentdiv)
        = $nsu ?
            $xc->findnodes("/x:html/x:body/x:div[\@id = 'doc']") :
                $doc->findnodes("/html/body/div[\@id = 'doc']");
    my(@releasedivs) = $nsu ?
        $xc->findnodes("//x:div[x:h2 and x:ul]",$cparentdiv) :
            $cparentdiv->findnodes("//div[h2 and ul]");
    my $releasediv;
    if ($Opt{vdistro}) {
        $excuse_string = "selected distro '$Opt{vdistro}'";
        my($fallbacktoversion) = $Opt{vdistro} =~ /(\d+\..*)/;
        $fallbacktoversion = 0 unless defined $fallbacktoversion;
      RELEASE: for my $i (0..$#releasedivs) {
            my $picked = "";
            my($x) = $nsu ?
                $xc->findvalue("x:h2/x:a[2]/\@name",$releasedivs[$i]) :
                    $releasedivs[$i]->findvalue("h2/a[2]/\@name");
            $DB::single=1;
            if ($x) {
                if ($x eq $Opt{vdistro}) {
                    $releasediv = $i;
                    $picked = " (picked)";
                }
                print STDERR "FOUND DISTRO: $x$picked\n" unless $Opt{quiet};
            } else {
                ($x) = $nsu ?
                    $xc->findvalue("x:h2/x:a[1]/\@name",$releasedivs[$i]) :
                        $releasedivs[$i]->findvalue("h2/a[1]/\@name");
                if ($x eq $fallbacktoversion) {
                    $releasediv = $i;
                    $picked = " (picked)";
                }
                print STDERR "FOUND VERSION: $x$picked\n" unless $Opt{quiet};
            }
        }
    } else {
        $excuse_string = "any distro";
    }
    unless (defined $releasediv) {
        $releasediv = 0;
    }
    # using a[1] because a[2] is missing on the first entry
    ($selected_release_distrov) = $nsu ?
        $xc->findvalue("x:h2/x:a[1]/\@name",$releasedivs[$releasediv]) :
            $releasedivs[$releasediv]->findvalue("h2/a[1]/\@name");
    ($selected_release_ul) = $nsu ?
        $xc->findnodes("x:ul",$releasedivs[$releasediv]) :
            $releasedivs[$releasediv]->findnodes("ul");
    unless (defined $selected_release_distrov) {
        warn "Warning: could not find $excuse_string in '$ctarget'";
        return;
    }
    print STDERR "SELECTED: $selected_release_distrov\n" unless $Opt{quiet};
    my($id);
    my @all;
    for my $test ($nsu ?
                  $xc->findnodes("x:li",$selected_release_ul) :
                  $selected_release_ul->findnodes("li")) {
        $id = $nsu ?
            $xc->findvalue("x:a[1]/text()",$test)     :
                $test->findvalue("a[1]/text()");
        push @all, {id=>$id};
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
    print STDERR "SELECTED: $selected_release_distrov\n" unless $Opt{quiet};
    my @all;
    for my $test (@$arr) {
        my $id = $test->{id};
        push @all, {id=>$id};
        return if $Signal;
    }
    @all = sort { $b->{id} <=> $a->{id} } @all;
    return \@all;
}

sub parse_single_report {
    my($report, $dumpvars, %Opt) = @_;
    my($id) = $report->{id};
    $Opt{cachedir} ||= "$ENV{HOME}/var/cpantesters";
    my $nnt_dir = "$Opt{cachedir}/nntp-testers";
    mkpath $nnt_dir;
    my $target = "$nnt_dir/$id";
    if ($Opt{local}) {
        unless (-e $target) {
            warn "Warning: No local file '$target' found, skipping\n";
            return;
        }
    } else {
        if (! -e $target) {
            print STDERR "Fetching $target..." if $Opt{verbose} && !$Opt{quiet};
            my $resp = _ua->mirror("http://www.nntp.perl.org/group/perl.cpan.testers/$id",$target);
            if ($resp->is_success) {
                if ($Opt{verbose}) {
                    my(@stat) = stat $target;
                    my $timestamp = gmtime $stat[9];
                    print STDERR "(timestamp $timestamp GMT)\n" unless $Opt{quiet};
                    if ($Opt{verbose} > 1) {
                        print STDERR $resp->headers->as_string unless $Opt{quiet};
                    }
                }
                my $headers = "$target.headers";
                open my $fh, ">", $headers or die;
                print $fh $resp->headers->as_string;
            } else {
                die $resp->status_line;
            }
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
    if ($Opt{solve}) {
        require Statistics::Regression;
        $Opt{dumpvars} = "." unless defined $Opt{dumpvars};
    }
    my $ctarget = _download_overview($cts_dir, $distro, %Opt);
    my $reports;
    $Opt{ctformat} ||= $default_ctformat;
    if ($Opt{ctformat} eq "html") {
        $reports = _parse_html($ctarget,%Opt);
    } else {
        $reports = _parse_yaml($ctarget,%Opt);
    }
    return unless $reports;
    for my $report (@$reports) {
        parse_single_report($report, \%dumpvars, %Opt);
        last if $Signal;
    }
    if ($Opt{dumpvars}) {
        require YAML::Syck;
        my $dumpfile = $Opt{dumpfile} || "ctgetreports.out";
        open my $fh, ">", $dumpfile or die "Could not open '$dumpfile' for writing: $!";
        print $fh YAML::Syck::Dump(\%dumpvars);
        close $fh or die "Could not close '$dumpfile': $!"
    }
    if ($Opt{solve}) {
        solve(\%dumpvars,%Opt);
    }
}

=head2 parse_report($target,$dumpvars,%Opt)

Reads one report. $target is the local filename to read. $dumpvars is
a hashref which gets filled. %Opt are the options as described in the
C<ctgetreports> manpage.

Note: this parsing is a bit dirty but as it seems good enough I'm not
inclined to change it. We parse HTML with a regexps only, no HTML
parser working, only the entities are decoded.

=cut
sub parse_report {
    my($target,$dumpvars,%Opt) = @_;
    our @q;
    my $id = basename($target);
    my($ok,$about);

    my(%extract);

    my $report;
    my @qr = map /^qr:(.+)/, @{$Opt{q}};
    if ($Opt{raw} || @qr) {
        open my $fh, $target or die "Could not open '$target': $!";
        local $/;
        $report = decode_entities <$fh>;
        close $fh;
        for my $qr (@qr) {
            my $cqr = eval "qr{$qr}";
            die "Could not compile regular expression '$qr': $@" if $@;
            my(@matches) = $report =~ $cqr;
            my $v;
            if (@matches) {
                if (@matches==1) {
                    $v = $matches[0];
                } else {
                    $v = join "", map {"($_)"} @matches;
                }
            } else {
                $v = "";
            }
            $extract{"qr:$qr"} = $v;
        }
    }

    open my $fh, $target or die "Could not open '$target': $!";

    my $report_writer;
    my $moduleunpack = {};
    my $expect_prereq = 0;
    my $expect_toolchain = 0;
    my $expecting_toolchain_soon = 0;

    my $in_summary = 0;
    my $in_prg_output = 0;
    my $in_env_context = 0;

    my $current_headline;
    my @previous_line = ""; # so we can neutralize line breaks
  LINE: while (<$fh>) {
        next unless /<title>(\S+)\s+(\S+)/;
        $ok = $1;
        $about = $2;
        $extract{"meta:ok"}    = $ok;
        $extract{"meta:about"} = $about;
        last;
    }
    seek $fh, 0, 0;
  LINE: while (<$fh>) {
        s/\r?\n\z//;
        while (/!$/) {
            my $followupline = <$fh>;
            $followupline =~ s/^\s+//; # remo leading space
            $_ .= $followupline;
            s/\r?\n\z//;
        }
        $_ = decode_entities $_;
        if (/^--------/ && $previous_line[-2] && $previous_line[-2] =~ /^--------/) {
            $current_headline = $previous_line[-1];
            if ($current_headline =~ /PROGRAM OUTPUT/) {
                $in_prg_output = 1;
            } else {
                $in_prg_output = 0;
            }
            if ($current_headline =~ /ENVIRONMENT AND OTHER CONTEXT/) {
                $in_env_context = 1;
            } else {
                $in_env_context = 0;
            }
        }
        unless ($extract{"meta:perl"}) {
            my $p5;
            if (0) {
            } elsif (/Summary of my perl5 \((.+)\) configuration:/) {
                $p5 = $1;
                $in_summary = 1;
                $in_env_context = 0;
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
                } elsif (/This report was machine-generated by (\S+) (\S+)/) {
                    $extract{"meta:writer"} = "$1 $2";
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
                    $ck =~ s/\s+$//;
                    $v =~ s/,$//;
                    if ($v =~ /^'(.*)'$/) {
                        $v = $1;
                    }
                    $v =~ s/^\s+//;
                    $v =~ s/\s+$//;
                    if ($qr && $ck =~ $qr) {
                        $dumpvars->{$ck}{$v}{$ok}++;
                        $extract{$ck} = $v;
                    } elsif ($conf_vars{$ck}) {
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
        if ($in_env_context) {
            if (/^\s{4}(\S+)\s*=\s*(.*)$/) {
                $extract{"env:$1"} = $2;
            }
        }
        push @previous_line, $_;
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
                $in_env_context = 0;
                $moduleunpack = {
                                 tpl => 'a'.length($1).'a'.length($2).'a'.length($3).'a*',
                                 type => 1,
                                };
            } elsif (/(\s+)(Module Name\s+)(Have)(\s+)Want/) {
                $in_env_context = 0;
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
            $in_env_context = 0;
            $expect_prereq=1;
        }
        if ($expecting_toolchain_soon) {
            if (/(\s+)(Module\s+) Have/) {
                $in_env_context = 0;
                $expect_toolchain=1;
                $expecting_toolchain_soon=0;
                $moduleunpack = {
                                 tpl => 'a'.length($1).'a'.length($2).'a*',
                                 type => 3,
                                };
            }
        }
        if (/toolchain versions installed/) {
            $in_env_context = 0;
            $expecting_toolchain_soon=1;
        }
    }                           # LINE
    if ($Opt{solve}) {
        $extract{id} = $id;
        my $data = $dumpvars->{"==DATA=="} ||= [];
        push @$data, \%extract;
    }
    # ---- %extract finished ----
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
    printf STDERR " %-4s %8d%s\n", $ok, $id, $diag unless $Opt{quiet};
    if ($Opt{raw}) {
        $report =~ s/\s+\z//;
        print STDERR $report, "\n================\n" unless $Opt{quiet};
    }
    if ($Opt{interactive}) {
        require IO::Prompt;
        local @ARGV;
        local $ARGV;
        my $ans = IO::Prompt::prompt
            (
             -p => "View $id? [onechar: ynq] ",
             -d => "y",
             -u => qr/[ynq]/,
             -onechar,
            );
        print STDERR "\n" unless $Opt{quiet};
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

=head2 solve

Feeds a couple of potentially interesting data to
Statistics::Regression and sorts the result by R^2 descending. Do not
confuse this with a prove, rather take it as a useful hint. It can
save you minutes of staring at data and provide a quick overview where
one should look closer. Displays the N top candidates, where N
defaults to 3 and can be set with the C<$Opt{solvetop}> variable.

=cut
{
    my %never_solve_on = map {($_ => 1)}
        (
         "conf:ccflags",
         "conf:config_args",
         "conf:cppflags",
         "conf:lddlflags",
         "conf:uname",
         "env:PATH",
         "env:PERL5LIB",
         "env:PERL5OPT",
         'env:$^X',
         'env:$EGID',
         'env:$GID',
         'env:$UID/$EUID',
         'env:PERL5_CPANPLUS_IS_RUNNING',
         'env:PERL5_CPAN_IS_RUNNING',
         'env:PERL5_CPAN_IS_RUNNING_IN_RECURSION',
        );
    my %normalize =
        (
         id => sub { return shift },
         'meta:date' => sub {
             my($Y,$M,$D,$h,$m,$s) = shift =~ /(\d+)-(\d+)-(\d+)T(\d+):(\d+):(\d+)/;
             Time::Local::timegm($s,$m,$h,$D,$M-1,$Y);
         },
        );
sub solve {
    my($V,%Opt) = @_;
    require Statistics::Regression;
    my @regression;
  VAR: for my $variable (sort keys %$V) {
        next if $variable eq "==DATA==";
        if ($never_solve_on{$variable}){
            warn "Skipping '$variable'\n" unless $Opt{quiet};
            next VAR;
        }
        my $value_distribution = $V->{$variable};
        my $keys = keys %$value_distribution;
        my @X = qw(const);
        if ($normalize{$variable}) {
            push @X, "n_$variable";
        } else {
            for my $value (sort keys %$value_distribution) {
                my $pf = $value_distribution->{$value};
                $pf->{PASS} ||= 0;
                $pf->{FAIL} ||= 0;
                push @X, "eq_$value";
                if (
                    $pf->{PASS} xor $pf->{FAIL}
                   ) {
                    my $vl = 40;
                    substr($value,$vl) = "..." if length $value > 3+$vl;
                    my $poor_mans_freehand_estimation = 0;
                    if ($poor_mans_freehand_estimation) {
                        warn sprintf
                            (
                             "%4d %4d %-23s | %s\n",
                             $pf->{PASS},
                             $pf->{FAIL},
                             $variable,
                             $value,
                            );
                    }
                }
            }
        }
        warn "variable[$variable]keys[$keys]X[@X]\n" unless $Opt{quiet};
        my $reg = Statistics::Regression->new($variable,\@X);
      RECORD: for my $rec (@{$V->{"==DATA=="}}) {
            my $y;
            if ($rec->{"meta:ok"} eq "PASS") {
                $y = 1;
            } elsif ($rec->{"meta:ok"} eq "FAIL") {
                $y = 0;
            } else {
                next RECORD;
            }
            my %obs;
            @obs{@X} = (0) x @X;
            $obs{const} = 1;
            for my $x (@X) {
                if ($x =~ /^eq_(.+)/) {
                    my $v = $1;
                    if (exists $rec->{$variable}
                        && defined $rec->{$variable}
                        && $rec->{$variable} eq $v) {
                        $obs{$x} = 1;
                    }
                } elsif ($x =~ /^n_(.+)/) {
                    my $v = $1;
                    $obs{$x} = $normalize{$v}->($rec->{$v});
                }
            }
            $reg->include($y, \%obs);
        }
        eval {$reg->standarderrors};
        if ($@) {
            # require YAML::Syck; print STDERR "Line " . __LINE__ . ", File: " . __FILE__ . "\n" . YAML::Syck::Dump({error=>"could not determine standarderrors",variable=>$variable,k=>$reg->k, n=>$reg->n}); # XXX
        } else {
            # $reg->print;
            push @regression, $reg;
        }
    }
    my $top = $Opt{solvetop} || 3;
    for my $reg (sort {$b->rsq <=> $a->rsq} @regression) {
        $reg->print;
        last if --$top <= 0;
    }
}
}

=head1 AUTHOR

Andreas König

=head1 BUGS

Please report any bugs or feature requests through the web
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

Thanks to RJBS for module-starter.

=head1 COPYRIGHT & LICENSE

Copyright 2008 Andreas König.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut

1; # End of CPAN::Testers::ParseReport
