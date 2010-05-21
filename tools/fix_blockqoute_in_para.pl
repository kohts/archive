#!/usr/bin/perl

use strict;
use warnings;

use utf8;
binmode STDOUT, ':encoding(UTF-8)';

if (!$ARGV[0]) {
  die "usage: $0 filename\n";
}

my $f_scalar = "";

my $f;
open($f, $ARGV[0]);
binmode $f, ':encoding(UTF-8)';
while (<$f>) {
  my $l = $_;

  $f_scalar .= $l;
}
close($f);


my $in = $f_scalar;
my $out = "";

#                  1           3                   4                  5
while ($in =~ /\G(.*?)(<para>([^\w]*?)<blockquote>(.+?)<\/blockquote>(.*?)<\/para>)(.*)/sg) {
  my @m = (0, $1, $2, $3, $4, $5, $6);  

  $out .= $m[1] if $m[1];
  
  if ($m[5] =~ /^[\;\,\!\.\r\n]+$/s) {
    $out .= '<blockqoute>' . $m[4] . $m[5] . '</blockqoute>';
  }
  else {
    $out .= $m[2];
  }

  $in = $m[6];  

  # comment to debug
  next;

  print
    "1: $m[1]\n" .
    "2: $m[2]\n" .
#    "3: $m[3]\n" .
    "4: $m[4]\n" .
    "5: $m[5]\n" .
    "\n\n\n"
    ;

}

if (!$out) {
  $out = $f_scalar;
}
else {
  $out .= $in if $in;
}

print $out;
