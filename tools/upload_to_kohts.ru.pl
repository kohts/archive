#!/usr/bin/perl

use strict;
use warnings;

use Getopt::Long;
use IPC::Cmd;

my $build_base = "/var/www";
my $upload_base = 'nit@lenin.ru:/www/www.kohts.ru/html';

my $conf = {
  'equiv' => {
    'dmzh' => 'ladygina-kohts_n.n./dmzh',
    'docbook-makeup' => 'docbook-makeup',
    'ertz' => 'kohts_a.f./ertz',
    'grootp' => 'kohts_a.f./grootp',
    'ichc' => 'ladygina-kohts_n.n./ichc',
    'ipss' => 'ladygina-kohts_n.n./ipss',
    'iod' => 'other/iod',
    'kodvo' => 'ladygina-kohts_n.n./kodvo',
    'menzbir' => 'kohts_a.f./menzbir',
    'mnm' => 'ladygina-kohts_n.n./mnm',
    'nim' => 'kohts_a.f./nim',
    'otchet1921' => 'ladygina-kohts_n.n./otchet1921',
    'pcm' => 'ladygina-kohts_n.n./pcm',
    'pi' => 'ladygina-kohts_n.n./pi',
    'rppeo' => 'ladygina-kohts_n.n./rppeo',
    'uml' => 'ladygina-kohts_n.n./uml',
    'vodo' => 'ladygina-kohts_n.n./vodo',
    'zhzh' => 'kohts_a.f./zhzh',
    },
  'upload' => {
    '^build$' => 1,
    '^docbook$' => 1,
    '^html$' => 1,
    '^images$' => 1,
    '.*\.pdf$' => 1,
    },
  };

sub sync_book {
  my ($b) = @_;

  my $dummy;
  opendir($dummy, "$build_base/$b") || die "unable to read $build_base/$b";
  my @all_entries = readdir($dummy);
  close($dummy);
  
  foreach my $f (sort @all_entries) {
    next if $f eq '.' || $f eq '..';

    my $upload = 0;
    foreach my $upload_pattern (keys %{$conf->{'upload'}}) {
      if ($f =~ /$upload_pattern/) {
        $upload = 1;
        last;
      }
    }
    next unless $upload;

    my $sync_cmd = "rsync --protect-args -av ";

    if (-d "$build_base/$b/$f") {
      $sync_cmd .= "\"$build_base/$b/$f/\" \"$upload_base/" . $conf->{'equiv'}->{$b} . "/$f/\"";
    }
    elsif (-f "$build_base/$b/$f") {
      $sync_cmd .= "\"$build_base/$b/$f\" \"$upload_base/" . $conf->{'equiv'}->{$b} . "/$f\"";
    }

    print $sync_cmd . "\n";
    
    my $r = IPC::Cmd::run_forked($sync_cmd, {'stdout_handler' =>
      sub {
        my ($l) = @_;
        
        return if $l =~ /^\s*$/;
        return if $l =~ /sending incremental file list/;
        return if $l =~ /sent.*received.*bytes/;
        return if $l =~ /total size is/;

        print $l;
      }
      });
    if ($r->{'exit_code'} ne 0) {
      print "error uploading: $r->{'merged'}\n";
    }
  }
}

my $sync;
my $filter;
my $result = GetOptions ("filter=s"   => \$filter, "sync"  => \$sync);

foreach my $e (sort keys %{$conf->{'equiv'}}) {
  if ($filter) {
    next unless $e =~ /$filter/;
  }
  
  print "$build_base/$e -> $upload_base/$conf->{'equiv'}->{$e}\n";

  if ($sync) {
    sync_book($e);
  }
}

if (!$filter && !$sync) {
  print "\ncommand line: --filter and --sync\n\n";
}
