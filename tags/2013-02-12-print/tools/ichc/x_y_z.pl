#!/usr/bin/perl -w

use strict;

if (!$ARGV[0]) {
  die "usage: $0 filename\n";
}

my $f;
open($f, $ARGV[0]);
while (<$f>) {
  my $l = $_;

  while ($l =~ /\G(.*?)(<xref linkend="tt_([\d]+)(_([\d]+))?(_([\d]+))?"\s+?\/>)(.*)/sgi) {
    my $y = $3;
    my $m = $5;
    my $d = $7;

    $l = $1 .
      "<cihc_age y=\"$y\" m=\"$m\" d=\"$d\" />" .
      $8;
  }

  print $l;
}

close($f);
