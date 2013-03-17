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

sub zero_pad {
    my ($v, $length) = @_;

    return $v unless defined($v);
    
    $length = 2 unless $length;
    
    if (length($v) > $length) {
        my_die("unable to pad string [$v] to length [$length] as it is longer");
    }
    
    while (length($v) < $length) {
        $v = "0" . $v;
    }
    
    return $v;
}

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
            my_die("ERROR: unable to open directory [$dirname]");
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

    my_die("unable to write to [$opts->{'log_file'}]") if -f $opts->{'log_file'} && ! -w $opts->{'log_file'};

    my $log_msg = $msg;
    $log_msg =~ s/[\r\n]/ /g;
    $log_msg = localtime() . " " . $log_msg . "\n";

    print $log_msg;

    my $fh;
    open($fh, ">>" . $opts->{'log_file'}) || my_die ("unable to open for append [$opts->{'log_file'}]");
    print $fh $log_msg;
    close($fh);
}

sub canonical_document_name {
    my ($d) = @_;
    return $d->{'archive_type'} . "-" . $d->{'archive_id'} . "-" . $d->{'document_id'};
}

if (!$ARGV[0]) {
    my_die("need archive directory\n");
}

my $archive_dir = $ARGV[0];
if (! -d $archive_dir) {
    my_die "not a directory: [$archive_dir]";
}

$main::log_file = File::Spec->catfile($archive_dir, basename($0) . ".log");
my $d = read_dir($archive_dir);

DOCUMENT: foreach my $doc_dir (@{$d}) {
    my $full_doc_dir = File::Spec->catfile($archive_dir, $doc_dir);

    # skip non-directories
    next DOCUMENT unless -d $full_doc_dir;

    if ($doc_dir !~ /^(of|nvf)[\-\ \_](\d+?)[\-\ \_](\d[\d_,;\-\ \.]+)$/) {
        print "skipping invalid doc_dir format: [$doc_dir]\n";
        next DOCUMENT;
    }
    my ($archive_type, $part, $id) = ($1, $2, $3);

    my $current_document = {
        'archive_dir' => $archive_dir,
        'archive_type' => $archive_type,
        'archive_id' => $part,
        'document_id' => $id,
        'full_document_path' => $full_doc_dir,
        };

    my $change_document_path = sub {
        my ($opts) = @_;
        $opts = {} unless $opts;
        my_die "Need document" unless $opts->{'document'};
        my_die "Need new path" unless $opts->{'new_path'};

        if (-d $opts->{'new_path'}) {
            my_die("unable to rename [$opts->{'document'}->{'full_document_path'}] to new name: directory [$opts->{'new_path'}] exists!");
        }

        do_log("renaming $opts->{'document'}->{'full_document_path'} -> $opts->{'new_path'}");
        rename ($opts->{'document'}->{'full_document_path'}, $opts->{'new_path'}) ||
            my_die "unable to rename [$opts->{'document'}->{'full_document_path'}] to [$opts->{'new_path'}]: $!";
      
        $opts->{'document'}->{'full_document_path'} = $opts->{'new_path'};
    };

    my $change_document_id = sub {
        my ($opts) = @_;
        $opts = {} unless $opts;
        my_die "Need document" unless $opts->{'document'};
        my_die "Need new id" unless $opts->{'new_id'};
      
        my $new_doc_dir = File::Spec->catfile(
            $opts->{'document'}->{'archive_dir'},
            canonical_document_name({
                'archive_type' => $opts->{'document'}->{'archive_type'},
                'archive_id' => $opts->{'document'}->{'archive_id'},
                'document_id' => $opts->{'new_id'},
                })
            );

        $change_document_path->({
            'document' => $opts->{'document'},
            'new_path' => $new_doc_dir,
            });
        $opts->{'document'}->{'document_id'} = $opts->{'new_id'};
    };

    # remove trailing minus
    if ($current_document->{'document_id'} =~ /\-$/) {
        my $new_id = $current_document->{'document_id'};
        $new_id =~ s/\-$//;
        $change_document_id->({
            'document' => $current_document,
            'new_id' => $new_id,
            });
    }

    # make canonical document directory name
    if (length($current_document->{'document_id'}) < 4) {
        my $new_id = "";
        for(my $i = length($current_document->{'document_id'}); $i < 4; $i++) {
            $new_id = "0" . $new_id;
        }
        $new_id = $new_id . $current_document->{'document_id'};
        $change_document_id->({
            'document' => $current_document,
            'new_id' => $new_id,
            });
    }

    # canonical delimiters in id
    if ($current_document->{'document_id'} =~ /,/) {
        my $t_id = $current_document->{'document_id'};
        $t_id =~ s/,/;/g;
        $change_document_id->({
            'document' => $current_document,
            'new_id' => $t_id,
            });
    }

    # canonical delimiters between document identification parts
    if (File::Spec->catfile($current_document->{'archive_dir'}, canonical_document_name($current_document)) ne $current_document->{'full_document_path'}) {
        $change_document_path->({
            'document' => $current_document,
            'new_path' => File::Spec->catfile($current_document->{'archive_dir'}, canonical_document_name($current_document)),
            });
    }

    # check page names inside document directory
    my $pages = read_dir($current_document->{'full_document_path'});
    my $i = 0;
    PAGE: foreach my $page (@{$pages}) {

        my $full_page_path = File::Spec->catfile($current_document->{'full_document_path'}, $page);

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
                rename ($full_page_path, $new_full_page_path) || my_die "unable to rename [$full_page_path] to [$new_full_page_path]: $!";
                do_log("fixing $full_page_path -> $new_full_page_path");
                $full_page_path = $new_full_page_path;
                $page =~ s/\.txt//;
            }

            # give description file canonical name
            my ($name, $ext) = ($page =~ /^(.+)(\..+)$/);

            if ($name ne canonical_document_name($current_document)) {
                my $new_desc_name = canonical_document_name($current_document) . $ext;
                my $new_full_page_path = File::Spec->catfile($current_document->{'full_document_path'}, $new_desc_name);

                if (-f $new_full_page_path) {
                    print "more than one txt file in document: [$current_document->{'full_document_path'}]\n";
                    next PAGE;
                }

                do_log("fixing $full_page_path -> $new_full_page_path");

                rename ($full_page_path, $new_full_page_path) || my_die "unable to rename [$full_page_path] to [$new_full_page_path]";
                $full_page_path = $new_full_page_path;
                $page = $new_desc_name;
            }

            next PAGE;
        }
        
        # allow underscore in relaxed page name
        # (which is converted below to canonical page id,
        # extracted from document directory name)
        if ($page !~ /^(of|nvf)[\-\ ](\d+?)[\-\ \_](\d[\d_,;\-\ \.]+?)-(\d+?)(\.jpg)$/) {
            print "skipping invalid page format: [$page]\n";
            next PAGE;
        } 

        # this is a valid page, increment page counter
        $i = $i + 1;

        my ($p_archive_type, $p_part, $p_id, $p_number, $p_ext) = ($1, $2, $3, $4, $5);
        my $int_p_number = int($p_number);

        # update page name parts according to current_document parameters
        if ($current_document->{'archive_type'} ne $p_archive_type ||
            $current_document->{'archive_id'} ne $p_part ||
            $current_document->{'document_id'} ne $p_id ||
            $int_p_number ne $i ||
            length($p_number) ne 3) {
            
            my $new_page = canonical_document_name($current_document) . "-" . zero_pad($i, 3) . $p_ext;
            my $new_full_page_path = File::Spec->catfile($current_document->{'full_document_path'}, $new_page);

            if (-e $new_full_page_path) {
                my_die ("unable to rename [$full_page_path] to [$new_full_page_path], destination exists");
            }

            do_log("renaming $full_page_path -> $new_full_page_path");
            rename($full_page_path, $new_full_page_path) || my_die "unable to rename [$full_page_path] to [$new_full_page_path]\n";
        }
    }
}