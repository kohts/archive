#!/usr/bin/perl -w

use strict;

if (!$ARGV[0]) {
  die "usage: $0 filename\n";
}

my $in_literallayout;
my $literal_buffer = "";

my $f;
open($f, $ARGV[0]);
while (<$f>) {
  my $l = $_;

  if ($l =~ /<literallayout>/) {
    $in_literallayout = 1;
  }

  if ($in_literallayout) {

    if ($l =~ /<footnote>/) {
      if ($literal_buffer =~ /\n$/s ) {
        chop($literal_buffer);
      }
    } 

    $literal_buffer .= $l;
  
    if ($l =~ /<\/literallayout>/) {
      print $literal_buffer;
      $literal_buffer = "";
      $in_literallayout = 0;
    }
  }
  else {
    print $l;
  }
}

close($f);
