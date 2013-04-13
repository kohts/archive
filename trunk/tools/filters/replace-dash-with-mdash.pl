#!/usr/bin/perl

use strict;
use warnings;

use utf8;
binmode STDOUT, ':encoding(UTF-8)';

if (!$ARGV[0]) {
  die "usage: $0 filename\n";
}

my $f;
open($f, $ARGV[0]) || die "unable to open [$ARGV[0]]";
binmode $f, ':encoding(UTF-8)';
while (my $line = <$f>) {
    $line =~ s/\s+—\s+/ &mdash; /g;
    $line =~ s/[^\s]—[^\s]/ &mdash; /g;
    $line =~ s/[^\s]—/ &mdash;/g;
    $line =~ s/—[^\s]/&mdash; /g;
    print $line;
}
close($f);
