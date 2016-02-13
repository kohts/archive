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

use Carp;
use Data::Dumper;
use File::Spec;
use File::Basename;

$Data::Dumper::Sortkeys = 1;
$| = 1;

sub zero_pad {
    my ($v, $length) = @_;

    return $v unless defined($v);
    
    $length = 2 unless $length;
    
    if (length($v) > $length) {
        Carp::confess("unable to pad string [$v] to length [$length] as it is longer");
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
            Carp::confess("ERROR: unable to open directory [$dirname]");
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

    Carp::confess("unable to write to [$opts->{'log_file'}]") if -f $opts->{'log_file'} && ! -w $opts->{'log_file'};

    my $log_msg = $msg;
    $log_msg =~ s/[\r\n]/ /g;
    $log_msg = localtime() . " " . $log_msg . "\n";

    print $log_msg;

    my $fh;
    open($fh, ">>" . $opts->{'log_file'}) || Carp::confess ("unable to open for append [$opts->{'log_file'}]");
    print $fh $log_msg;
    close($fh);
}

sub canonical_document_name {
    my ($d) = @_;
    return $d->{'archive_type'} . "-" . $d->{'archive_id'} . "-" . $d->{'document_id'};
}

if (!$ARGV[0]) {
    Carp::confess("need archive directory\n");
}

my $archive_dir = $ARGV[0];
if (! -d $archive_dir) {
    Carp::confess("not a directory: [$archive_dir]");
}

my $dry_run = $ARGV[1];

$main::log_file = File::Spec->catfile($archive_dir, basename($0) . ".log");
my $d = read_dir($archive_dir);

DOCUMENT: foreach my $doc_dir (@{$d}) {
    my $full_doc_dir = File::Spec->catfile($archive_dir, $doc_dir);

    # skip non-directories
    next DOCUMENT unless -d $full_doc_dir;

    my $current_document;
    
    my $page_renames = {
        # old page "path/filename" -> new page "path/filename"
        'old_to_new' => {},
        'new_from_old' => {},
        'tmp_old_to_new' => {},
        };
    my $push_page_rename = sub {
        my ($o) = @_;

        my $new_full_page_path = File::Spec->catfile($o->{'current_document_path'}, $o->{'new_page_name'});

        Carp::confess ("At least two identical old page paths [" . $o->{'current_page_path'} . "], something is very wrong")
            if defined($page_renames->{'old_to_new'}->{$o->{'current_page_path'}});
        Carp::confess ("One new page generated from at least two old page paths [$new_full_page_path], something is very wrong")
            if defined($page_renames->{'new_from_old'}->{$new_full_page_path});

        $page_renames->{'old_to_new'}->{$o->{'current_page_path'}} = $new_full_page_path;
        $page_renames->{'new_from_old'}->{$new_full_page_path} = $o->{'current_page_path'};
    };

    if ($doc_dir =~ /^(of|nvf)[\-\ \_](\d+?)[\-\ \_](\d[\d_,;\-\ \.]*)$/) {
        my ($archive_type, $part, $id) = ($1, $2, $3);

        $current_document = {
            'archive_dir' => $archive_dir,
            'archive_type' => $archive_type,
            'archive_id' => $part,
            'document_id' => $id,
            'full_document_path' => $full_doc_dir,
            };

        my $change_document_path = sub {
            my ($opts) = @_;
            $opts = {} unless $opts;
            Carp::confess("Need document") unless $opts->{'document'};
            Carp::confess("Need new path") unless $opts->{'new_path'};

            if (-d $opts->{'new_path'}) {
                Carp::confess("unable to rename [$opts->{'document'}->{'full_document_path'}] to new name: directory [$opts->{'new_path'}] exists!");
            }

            do_log("renaming $opts->{'document'}->{'full_document_path'} -> $opts->{'new_path'}");
            rename ($opts->{'document'}->{'full_document_path'}, $opts->{'new_path'}) ||
                Carp::confess("unable to rename [$opts->{'document'}->{'full_document_path'}] to [$opts->{'new_path'}]: $!");
          
            $opts->{'document'}->{'full_document_path'} = $opts->{'new_path'};
        };

        my $change_document_id = sub {
            my ($opts) = @_;
            $opts = {} unless $opts;
            Carp::confess("Need document") unless $opts->{'document'};
            Carp::confess("Need new id") unless $opts->{'new_id'};
          
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
                do_log("removed garbage $full_page_path");
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
                    rename ($full_page_path, $new_full_page_path) || Carp::confess("unable to rename [$full_page_path] to [$new_full_page_path]: $!");
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

                    rename ($full_page_path, $new_full_page_path) || Carp::confess("unable to rename [$full_page_path] to [$new_full_page_path]");
                    $full_page_path = $new_full_page_path;
                    $page = $new_desc_name;
                }

                next PAGE;
            }
            
            # allow underscore in relaxed page name
            # (which is converted below to canonical page id,
            # extracted from document directory name)
            if ($page !~ /^(of|nvf)[\-\ ]{1,2}(\d+?)[\-\ \_](\d[\d_,;\-\ \.]*?)-([\d_]+?)[^\d]?.*?(\.jpg)$/) {
                print "skipping document [$doc_dir] because of invalid page format: [$page]\n";
                next DOCUMENT;
            }

    #        my ($p_archive_type, $p_delim_1, $p_part, $p_id, $p_number, $p_ext) = ($1, $2, $3, $4, $5, $6);
            my $p_parsed = {
                'archive_type' => $1,
                'part' => $2,
                'id' => $3,
                'number' => $4,
                'ext' => $5,
                };

            # this is a valid page, increment page counter
            $i = $i + 1;

            my $int_p_number = int($p_parsed->{'number'});

            my $new_page = canonical_document_name($current_document) . "-" . zero_pad($i, 3) . $p_parsed->{'ext'};
            
            # update page filename if its canonical name doesn't match its current name
            if ($new_page ne $page) {
                $push_page_rename->({
                    'current_document_path' => $current_document->{'full_document_path'},
                    'current_page_path' => $full_page_path,
                    'new_page_name' => $new_page,
                    });
            }
        }
    } elsif ($doc_dir =~ /^eh-(\d+)$/) {
        my $eh_number = $1;

        $current_document = {
            'archive_dir' => $archive_dir,
            'full_document_path' => $full_doc_dir,
            };

        # check page names inside document directory
        my $pages = read_dir($current_document->{'full_document_path'});
        my $i = 0;

        my $page_renames = {
            # old page "path/filename" -> new page "path/filename"
            'old_to_new' => {},
            'new_from_old' => {},
            'tmp_old_to_new' => {},
            };

        PAGE: foreach my $page (@{$pages}) {

            my $full_page_path = File::Spec->catfile($current_document->{'full_document_path'}, $page);

            # remove temporary files
            if ($page eq "Thumbs.db") {
                unlink($full_page_path);
                do_log("removed garbage $full_page_path");
                next;
            }

            # skip non-files
            next PAGE unless -f $full_page_path;

            my $ext;
            if ($page =~ /^eh[\-\ ](\d+?)[\-\ \_](\d+?)\.([a-zA-Z]+)$/) {
                $ext = $3;
            } elsif ($page =~ /(\d+)\.([a-zA-Z]+)$/) {
                $ext = $2;
            } else {
                print "skipping invalid page format: [$page]\n";
                next PAGE;
            }

            # this is a valid page, increment page counter
            $i = $i + 1;

            my $new_page = "eh-" . $eh_number . "-" . zero_pad($i, 3) . "." . $ext;
            
            # update page filename if its canonical name doesn't match its current name
            if ($new_page ne $page) {
                $push_page_rename->({
                    'current_document_path' => $current_document->{'full_document_path'},
                    'current_page_path' => $full_page_path,
                    'new_page_name' => $new_page,
                    });
            }
        }
    } else {
        print "skipping invalid doc_dir format: [$doc_dir]\n";
        next DOCUMENT;
    }

    if (scalar(keys %{$page_renames->{'old_to_new'}})) {
        if ($dry_run) {
            print "would do following renames: " . Data::Dumper::Dumper($page_renames->{'old_to_new'});
            next DOCUMENT;
        }

        foreach my $old_path (sort keys %{$page_renames->{'old_to_new'}}) {
            my $old_tmp = $old_path . ".old.$$";

            $page_renames->{'tmp_old_to_new'}->{$old_tmp} = {
                'old_path' => $old_path,
                'new_path' => $page_renames->{'old_to_new'}->{$old_path}
                };
            
            rename($old_path, $old_tmp) || Carp::confess("unable to rename [$old_path] to [$old_tmp]");
        }
        foreach my $old_path_tmp (sort keys %{$page_renames->{'tmp_old_to_new'}}) {
            my $rename_struct = $page_renames->{'tmp_old_to_new'}->{$old_path_tmp};

            Carp::confess("Unable to rename [$old_path_tmp], not going to overwrite [$rename_struct->{'new_path'}]")
                if -e $rename_struct->{'new_path'};
            
            rename($old_path_tmp, $rename_struct->{'new_path'}) || Carp::confess("unable to rename [$old_path_tmp] to [$rename_struct->{'new_path'}]");
            do_log("renamed $rename_struct->{'old_path'} -> $rename_struct->{'new_path'}");
        }
    }
}
