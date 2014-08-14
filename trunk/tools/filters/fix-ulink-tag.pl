#!/usr/bin/perl

use strict;
use warnings;
use Carp;

use utf8;
binmode STDOUT, ':encoding(UTF-8)';

if (!$ARGV[0]) {
    Carp::confess("usage: $0 filename");
}

my $f;
open($f, $ARGV[0]) || Carp::confess("unable to open [$ARGV[0]]");
binmode $f, ':encoding(UTF-8)';
while (my $line = <$f>) {
    $line =~ s/<\s+?ulink(.+)/<ulink$1/g;
    $line =~ s/(<ulink.+?\/)\s+?>/$1>/g;
    print $line;
}
close($f);
