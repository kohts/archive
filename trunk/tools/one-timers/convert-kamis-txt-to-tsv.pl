#!/usr/bin/perl

use strict;
use warnings;
use Carp;
use Data::Dumper;
use utf8;
binmode STDOUT, ':encoding(UTF-8)';

$| = 1;

sub read_file_scalar {
  my ($filename, $opts) = @_;
  $opts = {} unless $opts;
  my $f;
  my $filecontent;
  unless (open $f, $filename) {
      confess("Couldn't open $filename for reading: $!");
  }
  if ($opts->{'binmode'}) {
      binmode $f, $opts->{'binmode'};
  }

  { local $/ = undef; $filecontent = <$f>; }
  close $f;

  return $filecontent;
}

# read file, each line is an array element
#
sub read_file_array {
  my ($filename, $opts) = @_;
  $opts = {} unless $opts;

  my $arr = [];
  my $t = undef;
  
  if (-e $filename || $opts->{'mandatory'}) {
    $t = read_file_scalar($filename, $opts);
    @{$arr} = split(/\n/so, $t);
  }

  return $arr;
}

my $filename = $ARGV[0] // "";

if (! -e $filename) {
    confess("Need input filename, got [$filename]");
}

my $file = read_file_scalar($filename, {'binmode' => ':encoding(UTF-8)'});

while ($file =~ /[\r\n]+?([\d]+)\.[\r\n]+?(Документ.+?)Сохранность(.+?)[\r\n]+?(.+)/s) {
    my $doc_id = $1;
    my $doc_name = $2;
    my $other = $4;
    $file = $other;

    $doc_name =~ s/[\r\n]/ /g;
    $doc_name =~ s/Документ. Автор: Котс А.Ф. //;
    $doc_name =~ s/Место создания: г. Москва.? //g;
    $doc_name =~ s/Время создания: б\/г //;
    $doc_name =~ s/Материал: бумага //;
    $doc_name =~ s/Документ. //;

    print join("\t", (
        $doc_id,
        $doc_name,
        )) . "\n";
}
