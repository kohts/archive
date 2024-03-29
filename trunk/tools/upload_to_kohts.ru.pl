#!/usr/bin/perl

use strict;
use warnings;

use Getopt::Long;
use IPC::Cmd;

my $build_base = "/var/www/html";
my $upload_base = 'nit@lenin.ru:/www/www.kohts.ru/html';

my $conf = {
  'equiv' => {
    'afk-works' => 'kohts_a.f./works',
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
  'upload' => [
    { 'from' => "$build_base/SOURCE", 'to' => "." },
    { 'from' => "$build_base/IMAGES", 'to' => "images", '--delete-excluded' => 1, },
    { 'from' => "html", 'to' => "html", '--delete-excluded' => 1, },
    { 'from' => "pdf", 'to' => "." },
  ],
  };

sub sync_book {
  my ($b, $opts) = @_;

  $opts = {} unless $opts;

  foreach my $upload_struct (@{$conf->{'upload'}}) {
    my $sync_cmd = "rsync --protect-args -av ";

    if ($upload_struct->{'--delete-excluded'}) {
      $sync_cmd .= " --delete-excluded ";
    }

    if ($upload_struct->{'from'} eq 'pdf') {
      my $pdf_name = IPC::Cmd::run_forked("cat $build_base/SOURCE/$b/build/Makefile | grep ^PDF_NAME | sed \"s%PDF_NAME = %%\" | sed 's%\"%%'g");
      $pdf_name->{'stdout'} =~ s/[\r\n]$//;

      if (!$pdf_name->{'stdout'}) {
          $pdf_name = IPC::Cmd::run_forked("cd $build_base/SOURCE/$b/build && make pdfname");
      }
      $pdf_name->{'stdout'} =~ s/[\r\n]$//;

      if (!$pdf_name->{'stdout'}) {
        die "$b: unable to determine PDF name";
      }

      $sync_cmd .= "\"" . "$build_base/OUT/$b/" . $pdf_name->{'stdout'} . "\" \"$upload_base/$conf->{'equiv'}->{$b}/" . $upload_struct->{'to'} . "\"";
    }
    elsif ($upload_struct->{'from'} eq 'html') {
      $sync_cmd .= "\"" . "$build_base/OUT/$b/html/\" \"$upload_base/$conf->{'equiv'}->{$b}/" . $upload_struct->{'to'} . "/\"";
    }
    else {
      $sync_cmd .= "\"" . $upload_struct->{'from'} . "/" . $b . "/\" \"$upload_base/$conf->{'equiv'}->{$b}/" . $upload_struct->{'to'} . "/\"";
    }

    print $sync_cmd . "\n";
    
    if (!$opts->{'dry-run'}) {
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
}

my $opts = {};
GetOptions($opts, 'filter=s', 'sync', 'dry-run');

foreach my $e (sort keys %{$conf->{'equiv'}}) {
  if ($opts->{'filter'}) {
    next unless $e =~ /$opts->{'filter'}/;
  }
  
  print "$build_base/$e -> $upload_base/$conf->{'equiv'}->{$e}\n";

  if ($opts->{'sync'} || $opts->{'dry-run'}) {
    sync_book($e, $opts);
  }
}

if (!$opts->{'filter'} && !$opts->{'sync'} && !$opts->{'dry-run'}) {
  print "\ncommand line: --filter <TEXT> and --sync or --dry-run\n\n";
}
