#!/usr/bin/perl -w

use strict;

if (!$ARGV[0]) {
  die "usage: $0 filename\n";
}

my $previous_line;

my $f;
open($f, $ARGV[0]);
while (<$f>) {
  my $l = $_;

  if ($l =~ /^<footnote>(.*)/) {
    $l = $1 . "\n";
    chop($previous_line);
    $previous_line .= "<footnote>\n";
  } 

  print $previous_line if $previous_line;
  $previous_line = $l;
}
close($f);

print $previous_line if $previous_line;
