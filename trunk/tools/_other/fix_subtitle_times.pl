#!/usr/bin/perl

use strict;
use warnings;
use utf8;

my $srt_corrected = $ARGV[0];
my $srt_to_fix = $ARGV[1];

if (! -e $srt_corrected || ! -e $srt_to_fix) {
    die "need corrected subtitles file and the one to correct";
}

my $corrected;
my $current_obj;

my $fh1;
open($fh1, "<" . $srt_corrected);
while (my $l = <$fh1>) {
    if ($l =~ /^(\d+)$/) {
        $corrected->{$current_obj->{'n'}} = $current_obj if $current_obj;
        $current_obj = {
            'n' => $1,
            };
    }
    elsif (!$current_obj->{'time'}) {
        $current_obj->{'time'} = $l
    }
    elsif ($l !~ /^$/) {
        $current_obj->{'caption'} = "" unless $current_obj->{'caption'};
        $current_obj->{'caption'} .= $l;
    }
}
close($fh1);
$corrected->{$current_obj->{'n'}} = $current_obj if $current_obj;

open($fh1, "<" . $srt_to_fix);
while (my $l = <$fh1>) {
    if ($l =~ /^(\d+)$/) {
        if ($current_obj) {
            print $current_obj->{'n'} . "\n";
            print $corrected->{$current_obj->{'n'}}->{'time'};
            print $current_obj->{'caption'};
            print "\n";
        }

        $current_obj = {
            'n' => $1,
            };
    }
    elsif (!$current_obj->{'time'}) {
        $current_obj->{'time'} = $l
    }
    elsif ($l !~ /^$/) {
        $current_obj->{'caption'} = "" unless $current_obj->{'caption'};
        $current_obj->{'caption'} .= $l;
    }
}
if ($current_obj) {
    print $current_obj->{'n'} . "\n";
    print $corrected->{$current_obj->{'n'}}->{'time'};
    print $current_obj->{'caption'};
    print "\n";
}
close($fh1);
