#!/usr/bin/perl

use strict;
use warnings;
use utf8;

$| = 1;

# returns nicely formatted callstack
#
sub get_callstack {
  my $cstack;
  my $i = 0;
  while ( 1 ) {
    my @caller_arr = caller($i);
    
    my $filename = $caller_arr[1];
    my $tline = $caller_arr[2];
    my $tfunc = $caller_arr[3];

    if (defined($tfunc) && $tfunc ne "") {
      if (
#        $tfunc !~ /\_\_ANON\_\_/ &&
        $tfunc !~ /.*::get_callstack/) {

        my $called = "";
        if ($filename && $filename ne '/dev/null') {
          $called .= ", called in $filename";

          if (defined($tline)) {
            $called .= " line $tline";
          }
        }
        $cstack .= "\t" . $tfunc . $called . "\n";
      }
      $i = $i + 1;
    }
    else {
      last;
    }
  }

  # following line is matched with regexp in Magic::Task,
  # update in both places if needed
  return "\nCallstack:\n" . $cstack . "\n";
}

sub my_die {
    my ($message, $opts) = @_;

    $opts //= {};

    my $msg = $message;

    if (!$opts->{'suppress_callstack'}) {
        $msg .= get_callstack();
    }

    # You can assign a number to $! to set errno if, for instance,
    # you want "$!"  to return the string for error n, or you want to set
    # the exit value for the die() operator. (Mnemonic: What just went bang?)
    $! = 1;

    CORE::die $msg;
}

sub safe_string {
  my ($str) = @_;

  if (defined($str)) {
    return $str;
  }
  else {
    return "";
  }
}

my $txt = $ARGV[0];
my $out_pfx = $ARGV[1] || "tokenized";
if (! -f $txt) {
    my_die "text file [$txt] doesn't exist";
}

my $in_f;
my $out_f;
open($in_f, $txt);
open($out_f, ">" . $txt . "." . $out_pfx);

binmode STDOUT, ':encoding(UTF-8)';
binmode $in_f, ':encoding(UTF-8)';
binmode $out_f, ':encoding(UTF-8)';

my $output_chunk = [];

while (my $l = <$in_f>) {
		chomp($l);

		my $words = [split(" ", $l, -1)];
		
		foreach my $token (@{$words}) {
				if (scalar(@{$output_chunk}) > 0) {
						print $out_f join(" ", @{$output_chunk}) . "\n";
						$output_chunk = [];
				}

				if (safe_string($token)) {
						push @{$output_chunk}, $token;
				}
		}
}
print $out_f join(" ", @{$output_chunk}) . "\n";

close($in_f);
close($out_f);
