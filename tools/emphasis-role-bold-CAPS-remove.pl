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
open($f, $ARGV[0]) || die "unable to open [$ARGV[0]]";
binmode $f, ':encoding(UTF-8)';
while (<$f>) {
  my $l = $_;

  $f_scalar .= $l;
}
close($f);

my $in = $f_scalar;
my $out = "";

while ($in =~ /\G(.*?)(\<emphasis role="bold"\>(.+?)\<\/emphasis\>)(.*)/sg) {
  my @m = (0, $1, $2, $3, $4);

  $out .= $m[1] if $m[1];

  # all caps
  if ($m[3] eq uc($m[3])) {
    $out .= '<emphasis role="bold">' . lc($m[3]) . '</emphasis>';
#    print "boo: " . $m[3] . "::" . uc($m[3]) . "\n";
  }
  
  $in = $m[4];  
}

if (!$out) {
  $out = $f_scalar;
}
else {
  $out .= $in if $in;
}

print $out;
