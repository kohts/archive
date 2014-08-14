#!/usr/bin/perl -w

use strict;

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
while (<$f>) {
  my $l = $_;
  
  my $out_l = "";
  while ($l =~ /\G(.*?)(<emphasis\s+role\=.*?bold.*?>|)(.*?)/sgio) {
#  while ($l =~ /\G(.*?)(23|)(.*?)/sgi) {
    my ($l1,$l2,$l3) = ($1,$2,$3);
    if ($l2) {
      $l2 = '<emphasis role="bold">';
    }
#    else {
#    }
#    print "l1: " . safe($l1) . "\n";
#    print "l2: " . safe($l2) . "\n";
#    print "l3: " . safe($l3) . "\n";
    $out_l .= safe($l1) . safe($l2) . safe($l3);
  }

  print $out_l;
}

close($f);
