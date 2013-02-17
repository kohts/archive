#!/usr/bin/perl -w

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

  while ($l =~ /\G(.*?)(<title>(.+\.+)<\/title>)(.*)/sgi) {
    my $s = $1;
    my $e = $4;
    my $title = $3;
    $title =~ s/\.+$//go;
    $l = $s . "<title>${title}</title>" . $e;
  }

  print $l;
}
close($f);
