#!/usr/bin/perl -w

use strict;

if (!$ARGV[0]) {
  die "usage: $0 filename\n";
}

my $f;
open($f, $ARGV[0]);
while (<$f>) {
  my $l = $_;

  while ($l =~ /\G(.*?)(<superscript>1<\/superscript>\/<subscript>2<\/subscript>)(.*)/sgi) {
    $l = $1 .
      "&half;" .
      $3;
  }

  print $l;
}

close($f);
