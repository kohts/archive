#!/usr/bin/perl
#
# archive formatting utility
#
# document naming
# page naming
# description files
#
# todo: directory timestamp, document history?
#

use strict;
use warnings;

use Data::Dumper;
use File::Spec;
use File::Basename;

$| = 1;

sub read_dir {
  my ($dirname, $opts) = @_;

  $opts = {} unless $opts;
  $opts->{'output_type'} = 'arrayref'
    unless $opts->{'output_type'};

  my $dummy;
  if (!opendir($dummy, $dirname)) {
    if ($opts->{'non_fatal'}) {
      return 0;
    }
    else {
      die("ERROR: unable to open directory [$dirname]");
    }
  }

  my @all_entries = readdir($dummy);
  close($dummy);

  my $entries;
  if ($opts->{'output_type'} eq 'arrayref') {
    $entries = [];
  }
  elsif ($opts->{'output_type'} eq 'hashref') {
    $entries = {};
  }

  foreach my $e (sort @all_entries) {
    next if $e eq '.' || $e eq '..';

    my $absolute_name = $dirname . "/" . $e;

    if ($opts->{'output_type'} eq 'arrayref') {
      # skipping non-directories if requested
      # effectively means "get only files";
      if ($opts->{'only-directories'}) {
        next if -l $absolute_name || ! -d $absolute_name;
      }
      
      # symlinks are also files
      if ($opts->{'only-files'}) {
        next if -d $absolute_name && ! -l $absolute_name;
      }

      # simple output, feasible only
      # for non-recursive directory reads
      push(@{$entries}, $e);
    }
  }

  return $entries;
}

sub do_log {
  my ($msg, $opts) = @_;
  $opts = {} unless $opts;
  $opts->{'log_file'} = $main::log_file unless $opts->{'log_file'};

  die "unable to write to [$opts->{'log_file'}]" if -f $opts->{'log_file'} && ! -w $opts->{'log_file'};

  my $log_msg = $msg;
  $log_msg =~ s/[\r\n]/ /g;
  $log_msg = localtime() . " " . $log_msg . "\n";

  print $log_msg;

  my $fh;
  open($fh, ">>" . $opts->{'log_file'}) || die "unable to open for append [$opts->{'log_file'}]";
  print $fh $log_msg;
  close($fh);
}

if (!$ARGV[0]) {
  die "need archive directory\n";
}

my $archive_dir = $ARGV[0];
if (! -d $archive_dir) {
  die "not a directory: [$archive_dir]";
}

$main::log_file = File::Spec->catfile($archive_dir, basename($0) . ".log");
my $d = read_dir($archive_dir);

DOCUMENT: foreach my $doc_dir (@{$d}) {
  my $full_doc_dir = File::Spec->catfile($archive_dir, $doc_dir);

  # skip non-directories
  next DOCUMENT unless -d $full_doc_dir;

  if ($doc_dir !~ /^(of|nvf)-(\d+?)-([\d_,;-]+)$/) {
    print "skipping invalid doc_dir format: [$doc_dir]\n";
    next DOCUMENT;
  }
  my ($archive_type, $part, $id) = ($1, $2, $3);

  # make canonical document directory name
  if (length($id) < 4) {
    my $new_id = "";
    for(my $i = length($id); $i < 4; $i++) {
      $new_id = "0" . $new_id;
    }
    $new_id = $new_id . $id;

    my $new_doc_dir = File::Spec->catfile($archive_dir, $archive_type . "-" . $part . "-" . $new_id);
    if (-d $new_doc_dir) {
      die "unable to rename [$full_doc_dir] to canonical name: directory [$new_doc_dir] exists!";
    }
    do_log("fixing $full_doc_dir -> $new_doc_dir");
    rename ($full_doc_dir, $new_doc_dir) || die "unable to rename [$full_doc_dir] to [$new_doc_dir]: $!";
    $full_doc_dir = $new_doc_dir;
    $doc_dir = $archive_type . "-" . $part . "-" . $new_id;
    $id = $new_id;
  }

  # check page names inside document directory
  my $pages = read_dir($full_doc_dir);
  PAGE: foreach my $page (@{$pages}) {

    my $full_page_path = File::Spec->catfile($full_doc_dir, $page);

    # remove temporary files
    if ($page eq "Thumbs.db") {
      unlink($full_page_path);
      next;
    }

    # skip non-files
    next PAGE unless -f $full_page_path;

    # special processing for description files
    if ($full_page_path =~ /\.txt$/) {
      
      # remove double extension (.txt.txt)
      if ($full_page_path =~ /\.txt\.txt/) {
        my $new_full_page_path = $full_page_path;
        $new_full_page_path =~ s/\.txt//;
        rename ($full_page_path, $new_full_page_path) || die "unable to rename [$full_page_path] to [$new_full_page_path]: $!";
        do_log("fixing $full_page_path -> $new_full_page_path");
        $full_page_path = $new_full_page_path;
        $page =~ s/\.txt//;
      }

      # give description file canonical name
      my ($name, $ext) = ($page =~ /^(.+)(\..+)$/);

      if ($name ne $doc_dir) {
        my $new_desc_name = $doc_dir . $ext;
        my $new_full_page_path = File::Spec->catfile($full_doc_dir, $new_desc_name);

        if (-f $new_full_page_path) {
          print "more than one txt file in document: [$full_doc_dir]\n";
          next PAGE;
        }

        do_log("fixing $full_page_path -> $new_full_page_path");

        rename ($full_page_path, $new_full_page_path) || die "unable to rename [$full_page_path] to [$new_full_page_path]";
        $full_page_path = $new_full_page_path;
        $page = $new_desc_name;
      }

      next PAGE;
    }
    
    # allow underscore in relaxed page name
    # (which is converted below to canonical page id,
    # extracted from document directory name)
    if ($page !~ /^(of|nvf)-(\d+?)-([\d_,;-]+?)-(\d+?)(\..+)$/) {
      print "skipping invalid page format: [$page]\n";
      next PAGE;
    } 

    my ($p_archive_type, $p_part, $p_id, $p_number, $p_ext) = ($1, $2, $3, $4, $5);

    if ($archive_type ne $p_archive_type || $part ne $p_part || $id ne $p_id) {
      my $new_page = $archive_type . "-" . $part . "-" . $id . "-" . $p_number . $p_ext;
      my $new_full_page_path = File::Spec->catfile($full_doc_dir, $new_page);
      do_log("fixing $full_page_path -> $new_full_page_path");
      rename($full_page_path, $new_full_page_path) || die "unable to rename [$full_page_path] to [$new_full_page_path]\n";
    }

    #print "$doc_dir $p_archive_type $p_part $p_id $p_ext\n";
  }
}
