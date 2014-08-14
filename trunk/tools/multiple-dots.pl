#!/usr/bin/perl -w

use strict;
use utf8;

binmode STDOUT, ':encoding(UTF-8)';

if (!$ARGV[0]) {
  die "usage: $0 filename\n";
}

sub safe {
  my ($l) = @_;
  if (defined($l)) {
    return $l;
  }
  else {
    return "";
  }
}

my $f;
open($f, $ARGV[0]);
binmode $f, ':encoding(UTF-8)';
while (<$f>) {
  my $l = $_;
  $l =~ s/([^\.])\.\.([^\.])/$1\.$2/g;
  $l =~ s/\s\.//g;
  $l =~ s/([^ ])   /$1 /g;
  $l =~ s/([^ ])  /$1 /g;
  print $l;
}

close($f);
