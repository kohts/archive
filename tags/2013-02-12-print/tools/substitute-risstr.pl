#!/usr/bin/perl -w
#
# automatically replaces "ris. X" and "str. X"
# to corresponding xref linkends
#

use strict;

use utf8;
binmode STDOUT, ':encoding(UTF-8)';

#my $ris = "\x{0440}";

if (!$ARGV[0]) {
  die "usage: $0 filename\n";
}

my $f;
open($f, $ARGV[0]);
binmode $f, ':encoding(UTF-8)';
while (<$f>) {
  my $l = $_;

#  print $l;

  while ($l =~ /\G(.*?)([Рр]ис\.\ ([0-9a-z]+))(.*)/sgi) {
    $l = $1 . "<xref linkend=\"picture$3\" />" . $4;
  }

  while ($l =~ /\G(.*?)([Сс]тр\.\ ([0-9]+))(.*)/sgi) {
    $l = $1 . "<xref linkend=\"str$3\" />" . $4;
  }

  print $l;
}
close($f);
