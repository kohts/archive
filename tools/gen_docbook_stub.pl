#!/usr/bin/perl

use strict;
use warnings;

use utf8;
binmode STDOUT, ':encoding(UTF-8)';

if (!$ARGV[0]) {
  die "usage: $0 filename\n";
}

my $sects = [];

my $f;
open($f, $ARGV[0]);
binmode $f, ':encoding(UTF-8)';
while (<$f>) {
  my $l = $_;

  while ($l =~ /\&(.+?)\;/g) {
    my $sect = $1;

    next if $sect eq 'boxh';
    next if $sect !~ /[a-zA-Z]/;

    push @{$sects}, $sect;
  }

}
close($f);

foreach my $sect (@{$sects}) {
  print '<!ENTITY ' . $sect . ' SYSTEM "' . $sect . '.docbook">' . "\n";
  system("touch $sect.docbook");
}
