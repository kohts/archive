#!/usr/bin/perl

BEGIN {
  die "ARCHIVE_HOME environment variable must be set. Unable to continue\n\n"
    unless $ENV{'ARCHIVE_HOME'};
};

use strict;
use warnings;

use lib "$ENV{'ARCHIVE_HOME'}/tools/lib";
use Docbook::Archive;

use Yandex::Tools;
use Data::Dumper;

sub write_file_scalar {
  my ($filename, $value, $opts) = @_;

  $opts = {} unless $opts;
  my $fh = Yandex::Tools::safe_open($filename, "overwrite", {'timeout' => $opts->{'timeout'} || 2});
  return 0 unless $fh;

  $value = "" unless defined($value);

  print $fh $value;
  Yandex::Tools::safe_close($fh);
}


my $steps = {
  '1' => {
    'filename_stdout_tool' => 'iod/fix_blockqoute_in_para.pl',
    },
  '2' => {
    'filename_stdout_tool' => 'emphasis-role-bold-CAPS-remove.pl',
    },
  };

my $docname = $ARGV[0];
Yandex::Tools::read_cmdline();

if (! Docbook::Archive::is_valid_document($docname)) {
  die "Not valid document [" . Yandex::Tools::safe_string($docname) . "]";
}

foreach my $stepnumber (sort keys %{$steps}) {
  my $step = $steps->{$stepnumber};  

  if ($step->{'filename_stdout_tool'}) {
    Yandex::Tools::debug("running step $stepnumber for document $docname");

    my $tool_path = $ENV{'ARCHIVE_HOME'} . "/tools/" . $step->{'filename_stdout_tool'};
    if (! -x $tool_path) {
      die "Invalid processing tool: $tool_path";
    }

    my $docbook_files = Docbook::Archive::get_document_docbook_files($docname);
    
    foreach my $docbook_file (keys %{$docbook_files}) {
      my $v = $docbook_files->{$docbook_file};
      
      my $before_processing = Yandex::Tools::read_file_scalar($v->{'absolute_name'});
      my $processed = Yandex::Tools::run_forked("$tool_path $v->{'absolute_name'}");
      if ($processed->{'exit_code'} ne 0) {
        die "Error processing file [$v->{'absolute_name'}]: " . $processed->{'err_msg'};
      }

      if ($before_processing ne $processed->{'stdout'}) {
        if (!write_file_scalar($v->{'absolute_name'}, $processed->{'stdout'})) {
          die "Unable to write step output to [$v->{'absolute_name'}]";
        }
        Yandex::Tools::debug("updated: $docbook_file");
      }
      else {
        Yandex::Tools::debug("no change: $docbook_file");
      }
    }

    next;
  }

  die "Invalid document step: " . Data::Dumper::Dumper($step);
}
