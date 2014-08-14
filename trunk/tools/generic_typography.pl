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

sub fix_emphasis {
  my ($in) = @_;
  my $out = "";

#                    1        2          3         4       5
  while ($in =~ /\G(.*?)(<emphasis.*?>)(.+?)(<\/emphasis>)(.*)/sg) {
    my @m = (0, $1, $2, $3, $4, $5);  
  
    $out .= $m[1] if $m[1];

    $m[3] = "" unless $m[3];
    $m[3] =~ s/[\r\n]//go;

    $out .= $m[2] . $m[3] .  $m[4];

    $in = $m[5];
  }

  if (!$out) {
    $out = $in;
  }
  else {
    $out .= $in if $in;
  }

  return $out;
}


my $content = "";

my $f;
open($f, $ARGV[0]);
binmode $f, ':encoding(UTF-8)';
while (<$f>) {
  my $l = $_;

  $l = replace_quotes($l);
  
  $content .= $l;
}
close($f);

$content = fix_emphasis($content);

print $content;
