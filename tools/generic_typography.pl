#!/usr/bin/perl

use strict;
use warnings;

use utf8;
binmode STDOUT, ':encoding(UTF-8)';

if (!$ARGV[0]) {
  die "usage: $0 filename\n";
}

sub replace_quotes {
  my ($l) = @_;
  
  $l =~ s/\x{201C}/\<quote\>/g;
  $l =~ s/\x{201D}/\<\/quote\>/g;
  $l =~ s/\x{2019}/\'/g;

  return $l;
}

my $f;
open($f, $ARGV[0]);
binmode $f, ':encoding(UTF-8)';
while (<$f>) {
  my $l = $_;

  $l = replace_quotes($l);

  print $l;
}
close($f);
