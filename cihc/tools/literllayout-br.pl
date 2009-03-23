#!/usr/bin/perl -w

use strict;

sub trim {
  my ($t) = @_;
  if ($t =~ /^[\s\t\r\n]+$/) {
    return "";
  }
  else {
    return $t;
  }
}

if (!$ARGV[0]) {
  die "usage: $0 filename\n";
}

my $in_prot;
my $in_literallayout;
my $literal_buffer = "";

my $f;
open($f, $ARGV[0]);
while (<$f>) {
  my $l = $_;

  if ($l =~ /<footnote/) {
    $in_prot = 1;
  }
  elsif ($l =~ /<\/footnote>/) {
    $in_prot = 0;
  }
  
  if (!$in_prot && $l =~ /(.*)<literallayout>(.*)[\r\n]*$/) {
    my $s = trim($1) . trim($2);
    if ($s) {
      $literal_buffer .=  $s . "<?br?>\n";
    }
    $in_literallayout = 1;
    next;
  }

  if (!$in_prot && $in_literallayout) {  
    if ($l =~ /(.*)<\/literallayout>(.*)[\r\n]*$/) {
      $literal_buffer .= trim($1) . trim($2) . "\n";

      print $literal_buffer;
      $literal_buffer = "";
      $in_literallayout = 0;
    }
    elsif ( $l =~ /(.*)[\r\n]*$/ ) {
      $literal_buffer .= $1 . "<?br?>\n";
    }
  }
  else {
    print $l;
  }
}

close($f);
