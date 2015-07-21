#!/usr/bin/perl

BEGIN {
  die "ARCHIVE_HOME environment variable must be set. Unable to continue\n\n"
    unless $ENV{'ARCHIVE_HOME'};

  if (-d "/home/petya/CPAN/Yandex--Tools") {
    $ENV{'TEST_LIB'} = "/home/petya/CPAN/Yandex--Tools/lib";
  }
  else {
    $ENV{'TEST_LIB'} = "/";
  }
};

use strict;
use warnings;

use lib "$ENV{'ARCHIVE_HOME'}/tools/lib";
use lib "$ENV{'TEST_LIB'}";
use Docbook::Archive;

use IPC::Cmd;
use Yandex::Tools;
use Data::Dumper;
use POSIX;
use Time::HiRes qw/usleep/;
use Carp;

my $steps = {
    '1' => { 'filename_stdout_tool' => 'iod/fix_blockqoute_in_para.pl', },
    '2' => { 'filename_stdout_tool' => 'remove_empty_para.pl', },
    '3' => { 'filename_stdout_tool' => 'replace-dash-with-mdash.pl', },
    '4' => { 'filename_stdout_tool' => 'replace-tridot-with-three-dots.pl', },
    '5' => { 'filename_stdout_tool' => 'fix-ulink-tag.pl', },
    '6' => { 'filename_stdout_tool' => 'trim_trailing_space.pl', },
    };

my $children = {};

my $wait_free_resource = sub {
    my ($max_children) = @_;
    $max_children //= 3;
    while (scalar(keys %{$children}) > $max_children) {
        foreach my $cpid (keys %{$children}) {
            if (waitpid($cpid, WNOHANG) == -1) {
                delete ($children->{$cpid});
            }
        }
        usleep(100_000);
    }
};

my $docname = $ARGV[0];
Yandex::Tools::read_cmdline();

if (! Docbook::Archive::is_valid_document($docname)) {
    Carp::confess("Not valid document [" . Yandex::Tools::safe_string($docname) . "]");
}

my $filename_filter;
if (Yandex::Tools::defined_cmdline_param("filter")) {
    $filename_filter = Yandex::Tools::get_cmdline_param("filter");
}

foreach my $stepnumber (sort keys %{$steps}) {
    my $step = $steps->{$stepnumber};  

    next unless $step->{'filename_stdout_tool'};
    
    my $tool_path = $ENV{'ARCHIVE_HOME'} . "/tools/filters/" . $step->{'filename_stdout_tool'};
    if (! -x $tool_path) {
        confess("Invalid processing tool: $tool_path");
    }

    Yandex::Tools::debug("running step [$stepnumber] [$tool_path] for document [$docname]");

    my $docbook_files = Docbook::Archive::get_document_docbook_files($docname);

    foreach my $docbook_file (keys %{$docbook_files}) {
        if ($filename_filter && $docbook_file !~ /$filename_filter/) {
            next;
        }

        $wait_free_resource->();

        my $child_pid = fork();
        if ($child_pid) {
            $children->{$child_pid} = 1;
        } elsif (defined($child_pid)) {

            my $v = $docbook_files->{$docbook_file};
            
            my $before_processing = Yandex::Tools::read_file_scalar($v->{'absolute_name'});
            my $processed = IPC::Cmd::run_forked("$tool_path \"$v->{'absolute_name'}\"");
            if ($processed->{'exit_code'} ne 0 || $processed->{'stderr'} ne '') {
                Carp::confess("Error processing file [$v->{'absolute_name'}]: " . $processed->{'err_msg'});
            }

            if ($before_processing ne $processed->{'stdout'}) {
                if (!Yandex::Tools::write_file_scalar($v->{'absolute_name'}, $processed->{'stdout'})) {
                    Carp::confess("Unable to write step output to [$v->{'absolute_name'}]");
                }
                Yandex::Tools::debug("updated: $docbook_file");
            }
            else {
                Yandex::Tools::debug("no change: $docbook_file");
            }
            exit 0;
        } else {
            Carp::confess("unable to fork: $!");
        }
    }
}

$wait_free_resource->(0);
