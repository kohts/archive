#!/usr/bin/perl
#
# This is a utility program intended to import data into DSpace.
#
# Functional startup modes are:
#
#   --validate-tsv
#       part of the --initial-import which just reads and verifies
#       the data without running actual import
#
#       Usage example (outputs to STDOUT):
#       aconsole.pl --validate-tsv --external-tsv /file/name
#   
#
#   --initial-import
#       At around 2016 this was used solelly to convert tab separated dump (UTF-8 encoded)
#       of contents of A.E. Kohts archives (which has been tracked in KAMIS in SDM,
#       part of the archive was tracked in DBX file previously) into TSV text file
#       ready to be imported into DSpace (the process relies on custom metadata fields
#       as defined in sdm-archive.xml schema).
#
#       In 2019 I've added support of reading data from local mysql database with contents
#       of KAMIS Oracle database to import data of N.N Ladygina-Kohts archive. Similar to 2016 mode
#       it still generates TSV text file ready to be imported into DSpace.
#
#       A.E. archive (2016) usage example (outputs to STDOUT):
#       aconsole.pl --initial-import --external-tsv /file/name --target-collection-handle 123456789/2
#
#       N.N. archive (2019) usage example:
#       aconsole.pl --initial-import --kamis-database db_name --target-collection-handle 123456789/2
#
#
#   --build-docbook-for-dspace
#       build html bitstream for the requested docbook file (which
#       should exist in docbook_source_base); this mode should be run
#       before running --import-bitstreams (which then imports
#       bitstreams into DSpace)
#
#       Usage example:
#       aconsole.pl --build-docbook-for-dspace --docbook-filename of-15845-0004.docbook
#
#
#   --import-bitstreams
#       - read the list of available bitstreams:
#           * scanned images of documents (external_archive_storage_base)
#           * html files of documents passed through OCR (docbook_dspace_html_out_base)
#       - match them with items in TSV file
#       - append the items into DSpace exported collection (which was prepared
#         with "dspace export").
#
#       During processing this utility creates symlinks to the bitstream
#       files in item directories and updates "contents" files.
#
#       Usage example:
#       aconsole.pl --import-bitstreams --external-tsv /file/name --dspace-exported-collection /pa/th
#
# All the important actions are logged into /var/log/dspace-sdm.log
# (which should be writable by the user which executes the utility)
#
#
# Debug startup modes:
#     --dump-config - validate configuration and output
#       raw dump of configuration ($data_desc_struct)
#
#     --data-split-by-tab - read STDIN (UTF-8 encoded) and present
#       tab separated input in a readable form (one field per line)
#
#     --data-split-by-comma - same as --data-split-by-tab but
#       with comma as a delimiter
#
#     --descriptor-dump - process list of items (command line parameters
#       or STDIN) and present them in a readable form
#
#     --dump-csv-item N M - reads whole tsv and outputs single item
#       (addresed by storage group N and storage item M in it; should be
#       defined in $data_desc_struct). Produces csv output for dspace
#       with --tsv-output or Dumper struct without.
#       Usage example: aconsole.pl --external-tsv afk-status.txt --dump-csv-item '1 1' --tsv-output
#
#     --dump-scanned-docs
#     --dump-ocr-html-docs
#     --dump-docbook-sources
#     --dump-dspace-exported-collection
#       read and dump the prepared structure
#
#     --dump-tsv-struct - reads TSV and outputs whole perl struct which
#       is then used to create output CSV; also outputs some statistics
#       Usage example: aconsole.pl --external-tsv afk-status.txt --dump-tsv-struct | less
#
#     --list-storage-items - lists all storage items by storage group
#       and outputs either the number of documents in the storage item
#       or the title.
#       Usage example: aconsole.pl --external-tsv afk-status.txt --list-storage-items [--titles]
#
#
# Operation notes
#
# Several notes on the identification of the items: each item in DSpace
# is listed in the table "item" and is uniquely identified by item.item_id,
# which is further associated with unique handle (as specified by handle.net):
#
#   dspace=> select * from handle where resource_type_id = 2;
#    handle_id |     handle     | resource_type_id | resource_id
#   -----------+----------------+------------------+-------------
#            4 | 123456789/4    |                2 |           2
#            3 | 123456789/3    |                2 |
#            5 | 123456789/5    |                2 |           3
#            6 | 123456789/6    |                2 |           4
#           11 | 123456789/10.1 |                2 |           8
#           12 | 123456789/10.2 |                2 |           9
#           10 | 123456789/10   |                2 |           9
#           14 | 123456789/14   |                2 |          12
#   (8 rows)
#
# Deleted items do not free handles (check handle_id 3 in the example above),
# resource type id(s) are stored in core/Constants.java (as of DSpace 4.1).
#
#
# A.E. Kohts SDM archives items are also uniquely identified.
# Historically archives were catalogued in two takes.
#
# First take happened for several tens of years after death of A.E. Kohts
# by several different people and was finally summed up around 1998-1999
# by Novikova N.A.:
# https://www.dropbox.com/sh/plawjce2lbtzzku/AACkqdQfG9azt46-L6UP5sRba
# (2208 storage items, documents from which are addressed additionally
# with OF (main funds) identifiers 9595-9609, 9626/1-11, 9649-9651,
# 9662/1-2, 9664/1-2, 9749/1-2, 9764-9768, 9771-9776, 10109/1-16,
# 10141/1-623, 10621/1-19, 12430/1-275, 12497/1-1212)
#
# Second take was made in 2012-2013 by Kalacheva I.P.
# (1713 storage items all addressed as OF-15845/1-1713)
#
# Upon import of the catalogs into DSpace we decided to store
# original (physical) identification of the documents, so it's
# easily possible to refer to the old identification having found
# the item in DSpace archive.
#
#
# So the structure of input data is as follows:
#
#   storage group -- physical identification system top level identifier;
#                    the group inside which all the items have unique
#                    storage (inventory) numbers. A.E. Kohts archives
#                    stored in the SDM are organized in two
#                    storage groups (as described above).
#
#   storage item  -- physical identification system second level identifier;
#                    Storage item is uniquely identified in the scope
#                    of some storage group by its inventory number.
#                    A.E. Kohts archives storage item is usually
#                    a group of objects usually combined into a paper
#                    folder or envelope or other type of wrapping.
#
#   item          -- is a document (usually a folder with several pages
#                    inside of it) or other object or several objects
#                    (such as pins for example), which is stored in a
#                    storage item possibly together with several other
#                    items (usually somehow logically interconnected).
#                    Every item in A.E. Kohts archive is uniquely identified
#                    by the its fund number and the number inside the fund
#                    (e.g. OF-10141/1)
#
#   fund number -- is the element of logical identification system which
#                  groups items according to some property of the items.
#                  "funds" termonilogy comes from Russian museology where
#                  all the museum items are grouped into funds according
#                  to the purpose of the fund. There are two main types
#                  of funds which are used for A.E. Kohts archives:
#                  main funds ("ОФ" -- acronym of "основной фонд" in Russian)
#                  and auxiliary funds ("НВФ" -- acronym of
#                  "научно-вспомогательный фонд" in Russian).
#

BEGIN {
    use FindBin;

    if ($ARGV[0] eq '--bash-completion-list') {
        my $name = $0;
        $name =~ s/.+\///;

        my $commands = {};

        my $in_commands;

        my $fh;
        open($fh, "<" . $FindBin::Bin . "/" . $name);
        while (my $l = <$fh>) {

          if ($l =~ /^my \$o_names = \[/) {
            $in_commands = 1;
          }
          
          if ($in_commands) {
            if ($l =~ /\'([^\']+)\'/) {
              $commands->{"--" . $1} = 1;
            }
            if ($l =~ /\]/) {
              $in_commands = 0;
              last;
            }
          }
        }
        close($fh);
        print join(" ", sort(keys %{$commands})) . "\n";
        exit 0;
        
    }

    die "Need ARCHIVE_ROOT environment variable to continue"
        unless $ENV{'ARCHIVE_ROOT'} && -d $ENV{'ARCHIVE_ROOT'};
}

use strict;
use warnings;
use utf8;

use SDM::Archive;
use DBD::Oracle;

my $data_desc_struct;
my $o_names = [
    'command-list',
    'build-docbook-for-dspace',
    'data-split-by-comma',
    'data-split-by-tab',
    'debug',
    'descriptor-dump=s',
    'docbook-filename=s',
    'dry-run',
    'dspace-exported-collection=s',
    'dump-config',
    'dump-docbook-sources',
    'dump-dspace-exported-collection',
    'dump-dspace-exported-item=s',
    'dump-csv-item=s',
    'dump-ocr-html-docs',
    'dump-scanned-docs',
    'dump-tsv-struct',
    'external-tsv=s',
    'import-bitstream=s',
    'import-bitstreams',
    'initial-import',
    'input-line=s',
    'limit=s',
    'list-storage-items',
    'no-xsltproc',
    'only-by-storage',
    'target-collection-handle=s',
    'tsv-output',
    'kamis-database=s',
    'titles',
    'validate-tsv',
    'create-kohtsae-community-and-collection',
    'create-kohtsnn-collection',
    'rest-test',
    'rest-add-bitstreams',
    'preprocess-book',
    'book-name=s',
    'filename-filter=s',
    'validate-pagination',
    'autoincrement-duplicate-page-number',
    'ignore-duplicate-fund-id',
    'scan-list-without-ocr',
    'scan-list-without-scan',
    'dspace-rest-get-item=s',
    'dspace-rest-get-items=s',
    'scan-schedule-scan=s',
    'target-collection=s',
    'scan-list-scheduled-for-scan',
    'scan-add-scans=s',
    'dspace-update-date-accesioned-with-scanned',
    'dspace-update-storageItemEqualized',
    'from=s',
    'oracle-parse',
    'dump',
    'generate-mysql-table-def',
    'oracle-dump-file=s',
    'local-mysql-target-tablename',
    'fill-local-mysql',
    'dspace-update-classification-groups-from-kamis-15845',
    'browse-kamis-local-summary=s',
    'browse-kamis-by-fond-number=s',
    'browse-kamis-klass',
    'browse-kamis-get-paints-by-id=s',
    'oracle-test',
    ];
my $o = {};
Getopt::Long::GetOptionsFromArray(\@ARGV, $o, @{$o_names});

sub sync_dspace_item_from_external_storage {
    my ($o) = @_;

    Carp::confess("Programmer error: external_storage_item required")
        unless defined($o->{'external_storage_item'});
    Carp::confess("Programmer error: dspace_collection_item required")
        unless defined($o->{'dspace_collection_item'});

    my $st_item = $o->{'external_storage_item'};
    my $dspace_collection_item = $o->{'dspace_collection_item'};

    my $r_struct = read_scanned_docs();

    my $updated_item = 0;

    my $orig_contents = $dspace_collection_item->{'contents'};

    HTML_FILES: foreach my $html_file (@{$st_item->{'ocr_html_document_directories'}}) {
        if ($o->{'dry-run'}) {
            print "would try to add HTML document to [$dspace_collection_item->{'storage-group-id'}/$dspace_collection_item->{'storage-item-id'}]\n";
            last HTML_FILES;
        }
        
        my $f = $st_item->{'ocr_html_document_directories_h'}->{$html_file};

        my $fname = $f;
        $fname =~ s/.+\///g;

        my $r = symlink($f, $dspace_collection_item->{'item-path'} . "/" . $fname);
        if (!$r) {
            Carp::confess("Error creating symlink from [$f] to [$dspace_collection_item->{'item-path'}/$fname]:" . $!);
        }
        
        $dspace_collection_item->{'contents'} .= $fname . "\n";
        write_file_scalar($dspace_collection_item->{'item-path'} . "/contents", $dspace_collection_item->{'contents'});

        $updated_item++;
    }

    PDF_FILES: foreach my $pdf_file (@{$st_item->{'ocr_pdf_document_directories'}}) {
        if ($o->{'dry-run'}) {
            print "would try to add PDF document to [$dspace_collection_item->{'storage-group-id'}/$dspace_collection_item->{'storage-item-id'}]\n";
            last PDF_FILES;
        }
        
        my $f = $st_item->{'ocr_pdf_document_directories_h'}->{$pdf_file};

        my $fname = $f;
        $fname =~ s/.+\///g;

        my $r = symlink($f, $dspace_collection_item->{'item-path'} . "/" . $fname);
        if (!$r) {
            Carp::confess("Error creating symlink from [$f] to [$dspace_collection_item->{'item-path'}/$fname]:" . $!);
        }
        
        $dspace_collection_item->{'contents'} .= $fname . "\n";
        write_file_scalar($dspace_collection_item->{'item-path'} . "/contents", $dspace_collection_item->{'contents'});

        $updated_item++;
    }
    
    SCAN_DIRS: foreach my $scan_dir (@{$st_item->{'scanned_document_directories'}}) {
        
        # this shouldn't happen in production as external_archive_storage_base
        # shouldn't change when this script is run; during tests though
        # this happened (because upload of archive to the test server
        # took about several weeks because of the slow network)
        next unless defined($r_struct->{'files'}->{$scan_dir});

        if ($o->{'dry-run'}) {
            print "would try to add SCAN to [$dspace_collection_item->{'storage-group-id'}/$dspace_collection_item->{'storage-item-id'}]\n";
            last SCAN_DIRS;
        }

        foreach my $f (sort keys %{$r_struct->{'files'}->{$scan_dir}}) {
            my $fname = $f;
            
            $fname =~ s/^.+\///;
            if ($f =~ m%/$scan_dir/([^/]+)/[^/]+$%) {
                $fname = $1 . "-" . $fname;
            }

            my $r = symlink($f, $dspace_collection_item->{'item-path'} . "/" . $fname);
            if (!$r) {
                Carp::confess("Error creating symlink from [$f] to [$dspace_collection_item->{'item-path'}/$fname]:" . $!);
            }

            $dspace_collection_item->{'contents'} .= $fname . "\n";
            $updated_item++;
        }
        write_file_scalar($dspace_collection_item->{'item-path'} . "/contents", $dspace_collection_item->{'contents'});
    }

    if ($updated_item) {
        # update metadata_sdm-archive-.xml
        # set sdm-archive.date.digitized to the current date
        # TODO: find a method to push metadata value to DSpace (to the existing item)
        Carp::confess("Archive format error: metadata_sdm-archive.xml expected in [$dspace_collection_item->{'item-path'}]")
            unless -e $dspace_collection_item->{'item-path'} . "/metadata_sdm-archive.xml";

        my $metadata_sdm_archive_workflow = read_dspace_xml_schema({
            'file_name' => $dspace_collection_item->{'item-path'} . "/metadata_sdm-archive.xml",
            'schema_name' => 'sdm-archive',
            });

        my $has_date_digitized;
        my $item_struct;
        DCVALUES: foreach my $dcvalue (@{$metadata_sdm_archive_workflow->{'dcvalue'}}) {
            if ($dcvalue->{'element'} eq 'date' &&
                $dcvalue->{'qualifier'} eq 'digitized') {
                
                $has_date_digitized = 1;

                if (safe_string($orig_contents) ne '') {
                    Carp::confess("Can't add bitstreams to the item which already has been digitized: [$dspace_collection_item->{'item-path'}]");
                }
                else {
                    # date.digitized might have been set for the item by --initial-import
                    # (which sets this date to the date when the item was originally scanned),
                    # but the item might not have been updated with bitstreams
                }
            }
        }
        
        # only append date.digitized to the items which do not have it
        if (!$has_date_digitized) {
            push @{$metadata_sdm_archive_workflow->{'dcvalue'}}, {
                'element' => 'date',
                'qualifier' => 'digitized',
                'content' => date_from_unixtime(time()),
                };
        
            write_file_scalar($dspace_collection_item->{'item-path'} . "/metadata_sdm-archive.xml",
                XML::Simple::XMLout($metadata_sdm_archive_workflow));
        }
    }

    return $updated_item;
}


sub separated_list_to_struct {
    my ($in_string, $opts) = @_;
    
    $opts = {} unless $opts;
    $opts->{'delimiter'} = "," unless $opts->{'delimiter'};
    
    my $out = {
        'string' => $in_string,
        'array' => [],
        'by_name0' => {},
        'by_position0' => {},
        'by_name1' => {},
        'by_position1' => {},
        'opts' => $opts,
        'number_of_elements' => 0,
        };
    my $i = 0;
    
    foreach my $el (split($opts->{'delimiter'}, $in_string)) {
        push (@{$out->{'array'}}, $el);
        
        $out->{'by_name0'}->{$el} = $i;
        $out->{'by_name1'}->{$el} = $i + 1;
        $out->{'by_position0'}->{$i} = $el;
        $out->{'by_position1'}->{$i + 1} = $el;
        
        $i = $i + 1;
    }
    
    $out->{'number_of_elements'} = $i;
    
    return $out;
}

sub extract_meta_data {
    my ($text) = @_;

    my $possible_field_labels = {
        'doc_type' => {'label' => 'Техника', 'pos' => undef, 'value' => undef},
        'doc_date' => {'label' => 'Время создания', 'pos' => undef, 'value' => undef},
        'doc_desc' => {'label' => 'Описание', 'pos' => undef, 'value' => undef},
        };
    
    my $sorted_fls = [];

    foreach my $fl (keys %{$possible_field_labels}) {
        my $fl_match_pos = index($text, $possible_field_labels->{$fl}->{'label'} . ":");
        if ($fl_match_pos < 0) {
            delete($possible_field_labels->{$fl});
        } else {
            $possible_field_labels->{$fl}->{'pos'} = $fl_match_pos;
        }
    }
    
    $sorted_fls = [sort {$possible_field_labels->{$a}->{'pos'} <=> $possible_field_labels->{$b}->{'pos'}} keys %{$possible_field_labels}];

    my $i = 0;
    foreach my $fl (@{$sorted_fls}) {
        my $rx_str = '^(.*?)' . $possible_field_labels->{$fl}->{'label'} . '\s*?:\s*?(.+)(\s*?';

        if ($i < (scalar(@{$sorted_fls}) - 1)) {
            $rx_str = $rx_str . $possible_field_labels->{$sorted_fls->[$i+1]}->{'label'} . '\s*?:\s*?.+$)';
        } else {
            $rx_str = $rx_str . '\s*?$)';
        }

#        print $rx_str . "\n";
        if ($text =~ /$rx_str/) {
            $possible_field_labels->{$fl}->{'value'} = trim($2);
#            print $1 . "\n";
#            print $2 . "\n";
#            print $3 . "\n";
            $text = $1 . $3;
        }
        $i++;
    }

#    print Data::Dumper::Dumper($possible_field_labels);

    $possible_field_labels->{'trimmed_input'} = trim($text);
    return $possible_field_labels;
}

# returns the day, i.e. 2014-12-25
sub date_from_unixtime {
    my ($unixtime) = @_;

    Carp::confess("Programmer error: invalid unixtime [" . safe_string($unixtime) . "]")
        unless $unixtime && $unixtime =~ /^\d+$/;
    
    my $time = DateTime->from_epoch("epoch" => $unixtime, "time_zone" => $data_desc_struct->{'external_archive_storage_timezone'});
    my $day = join("-", $time->year, sprintf("%02d", $time->month), sprintf("%02d", $time->day));
    return $day;
}

# read file, each line is an array element
#
sub read_file_array {
  my ($filename, $opts) = @_;
  $opts = {} unless $opts;

  my $arr = [];
  my $t = undef;
  
  if (-e $filename || $opts->{'mandatory'}) {
    $t = read_file_scalar($filename);
    @{$arr} = split(/\n/so, $t);
  }

  return $arr;
}

sub read_file_scalar {
    my ($fname, $opts) = @_;
    Carp::confess("Programmer error: need filename")
        unless defined($fname) && $fname ne "";

    $opts = {} unless $opts;
    
    my $contents = "";
    my $fh;
    open($fh, "<" . $fname) || Carp::confess("Can't open [$fname] for reading");

    if ($opts->{'binary'}) {
        binmode($fh);
    }
    else {
        binmode($fh, ':encoding(UTF-8)');
    }

    while (my $l = <$fh>) {
        $contents .= $l;
    }
    close($fh);
    return $contents;
}

sub write_file_scalar {
    my ($fname, $contents) = @_;
    Carp::confess("Programmer error: need filename")
        unless defined($fname) && $fname ne "";
    $contents = "" unless defined($contents);
    my $fh;
    open($fh, ">" . $fname) || Carp::confess("Can't open [$fname] for writing");
    binmode($fh, ':encoding(UTF-8)');
    print $fh $contents;
    close($fh);
}

sub read_scanned_docs {
    my ($opts) = @_;
    $opts = {} unless $opts;

    # cache
    return $SDM::Archive::runtime->{'read_scanned_docs'}
        if defined($SDM::Archive::runtime->{'read_scanned_docs'});

    $SDM::Archive::runtime->{'read_scanned_docs'} = {
        'scanned_docs' => {
            'array' => [
                # array of the filenames (items) in the base archive directory, i.e.
                #   eh-0716,
                #   eh-0717,
                #   etc.
                ],
            'hash' => {
                # hash of the filenames (items) in the base archive directory pointing
                # to the array of unique modification times sorted (ascending)
                # by the number of files with the modification day in the item, i.e.
                #   eh-0716 => ["2013-07-18"]
                #   eh-0719 => ["2014-10-06"]
                },
            },
        'files' => {
            # each archive file keyd by
            #   the short item directory name (1st level hash key)
            #   full item path (2nd level hash key), i.e.
            #     eh-0716 => {
            #         /gone/root/raw-afk/eh-0716/eh-0716-001.jpg => 1,
            #         /gone/root/raw-afk/eh-0716/eh-0716-002.jpg => 1,
            #     }
            #     
            #
            },
        };

    if ($opts->{'must_exist'}) {
        if (!defined($data_desc_struct->{'external_archive_storage_base'})) {
            Carp::confess("Configuration error: external_archive_storage_base must be configured" .
                " (consider creating ~/.aconsole.pl; sample in trunk/tools/.aconsole.pl)");
        }
        if (! -d $data_desc_struct->{'external_archive_storage_base'}) {
            Carp::confess("Configuration error: external_archive_storage_base points to non-existent directory [" .
                $data_desc_struct->{'external_archive_storage_base'} . "]" .
                " (consider redefining in ~/.aconsole.pl or /etc/aconsole-config.pl; sample in trunk/tools/.aconsole.pl)");
        }
    }

    return $SDM::Archive::runtime->{'read_scanned_docs'}
        unless $data_desc_struct->{'external_archive_storage_base'};


    print "reading [$data_desc_struct->{'external_archive_storage_base'}]\n" if $opts->{'debug'};
    $SDM::Archive::runtime->{'read_scanned_docs'}->{'scanned_docs'}->{'array'} =
        Yandex::Tools::read_dir($data_desc_struct->{'external_archive_storage_base'});
    
    my $cleaned_array = [];

    foreach my $item_dir (@{$SDM::Archive::runtime->{'read_scanned_docs'}->{'scanned_docs'}->{'array'}}) {
        my $item = $data_desc_struct->{'external_archive_storage_base'} . "/" . $item_dir;
        
        # scanned document is a directory
        next unless -d $item;

        push @{$cleaned_array}, $item_dir;

        $SDM::Archive::runtime->{'read_scanned_docs'}->{'files'}->{$item_dir} = {};

        my $ftimes = {};
        my $scan_dir;
        $scan_dir = sub {
            my ($dir) = @_;

            my $item_files = Yandex::Tools::read_dir($dir);

            ITEM_ELEMENT: foreach my $f (@{$item_files}) {
                if (-d $dir . "/" . $f) {
                    $scan_dir->($dir . "/" . $f);
                    next ITEM_ELEMENT;
                }

                my $fstat = [lstat($dir . "/" . $f)];
                Carp::confess("Error lstata(" . $dir . "/" . $f . "): $!")
                    if scalar(@{$fstat}) == 0;

                my $day = date_from_unixtime($fstat->[9]);

                $ftimes->{$day} = 0 unless $ftimes->{$day};
                $ftimes->{$day}++;

                $SDM::Archive::runtime->{'read_scanned_docs'}->{'files'}->{$item_dir}->{$dir . "/" . $f} = 1;
            }
        };

        $scan_dir->($item);

        $SDM::Archive::runtime->{'read_scanned_docs'}->{'scanned_docs'}->{'hash'}->{$item_dir} = [];
        foreach my $mod_day (sort {$ftimes->{$a} <=> $ftimes->{$b}} keys %{$ftimes}) {
            push @{$SDM::Archive::runtime->{'read_scanned_docs'}->{'scanned_docs'}->{'hash'}->{$item_dir}}, $mod_day;
        }
    }

    $SDM::Archive::runtime->{'read_scanned_docs'}->{'scanned_docs'}->{'array'} = $cleaned_array;

#        print Data::Dumper::Dumper($SDM::Archive::runtime->{'read_scanned_docs'});

    return $SDM::Archive::runtime->{'read_scanned_docs'};
}

sub read_ocr_html_docs {
    my ($opts) = @_;
    $opts = {} unless $opts;

    # cache
    return $SDM::Archive::runtime->{'read_ocr_html_docs'} if defined($SDM::Archive::runtime->{'read_ocr_html_docs'});

    $SDM::Archive::runtime->{'read_ocr_html_docs'} = {
        'ocr_html_files' => {
            'array' => [],
            'hash' => {},
            },
        };

    if ($opts->{'must_exist'}) {
        if (!defined($data_desc_struct->{'docbook_dspace_html_out_base'})) {
            Carp::confess("Configuration error: docbook_dspace_html_out_base must be configured" .
                " (consider creating ~/.aconsole.pl; sample in trunk/tools/.aconsole.pl)");
        }
        if (! -d $data_desc_struct->{'docbook_dspace_html_out_base'}) {
            Carp::confess("Configuration error: docbook_dspace_html_out_base points to non-existent directory [" .
                $data_desc_struct->{'docbook_dspace_html_out_base'} . "]" .
                " (consider redefining in ~/.aconsole.pl or /etc/aconsole-config.pl; sample in trunk/tools/.aconsole.pl)");
        }
    }

    return $SDM::Archive::runtime->{'read_ocr_html_docs'}
        unless $data_desc_struct->{'docbook_dspace_html_out_base'};

    $SDM::Archive::runtime->{'read_ocr_html_docs'}->{'ocr_html_files'}->{'files_array'} =
        Yandex::Tools::read_dir($data_desc_struct->{'docbook_dspace_html_out_base'});
    $SDM::Archive::runtime->{'read_ocr_html_docs'}->{'ocr_html_files'}->{'array'} = [];

    foreach my $el (@{$SDM::Archive::runtime->{'read_ocr_html_docs'}->{'ocr_html_files'}->{'files_array'}}) {
        my $item = $data_desc_struct->{'docbook_dspace_html_out_base'} . "/" . $el;

        next unless -f $item;
        next unless $el =~ /^(.+)\.html$/;

        $SDM::Archive::runtime->{'read_ocr_html_docs'}->{'ocr_html_files'}->{'hash'}->{$1} = $item;
        push @{$SDM::Archive::runtime->{'read_ocr_html_docs'}->{'ocr_html_files'}->{'array'}}, $1;
    }

    return $SDM::Archive::runtime->{'read_ocr_html_docs'};
}

sub read_ocr_pdf_docs {
    my ($opts) = @_;
    $opts = {} unless $opts;

    # cache
    return $SDM::Archive::runtime->{'read_ocr_pdf_docs'} if defined($SDM::Archive::runtime->{'read_ocr_pdf_docs'});

    $SDM::Archive::runtime->{'read_ocr_pdf_docs'} = {
        'ocr_pdf_files' => {
            'array' => [],
            'hash' => {},
            },
        };

    if ($opts->{'must_exist'}) {
        if (!defined($data_desc_struct->{'docbook_dspace_pdf_out_base'})) {
            Carp::confess("Configuration error: docbook_dspace_pdf_out_base must be configured" .
                " (consider creating ~/.aconsole.pl; sample in trunk/tools/.aconsole.pl)");
        }
        if (! -d $data_desc_struct->{'docbook_dspace_pdf_out_base'}) {
            Carp::confess("Configuration error: docbook_dspace_pdf_out_base points to non-existent directory [" .
                $data_desc_struct->{'docbook_dspace_pdf_out_base'} . "]" .
                " (consider redefining in ~/.aconsole.pl or /etc/aconsole-config.pl; sample in trunk/tools/.aconsole.pl)");
        }
    }

    return $SDM::Archive::runtime->{'read_ocr_pdf_docs'}
        unless $data_desc_struct->{'docbook_dspace_pdf_out_base'};

    $SDM::Archive::runtime->{'read_ocr_pdf_docs'}->{'ocr_pdf_files'}->{'files_array'} =
        Yandex::Tools::read_dir($data_desc_struct->{'docbook_dspace_pdf_out_base'});
    $SDM::Archive::runtime->{'read_ocr_pdf_docs'}->{'ocr_pdf_files'}->{'array'} = [];

    foreach my $el (@{$SDM::Archive::runtime->{'read_ocr_pdf_docs'}->{'ocr_pdf_files'}->{'files_array'}}) {
        my $item = $data_desc_struct->{'docbook_dspace_pdf_out_base'} . "/" . $el;

        next unless -f $item;
        next unless $el =~ /^(.+)\.pdf$/;

        $SDM::Archive::runtime->{'read_ocr_pdf_docs'}->{'ocr_pdf_files'}->{'hash'}->{$1} = $item;
        push @{$SDM::Archive::runtime->{'read_ocr_pdf_docs'}->{'ocr_pdf_files'}->{'array'}}, $1;
    }

    return $SDM::Archive::runtime->{'read_ocr_pdf_docs'};
}


# This subroutine tries to determine the date when docbook file
# was created in the repository for every file. Which is
# a rather tricky thing because probably svn2hg worked
# not very cleanly on renames, consider the excerpt
# from the git log --follow:
#
#   commit 0070e51fa497eb7fc6f33f06ddb459b595d848e4
#   Author: Petya Kohts <petya@kohts.com>
#   Date:   Sun Dec 11 18:08:08 2011 +0000
# 
#       stubs for articles
# 
#   diff --git a/books/ipss/docbook/curves_eng_print.docbook b/books/afk-works/docbook/of-10141-0042.docbook
#   similarity index 100%
#   copy from books/ipss/docbook/curves_eng_print.docbook
#   copy to books/afk-works/docbook/of-10141-0042.docbook
#
#
# For the time I'm determining file creation date as the date
# when the majority of its content was created; which is fine
# as of August 2014, but might change in the future (if there is
# some massive editing of files). Hopefully this code
# is not used by that time.
#
sub read_docbook_sources {
    my ($opts) = @_;
    $opts = {} unless $opts;

    # cache
    return $SDM::Archive::runtime->{'read_docbook_sources'}
        if defined($SDM::Archive::runtime->{'read_docbook_sources'});

    $SDM::Archive::runtime->{'read_docbook_sources'} = {
        'docbook_files' => {
            'array' => [],
            'hash' => {},
            },
        };

    if ($opts->{'must_exist'}) {
        if (!defined($data_desc_struct->{'docbook_source_base'})) {
            Carp::confess("Configuration error: docbook_source_base must be configured" .
                " (consider creating ~/.aconsole.pl; sample in trunk/tools/.aconsole.pl)");
        }
        if (! -d $data_desc_struct->{'docbook_source_base'}) {
            Carp::confess("Configuration error: docbook_source_base points to non-existent directory [" .
                $data_desc_struct->{'docbook_source_base'} . "]" .
                " (consider redefining in ~/.aconsole.pl or /etc/aconsole-config.pl; sample in trunk/tools/.aconsole.pl)");
        }
    }

    return $SDM::Archive::runtime->{'read_docbook_sources'}
        unless $data_desc_struct->{'docbook_source_base'};

    $SDM::Archive::runtime->{'read_docbook_sources'}->{'docbook_files'}->{'array'} =
        Yandex::Tools::read_dir($data_desc_struct->{'docbook_source_base'} . "/docbook");

    foreach my $el (@{$SDM::Archive::runtime->{'read_docbook_sources'}->{'docbook_files'}->{'array'}}) {
        my $item = $data_desc_struct->{'docbook_source_base'} . "/docbook/" . $el;

        next unless -f $item;
        next unless $el =~ /^of/ || $el =~ /^nvf/;
        next unless $el =~ /^(.+)\.docbook$/;

        my $docbook_short_name = $1;

#        my $cmd = "cd " . $data_desc_struct->{'docbook_source_base'} . " && git log --date=short --follow $item | grep ^Date | tail -n 1";
        my $cmd = "cd " . $data_desc_struct->{'docbook_source_base'} .
            " && " .
            'git blame --show-name --date=short ' . $item .
            ' | awk \'{print $5}\' | sort | uniq -c | sort -nr | head -n 1 | awk \'{print $2}\'';
        my $r = IPC::Cmd::run_forked($cmd);
        Carp::confess("Error getting item [$item] creation time: " . $r->{'merged'})
            if $r->{'exit_code'} != 0;
        
        my $docbook_creation_date;
        if ($r->{'stdout'} =~ /(\d\d\d\d-\d\d-\d\d)/s) {
            $docbook_creation_date = $1;
        } else {
            Carp::confess("Unexpected output from [$cmd]: " . $r->{'merged'});
        }

        $SDM::Archive::runtime->{'read_docbook_sources'}->{'docbook_files'}->{'hash'}->{$docbook_short_name} = $docbook_creation_date;
    }

    return $SDM::Archive::runtime->{'read_docbook_sources'};
}

sub read_nn_archive_from_kamis {
    my ($kamis_database, $o) = @_;

    $o = {} unless $o;

    my $today_yyyy_mm_dd = date_from_unixtime(time());

    my $doc_struct = {
        'by_storage_group' => {
            '1' => {},
            },
        'total_documents' => 0,
        };

    my $dbh = SDM::Archive::DB::get_kamis_db({'dbname' => $kamis_database});
    
    foreach my $fund_number_str (@{$data_desc_struct->{'NN'}->{'archive_funds'}}) {
        my ($of_nvf, $fund_number) = split(/\-/, $fund_number_str);
        Carp::confess("Wrong fund number format: [$fund_number_str]")
            unless $of_nvf && $fund_number;

        $of_nvf =~ s/OF/ОФ/;
        $of_nvf =~ s/NVF/НВФ/;
            
        my $sth = SDM::Archive::DB::execute_statement({
            'dbh' => \$dbh,
            'sql' => "select * from DARVIN_PAINTS where NOMK1 = ? AND NTXRAN = ?",
            'bound_values' => [$fund_number, $of_nvf],
            });
    
        while (my $row = $sth->fetchrow_hashref()) {
            $doc_struct->{'total_documents'} = $doc_struct->{'total_documents'} + 1;

            # NOMK2 is defined for e.g. OF-15111/1, but not defined for OF-15067 (without sub-numbers)
            #if (!defined($row->{'NOMK2'})) {
            #    Carp::confess("NOMK2 not defined: " . Data::Dumper::Dumper(SDM::Archive::DB::non_null_fields($row)));
            #}

            if ($o->{'dump'}) {
                print Data::Dumper::Dumper(SDM::Archive::DB::non_null_fields($row));
            }

            my $tsv_struct = SDM::Archive::tsv_struct_init({
                'dc.title[ru]' => $row->{'PNAM'},
                # https://lccn.loc.gov/sh85005227
                'dc.subject[en]' => 'Animal psychology',
                'dc.subject[ru]' => 'Зоопсихология',
                'sdm-archive.date.cataloged' => $today_yyyy_mm_dd,
                'sdm-archive.misc.notes' => '',
                });

            my $authors;
            my $authors_extracted;
            $authors = $row->{'AVTOR'} if defined($row->{'AVTOR'});
            $authors = "Неизвестный автор" unless $authors;

            if ($authors) {
                my $authors = SDM::Archive::extract_authors($authors, {'archive' => 'nn', 'do_not_die' => 0});
                foreach my $a (@{$authors->{'extracted_struct'}}) {
                    SDM::Archive::push_metadata_value($tsv_struct, 'dc.contributor.author[' . $a->{'lang'} . ']', $a->{'name'});
                    SDM::Archive::push_metadata_value($tsv_struct, 'dc.creator[' . $a->{'lang'} . ']', $a->{'name'});
                    $authors_extracted = 1;
                }
            }
            if (!$authors_extracted) {
                Carp::confess("Can't extract author from: " . Data::Dumper::Dumper(SDM::Archive::DB::non_null_fields($row)));
            }

            if (defined($row->{'DOPPOL'})) {
                SDM::Archive::push_metadata_value($tsv_struct, 'dc.identifier.other[ru]', $row->{'DOPPOL'});
            }
            if (defined($row->{'CREAT'})) {
                SDM::Archive::push_metadata_value($tsv_struct, 'dc.date.created', $row->{'CREAT'});
            }
            
            my $document_type = [];
            my $misc_notes = [];

            if (defined($row->{'KOLLIST'})) {
                my $num = $row->{'KOLLIST'};
                $num =~ s/[^\d\+]//g;
                $num = eval($num);
                
                if ($num > 0) {
                    push (@{$misc_notes}, $num . " лл.");
                }
            }
            
            my $klass = SDM::Archive::DB::kamis_get_paint_klass_by_paints_id_bas($row->{'ID_BAS'});
            
            # sort order is cosmetically important here: it puts location
            # at the end of sdm-archive.misc.notes (and doesn't really influences
            # other fields)
            foreach my $e (sort {$b->{'ID_KL'} cmp $a->{'ID_KL'}} @{$klass}) {

                if (
                    $e->{'ID_KL'} eq '10' ||
                    $e->{'ID_KL'} eq '11'
                    ) {
                    
                    foreach my $dt (split("/[\,\+]/", trim($e->{'ALLNAMES'}))) {
                        SDM::Archive::push_metadata_value($tsv_struct, 'sdm-archive.misc.document-type', $dt);
                    }
                }

                if ($e->{'ID_KL'} eq '88') {
                    SDM::Archive::push_metadata_value($tsv_struct, 'sdm-archive.misc.authenticity', $e->{'ALLNAMES'});
                }

                if ($e->{'ID_KL'} eq '45') {
                    # https://www.loc.gov/standards/iso639-2/php/code_list.php
                    my $lmap = {
                        'английский' => 'en',
                        'русский' => 'ru',
                        'французский' => 'fr',
                        'немецкий' => 'de',
                        'латинский' => 'la',
                        'чешский' => 'cs',
                        'итальянский' => 'it',
                        'испанский' => 'es',
                        'китайский' => 'zh',
                        'польский' => 'pl',
                        'венгерский' => 'hu',
                        'японский' => 'ja',
                        'норвежский' => 'no',
                        };
                    
                    if (!defined($lmap->{$e->{'ALLNAMES'}})) {
                        Carp::confess("Undefined language: " .
                            Data::Dumper::Dumper(SDM::Archive::DB::non_null_fields($row)) .
                            Data::Dumper::Dumper(SDM::Archive::DB::non_null_fields($e))
                            );
                    }

                    SDM::Archive::push_metadata_value($tsv_struct, 'dc.language.iso[en]', $lmap->{$e->{'ALLNAMES'}});
                }

                if ($e->{'ID_KL'} eq '87') {
                    SDM::Archive::push_metadata_value($tsv_struct, 'sdm-archive.misc.completeness', $e->{'ALLNAMES'});
                }

                if (
                    $e->{'ID_KL'} eq '14' ||
                    $e->{'ID_KL'} eq '16'
                    ) {
                    if (defined($e->{'NAMEK'})) {
                        push (@{$misc_notes}, join(" ", trim($e->{'NAMEK'}), trim($e->{'NAME'})));
                    }
                    else {
                        push (@{$misc_notes}, trim($e->{'ALLNAMES'}));
                    }
                }

                if (
                    $e->{'ID_KL'} eq '21' ||
                    $e->{'ID_KL'} eq '24' ||
                    $e->{'ID_KL'} eq '84'
                    ) {
                    push (@{$misc_notes}, trim($e->{'ALLNAMES'}));
                }
                if ($e->{'ID_KL'} eq '86') {
                    SDM::Archive::push_metadata_value($tsv_struct, 'sdm-archive.misc.classification-group', $e->{'ALLNAMES'});
                }
            }

            SDM::Archive::push_metadata_value($tsv_struct, 'sdm-archive.misc.notes', join(", ", @{$misc_notes}));

            Carp::confess("NOMKP not defined: " . Data::Dumper::Dumper(SDM::Archive::DB::non_null_fields($row)))
                if !defined($row->{'NOMKP'});
            Carp::confess("PNAM and VFORM not defined: " . Data::Dumper::Dumper(SDM::Archive::DB::non_null_fields($row)))
                if !defined($row->{'PNAM'}) && !defined($row->{'VFORM'});

            if (defined($row->{'DATARCH'})) {
                SDM::Archive::push_metadata_value($tsv_struct, 'sdm-archive.misc.archive-date', $row->{'DATARCH'});
            }
            if (defined($row->{'DATKP'})) {
                SDM::Archive::push_metadata_value($tsv_struct, 'sdm-archive.misc.archive-date', $row->{'DATKP'});
            }

            SDM::Archive::push_metadata_value($tsv_struct, 'sdm-archive.misc.fond', $row->{'NTXRAN'} . "-" . $row->{'NOMK1'});

            my $desc = [];
            my $nomkp = $row->{'NOMKP'};
            $nomkp =~ s/^КП//;
            
            foreach my $f (qw/PNAM VFORM PRINAUCH SAFS/){
                push (@{$desc}, $row->{$f}) if defined($row->{$f});
            }

            my $tarr;
            $tarr = SDM::Archive::get_metadata_values($tsv_struct, 'dc.date.created');
            push @{$desc}, "Время создания: " . join(", ", @{$tarr}) if scalar(@{$tarr});
            $tarr = SDM::Archive::get_metadata_values($tsv_struct, 'sdm-archive.misc.completeness');
            push @{$desc}, "Полнота: " . join(", ", @{$tarr}) if scalar(@{$tarr});
            $tarr = SDM::Archive::get_metadata_values($tsv_struct, 'sdm-archive.misc.authenticity');
            push @{$desc}, "Подлинность: " . join(", ", @{$tarr}) if scalar(@{$tarr});
            $tarr = SDM::Archive::get_metadata_values($tsv_struct, 'sdm-archive.misc.document-type');
            push @{$desc}, "Способ воспроизведения: " . join(", ", @{$tarr}) if scalar(@{$tarr});
            $tarr = SDM::Archive::get_metadata_values($tsv_struct, 'dc.identifier.other[ru]');
            push @{$desc}, "Хранение: " . join(", ", @{$tarr}) if scalar(@{$tarr});
            $tarr = SDM::Archive::get_metadata_values($tsv_struct, 'sdm-archive.misc.notes');
            push @{$desc}, "Примечания: " . join(", ", @{$tarr}) if scalar(@{$tarr});

            SDM::Archive::push_metadata_value($tsv_struct, 'dc.description[ru]', $nomkp . " " . join(". ", @{$desc}));

            if ($o->{'dump'}) {
                print Data::Dumper::Dumper($tsv_struct);
            }

            $doc_struct->{'by_storage_group'}->{'1'}->{$row->{'ID_BAS'}} = {
                'tsv_struct' => $tsv_struct,
                };
        }
    }

    return $doc_struct;
}

sub tsv_read_and_validate {
    my ($input_file, $o) = @_;

    # cache
    if (defined($SDM::Archive::runtime->{'csv_struct'})) {
        return $SDM::Archive::runtime->{'csv_struct'};
    }

    $o = {} unless $o;

    my $doc_struct = {
        'array' => [],
        'by_line_number' => {},
        'by_storage_group' => {},
        'funds' => {},
        'storage_items_by_fund_number' => {},
        'title_line' => {},
        'total_input_lines' => 0,
        
        # scanned dir -> array of storage_struct items
        'storage_items_by_scanned_dir' => {},
 
        # html -> array of storage_struct items
        'storage_items_by_ocr_html' => {},

        # html -> array of storage_struct items
        'storage_items_by_ocr_pdf' => {},
        };

    # read xls output and populate $list
    my $list = [];
    my $fh;
    open($fh, "<" . $input_file) || Carp::confess("Can't open [$input_file] for reading");
    binmode($fh, ':encoding(UTF-8)');
    while (my $l = <$fh>) {
        push @{$list}, $l;
    }
    close($fh);

    TSV_LINE: foreach my $line (@{$list}) {
        $doc_struct->{'total_input_lines'}++;

        if ($o->{'input-line'}) {
            next TSV_LINE if $doc_struct->{'total_input_lines'} ne $o->{'input-line'};
        }

        my $line_struct = {
            #'orig_line' => $line,
            'orig_field_values_array' => [split("\t", $line, -1)],
            'by_field_name' => {},
            'orig_line_number' => $doc_struct->{'total_input_lines'},
            };

        if (scalar(@{$line_struct->{'orig_field_values_array'}}) != scalar(@{$data_desc_struct->{'input_tsv_fields'}}) ) {
            Carp::confess("Invalid file format: expected [" . scalar(@{$data_desc_struct->{'input_tsv_fields'}}) .
                "] fields, got [" . scalar(@{$line_struct->{'orig_field_values_array'}}) . "] fields at the line " .
                $doc_struct->{'total_input_lines'});
        }

        my $i = 0;
        foreach my $fvalue (@{$line_struct->{'orig_field_values_array'}}) {
            # generic input text filtering
            my $nvalue = $fvalue;

            # remove surrounding quotes
            if ($nvalue && substr($nvalue, 0, 1) eq '"' &&
                substr($nvalue, length($nvalue) - 1, 1) eq '"') {
                $nvalue = substr($nvalue, 1, length($nvalue) - 2);
            }

            # remove heading and trailing whitespace
            $nvalue = trim($nvalue);

            # replace all repeated space with one space symbol
            while ($nvalue =~ /\s\s/) {
                $nvalue =~ s/\s\s/ /gs;
            }

            # push dangling commas and dots to the text
            $nvalue =~ s/\s\,(\s|$)/\,$1/g;
            $nvalue =~ s/\s\.(\s|$)/\.$1/g;
            $nvalue =~ s/\s\;(\s|$)/\;$1/g;

            $nvalue =~ s/""/"/g;

            $line_struct->{'by_field_name'}->{$data_desc_struct->{'input_tsv_fields'}->[$i]} = $nvalue;
            $i++;
        }

        if ($o->{'dump'}) {
            print Data::Dumper::Dumper($line_struct);
            next TSV_LINE;
        }

        # skip title
        if ($line_struct->{'by_field_name'}->{'date_of_status'} eq 'date of status') {
            if ($doc_struct->{'total_input_lines'} ne 1) {
                Carp::confess("Unexpected title line on the line number [$doc_struct->{'total_input_lines'}]");
            }

            $doc_struct->{'title_line'} = $line_struct;
            next TSV_LINE;
        }

        push @{$doc_struct->{'array'}}, $line_struct;
        $doc_struct->{'by_line_number'}->{$doc_struct->{'total_input_lines'}} = $line_struct;

        my $st_gr_id;
        my $fund_number;
        if ($line_struct->{'by_field_name'}->{'of_number'}) {
            $fund_number = $line_struct->{'by_field_name'}->{'of_number'};
            
            $doc_struct->{'funds'}->{$fund_number} = {}
                unless $doc_struct->{'funds'}->{$fund_number};
            
            if ($doc_struct->{'funds'}->{$fund_number}->{'type'} &&
                $doc_struct->{'funds'}->{$fund_number}->{'type'} ne "of") {
                Carp::confess("Data integrity error: fund [$fund_number] is referenced as [of] and as [$doc_struct->{'funds'}->{$fund_number}->{'type'}]");
            }

            $doc_struct->{'funds'}->{$fund_number}->{'type'} = "of";

            $st_gr_id = $data_desc_struct->{'storage_groups_by_fund_number'}->{$fund_number};
        } elsif ($line_struct->{'by_field_name'}->{'nvf_number'}) {
            $fund_number = $line_struct->{'by_field_name'}->{'nvf_number'};

            $doc_struct->{'funds'}->{$fund_number} = {}
                unless $doc_struct->{'funds'}->{$fund_number};

            if ($doc_struct->{'funds'}->{$fund_number}->{'type'} &&
                $doc_struct->{'funds'}->{$fund_number}->{'type'} ne "nvf") {
                Carp::confess("Data integrity error: fund [$fund_number] is referenced as [nvf] and as [$doc_struct->{'funds'}->{$fund_number}->{'type'}]");
            }

            $doc_struct->{'funds'}->{$fund_number}->{'type'} = "nvf";

            $st_gr_id = $data_desc_struct->{'storage_groups_by_fund_number'}->{$fund_number};
        } elsif ($line_struct->{'by_field_name'}->{'storage_number'} eq '796') {
            $st_gr_id = $data_desc_struct->{'storage_groups_by_name'}->{'Novikova'}->{'id'};
        } else {
            print Data::Dumper::Dumper($line_struct);
            Carp::confess("of_number and nvf_number are undefined for the line [$doc_struct->{'total_input_lines'}]");
        }

        if (!$st_gr_id) {
            print Data::Dumper::Dumper($line_struct);
            Carp::confess("Unable to find storage group for the line [$doc_struct->{'total_input_lines'}]");
        } else {
            Carp::confess("Invalid storage group id [$st_gr_id]")
                unless defined($data_desc_struct->{'AE'}->{'storage_groups'}->{$st_gr_id});

            $doc_struct->{'by_storage_group'}->{$st_gr_id} = {}
                unless $doc_struct->{'by_storage_group'}->{$st_gr_id};
        }

        my $st_id;
        if ($data_desc_struct->{'AE'}->{'storage_groups'}->{$st_gr_id}->{'name'} eq 'Novikova') {
            $st_id = $line_struct->{'by_field_name'}->{'storage_number'};
        } else {
            $st_id = $line_struct->{'by_field_name'}->{'number_suffix'};
        }
        if (!$st_id) {
            print Data::Dumper::Dumper($line_struct);
            Carp::confess("Unable to detect storage_number for line [$doc_struct->{'total_input_lines'}]");
        }

        my $storage_struct = $doc_struct->{'by_storage_group'}->{$st_gr_id}->{$st_id} // {'documents' => []};
        push @{$storage_struct->{'documents'}}, $line_struct;
        $doc_struct->{'by_storage_group'}->{$st_gr_id}->{$st_id} = $storage_struct;
    
        if ($fund_number) {
            $doc_struct->{'storage_items_by_fund_number'}->{$fund_number} = {}
                unless $doc_struct->{'storage_items_by_fund_number'}->{$fund_number};
            $doc_struct->{'storage_items_by_fund_number'}->{$fund_number}->{$st_id} = $storage_struct;
        }
    }

    my $scanned_dirs = read_scanned_docs();
    my $html_files = read_ocr_html_docs();
    my $pdf_files = read_ocr_pdf_docs();
    my $r2_struct = read_docbook_sources();

    my $today_yyyy_mm_dd = date_from_unixtime(time());

    foreach my $st_gr_id (keys %{$doc_struct->{'by_storage_group'}}) {
        foreach my $storage_number (sort {$a <=> $b} keys %{$doc_struct->{'by_storage_group'}->{$st_gr_id}}) {
            my $storage_struct = $doc_struct->{'by_storage_group'}->{$st_gr_id}->{$storage_number};

            $storage_struct->{'scanned_document_directories'} = [];
            $storage_struct->{'scanned_document_directories_h'} = {};
            $storage_struct->{'ocr_html_document_directories'} = [];
            $storage_struct->{'ocr_html_document_directories_h'} = {};
            $storage_struct->{'ocr_pdf_document_directories'} = [];
            $storage_struct->{'ocr_pdf_document_directories_h'} = {};
            $storage_struct->{'docbook_files_dates'} = [];
            $storage_struct->{'docbook_files_dates_h'} = {};

            # for given storage item checks different combinations
            # of possible scanned files, ocr documents, etc
            my $try_external_resource = sub {
                my ($opts) = @_;
                $opts = {} unless $opts;

                my $resource_struct;
                my $resource_tmp_name;
                my $resource_perm_name;

                if (safe_string($opts->{'resource'}) eq 'scan') {
                    $resource_struct = $scanned_dirs->{'scanned_docs'};
                    $resource_tmp_name = 'scanned_document_directories';
                    $resource_perm_name = 'storage_items_by_scanned_dir';
                }
                elsif (safe_string($opts->{'resource'}) eq 'html') {
                    $resource_struct = $html_files->{'ocr_html_files'};
                    $resource_tmp_name = 'ocr_html_document_directories';
                    $resource_perm_name = 'storage_items_by_ocr_html';
                }
                elsif (safe_string($opts->{'resource'}) eq 'pdf') {
                    $resource_struct = $pdf_files->{'ocr_pdf_files'};
                    $resource_tmp_name = 'ocr_pdf_document_directories';
                    $resource_perm_name = 'storage_items_by_ocr_pdf';
                }
                elsif (safe_string($opts->{'resource'}) eq 'docbook') {
                    $resource_struct = $r2_struct->{'docbook_files'};
                    $resource_tmp_name = 'docbook_files_dates';
                    $resource_perm_name = 'storage_items_by_docbook';
                }
                else {
                    Carp::confess("Programmer error: resource type must be one of: scan, html, pdf, docbook");
                }

                my $possible_resource_names = [];
                if (safe_string($opts->{'prefix'}) eq 'eh') {
                    Carp::confess("[n] is the required parameter")
                        unless defined($opts->{'n'});

                    push (@{$possible_resource_names}, "eh-" . sprintf("%04d", $opts->{'n'}));
                } elsif (safe_string($opts->{'prefix'}) eq 'of' ||
                    safe_string($opts->{'prefix'}) eq 'nvf') {

                    Carp::confess("Programmer error: [n] is mandatory for of/nvf mode")
                        unless defined($opts->{'n'});

                    if ($opts->{'n'} =~ /^\d+$/) {
                        push (@{$possible_resource_names}, $opts->{'prefix'} . "-" . $opts->{'n'});
                        push (@{$possible_resource_names}, $opts->{'prefix'} . "-" . sprintf("%04d", $opts->{'n'}));
                    } else {
                        push (@{$possible_resource_names}, $opts->{'prefix'} . "-" . $opts->{'n'});
                    }

                    if ($opts->{'n2'}) {
                        my $new_resources = [];
                        foreach my $r (@{$possible_resource_names}) {
                            if ($opts->{'n2'} =~ /^\d+$/) {
                                push @{$new_resources}, $r . "-" . sprintf("%04d", $opts->{'n2'});
                                push @{$new_resources}, $r . "-" . $opts->{'n2'};
                            } else {
                                push @{$new_resources}, $r . "-" . $opts->{'n2'};
                            }
                        }
                        $possible_resource_names = $new_resources;
                    }

                    my $new_resources2 = [];
                    foreach my $r (@{$possible_resource_names}) {
                        my $tmp_r = $r;
                        # of-10141-193;478 is the name of the item in csv
                        # of-10141-193_478 is the name of the corresponding html file
                        if ($tmp_r =~ /;/) {
                            $tmp_r =~ s/;/_/;
                            push (@{$new_resources2}, $tmp_r);
                        }
                        push (@{$new_resources2}, $r);
                    }
                    $possible_resource_names = $new_resources2;
                } elsif ($opts->{'resource_name'}) {
                    push (@{$possible_resource_names}, $opts->{'resource_name'});
                } else {
                    Carp::confess("Programmer error: prefix must be one of (eh, of, nvf), got [" .
                        safe_string($opts->{'prefix'}) . "]; storage_struct: " . Data::Dumper::Dumper($storage_struct));
                }

                foreach my $resource_name (@{$possible_resource_names}) {
                    next unless defined($resource_name) && $resource_name ne "";
                
                    # check that document exists on the disk
                    if (!scalar(@{$resource_struct->{'array'}}) ||
                        scalar(@{$resource_struct->{'array'}}) &&
                        !defined($resource_struct->{'hash'}->{$resource_name})) {
                        
                        next;
                    }

                    # do not add documents more than once
                    if (defined($storage_struct->{$resource_tmp_name . '_h'}->{$resource_name})) {
                        next;
                    }

                    $storage_struct->{$resource_tmp_name . '_h'}->{$resource_name} = $resource_struct->{'hash'}->{$resource_name};
                    push @{$storage_struct->{$resource_tmp_name}}, $resource_name;

                    $doc_struct->{$resource_perm_name}->{$resource_name} = []
                        unless defined($doc_struct->{$resource_perm_name}->{$resource_name});
                    push @{$doc_struct->{$resource_perm_name}->{$resource_name}}, $storage_struct;
                }
            };

            # always try eh-XXXX
            if ($data_desc_struct->{'AE'}->{'storage_groups'}->{$st_gr_id}->{'name'} eq 'Novikova') {
                $try_external_resource->({ 'resource' => 'scan', 'prefix' => 'eh', 'n' => $storage_number, });
            }

            my $predefined_storage_struct;
            if (defined($data_desc_struct->{'AE'}->{'storage_groups'}->{$st_gr_id}->{'storage_items'}) &&
                defined($data_desc_struct->{'AE'}->{'storage_groups'}->{$st_gr_id}->{'storage_items'}->{$storage_number})) {
                $predefined_storage_struct = $data_desc_struct->{'AE'}->{'storage_groups'}->{$st_gr_id}->{'storage_items'}->{$storage_number};                
            }

            my $tsv_struct = SDM::Archive::tsv_struct_init({
                'dc.subject[en]' => 'Museology',
                'dc.subject[ru]' => 'Музейное дело',
                'sdm-archive.date.cataloged' => $today_yyyy_mm_dd,
                'sdm-archive.misc.inventoryGroup' => $data_desc_struct->{'AE'}->{'storage_groups'}->{$st_gr_id}->{'name'},
                'sdm-archive.misc.storageItem' => $storage_number,
                });

            if ($predefined_storage_struct) {
                my $extracted_author;
                if ($predefined_storage_struct =~ /^(.+), переписка$/) {
                    $extracted_author = $1;
                
                    my $doc_authors1 = SDM::Archive::find_author($extracted_author);
                    foreach my $author (@{$doc_authors1}) {
                        SDM::Archive::push_metadata_value($tsv_struct, 'dc.contributor.author[' . $author->{'lang'} . ']', $author->{'name'});
                        SDM::Archive::push_metadata_value($tsv_struct, 'dc.creator[' . $author->{'lang'} . ']', $author->{'name'});
                    }
                }
                SDM::Archive::push_metadata_value($tsv_struct, 'dc.title[ru]', $predefined_storage_struct);
            }

            # - detect and store storage paths here against $data_desc_struct->{'external_archive_storage_base'}
            # - check "scanned" status (should be identical for all the documents in the storage item)
            STORAGE_PLACE_ITEMS: foreach my $item (@{$storage_struct->{'documents'}}) {

                if (safe_string($item->{'by_field_name'}->{'scanned_doc_id'}) eq '') {
                    Carp::confess("Input TSV invalid format: scanned_doc_id is empty for item " . Data::Dumper::Dumper($item));
                }

                my $title_struct = SDM::Archive::extract_authors($item->{'by_field_name'}->{'doc_name'}, {
                    'default_author' => {"name" => "Котс, Александр Федорович", "lang" => "ru"}, {"name" => "Kohts (Coates), Alexander Erich", "lang" => "en"},
                    'archive' => 'afk',
                    });
                foreach my $author (@{$title_struct->{'extracted_struct'}}) {
                    SDM::Archive::push_metadata_value($tsv_struct, 'dc.contributor.author[' . $author->{'lang'} . ']', $author->{'name'});
                    SDM::Archive::push_metadata_value($tsv_struct, 'dc.creator[' . $author->{'lang'} . ']', $author->{'name'});
                }

                my $meta = extract_meta_data($title_struct->{'trimmed_input'});
                Carp::confess("Unable to determine document type: " . Data::Dumper::Dumper($storage_struct))
                    if $item->{'by_field_name'}->{'doc_type'} && $meta->{'doc_type'};
                Carp::confess("Unable to determine document description: " . Data::Dumper::Dumper($storage_struct))
                    if $item->{'by_field_name'}->{'doc_desc'} && $meta->{'doc_date'};
                Carp::confess("Unable to determine document date: " . Data::Dumper::Dumper($storage_struct))
                    if $item->{'by_field_name'}->{'doc_date'} && $meta->{'doc_desc'};

                my $doc_type = $meta->{'doc_type'} ? $meta->{'doc_type'}->{'value'} : $item->{'by_field_name'}->{'doc_type'};
                my $doc_date = $meta->{'doc_date'} ? $meta->{'doc_date'}->{'value'} : $item->{'by_field_name'}->{'doc_date'};
                my $doc_desc = $meta->{'doc_desc'} ? $meta->{'doc_desc'}->{'value'} : $item->{'by_field_name'}->{'doc_desc'};

                if (!defined($predefined_storage_struct)) {
                    SDM::Archive::push_metadata_value($tsv_struct, 'dc.title[ru]', $meta->{'trimmed_input'});
                }

                $doc_type = SDM::Archive::push_metadata_value($tsv_struct, 'sdm-archive.misc.document-type', $doc_type);
                $doc_desc = SDM::Archive::push_metadata_value($tsv_struct, 'sdm-archive.misc.notes', $doc_desc);

                $doc_date = SDM::Archive::push_metadata_value($tsv_struct, 'dc.date.created', $doc_date);

                SDM::Archive::push_metadata_value($tsv_struct, 'dc.identifier.other[ru]', storage_id_csv_to_dspace({
                    'storage-group-id' => $st_gr_id,
                    'storage-item-id' => $storage_number,
                    'language' => 'ru',
                    }));
                SDM::Archive::push_metadata_value($tsv_struct, 'dc.identifier.other[en]', storage_id_csv_to_dspace({
                    'storage-group-id' => $st_gr_id,
                    'storage-item-id' => $storage_number,
                    'language' => 'en',
                    }));

                $item->{'by_field_name'}->{'doc_property_full'} =
                    SDM::Archive::push_metadata_value($tsv_struct, 'sdm-archive.misc.completeness', $item->{'by_field_name'}->{'doc_property_full'});
                $item->{'by_field_name'}->{'doc_property_genuine'} = 
                    SDM::Archive::push_metadata_value($tsv_struct, 'sdm-archive.misc.authenticity', $item->{'by_field_name'}->{'doc_property_genuine'});
                $item->{'by_field_name'}->{'archive_date'} =
                    SDM::Archive::push_metadata_value($tsv_struct, 'sdm-archive.misc.archive-date', $item->{'by_field_name'}->{'archive_date'});

                if ($item->{'by_field_name'}->{'classification_code'} &&
                    defined($data_desc_struct->{'AE'}->{'storage_groups'}->{$st_gr_id}->{'classification_codes'})
                    ) {

                    foreach my $itcc (split("/", $item->{'by_field_name'}->{'classification_code'})) {
                        my $found_cc_group;
                        my $cc;

                        $cc = SDM::Archive::match_classification_group_by_code($itcc);
                        if ($cc) {
                            SDM::Archive::push_metadata_value($tsv_struct, 'sdm-archive.misc.classification-group',
                                $data_desc_struct->{'AE'}->{'storage_groups'}->{$st_gr_id}->{'classification_codes'}->{$cc});
                            SDM::Archive::push_metadata_value($tsv_struct, 'sdm-archive.misc.classification-code',
                                $cc);
                            $found_cc_group = 1;
                        }

                        if (!$found_cc_group && substr($itcc, length($itcc) - 1) !~ /[0-9]/) {
                            $itcc = substr($itcc, 0, length($itcc) - 1);

                            $cc = SDM::Archive::match_classification_group_by_code($itcc);
                            if ($cc) {
                               SDM::Archive::push_metadata_value($tsv_struct, 'sdm-archive.misc.classification-group',
                                    $data_desc_struct->{'AE'}->{'storage_groups'}->{$st_gr_id}->{'classification_codes'}->{$cc});
                                SDM::Archive::push_metadata_value($tsv_struct, 'sdm-archive.misc.classification-code',
                                    $cc);
                                $found_cc_group = 1;
                            }
                        }

                        if (!$found_cc_group) {
                            Carp::confess("Can't find classification code group for [$item->{'by_field_name'}->{'classification_code'}], item: " .
                                Data::Dumper::Dumper($storage_struct));
                        }
                    }
                }

                # prepare 'dc.description[ru]' value
                my $item_desc = "";
                if ($item->{'by_field_name'}->{'of_number'}) {
                    SDM::Archive::push_metadata_value($tsv_struct, 'sdm-archive.misc.fond', "ОФ-" . $item->{'by_field_name'}->{'of_number'});

                    $item_desc .= "ОФ-" . $item->{'by_field_name'}->{'of_number'} .
                        ($item->{'by_field_name'}->{'number_suffix'} ?
                            "/" . $item->{'by_field_name'}->{'number_suffix'}
                            : "");

                    $try_external_resource->({
                        'resource' => 'scan',
                        'prefix' => 'of',
                        'n' => $item->{'by_field_name'}->{'of_number'},
                        'n2' => $item->{'by_field_name'}->{'number_suffix'},
                        });
                    $try_external_resource->({
                        'resource' => 'html',
                        'prefix' => 'of',
                        'n' => $item->{'by_field_name'}->{'of_number'},
                        'n2' => $item->{'by_field_name'}->{'number_suffix'},
                        });
                    $try_external_resource->({
                        'resource' => 'pdf',
                        'prefix' => 'of',
                        'n' => $item->{'by_field_name'}->{'of_number'},
                        'n2' => $item->{'by_field_name'}->{'number_suffix'},
                        });
                    $try_external_resource->({
                        'resource' => 'docbook',
                        'prefix' => 'of',
                        'n' => $item->{'by_field_name'}->{'of_number'},
                        'n2' => $item->{'by_field_name'}->{'number_suffix'},
                        });
                }
                else {
                    SDM::Archive::push_metadata_value($tsv_struct, 'sdm-archive.misc.fond', "НВФ-" . $item->{'by_field_name'}->{'nvf_number'});

                    $item_desc .= "НВФ-" . $item->{'by_field_name'}->{'nvf_number'} .
                        ($item->{'by_field_name'}->{'number_suffix'} ?
                            "/" . $item->{'by_field_name'}->{'number_suffix'}
                            : "");
                    $try_external_resource->({
                        'resource' => 'scan',
                        'prefix' => 'nvf',
                        'n' => $item->{'by_field_name'}->{'nvf_number'},
                        'n2' => $item->{'by_field_name'}->{'number_suffix'},
                        });
                    $try_external_resource->({
                        'resource' => 'html',
                        'prefix' => 'nvf',
                        'n' => $item->{'by_field_name'}->{'nvf_number'},
                        'n2' => $item->{'by_field_name'}->{'number_suffix'},
                        });
                    $try_external_resource->({
                        'resource' => 'pdf',
                        'prefix' => 'nvf',
                        'n' => $item->{'by_field_name'}->{'nvf_number'},
                        'n2' => $item->{'by_field_name'}->{'number_suffix'},
                        });
                    $try_external_resource->({
                        'resource' => 'docbook',
                        'prefix' => 'nvf',
                        'n' => $item->{'by_field_name'}->{'nvf_number'},
                        'n2' => $item->{'by_field_name'}->{'number_suffix'},
                        });
                }

                my $desc_elements = [];
                my $push_desc_el = sub {
                    my ($str) = @_;
                    push (@{$desc_elements}, $str . ($str =~ /\.$/ ? "" : "."));
                };

                $push_desc_el->($meta->{'trimmed_input'});
                if ($doc_date) {
                    $push_desc_el->("Время создания: " . $doc_date);
                }
                if ($item->{'by_field_name'}->{'doc_property_full'}) {
                    $push_desc_el->("Полнота: " . $item->{'by_field_name'}->{'doc_property_full'});
                }
                if ($item->{'by_field_name'}->{'doc_property_genuine'}) {
                    $push_desc_el->("Подлинность: " . $item->{'by_field_name'}->{'doc_property_genuine'});
                }
                if ($doc_type) {
                    $push_desc_el->("Способ воспроизведения: " . $doc_type);
                }
                if ($doc_desc) {
                    $push_desc_el->("Примечания: " . $doc_desc);
                }
                $item_desc .= " " . join (" ", @{$desc_elements});
                SDM::Archive::push_metadata_value($tsv_struct, 'dc.description[ru]', $item_desc);

                $try_external_resource->({
                    'resource' => 'scan',
                    'resource_name' => $item->{'by_field_name'}->{'scanned_doc_id'},
                    });
            }

            foreach my $d (keys %{$storage_struct->{'scanned_document_directories_h'}}) {
                foreach my $d_day (@{$storage_struct->{'scanned_document_directories_h'}->{$d}}) {
                    SDM::Archive::push_metadata_value($tsv_struct, 'sdm-archive.date.digitized', $d_day);
                }
            }
            foreach my $d (keys %{$storage_struct->{'docbook_files_dates_h'}}) {
                SDM::Archive::push_metadata_value($tsv_struct, 'sdm-archive.date.textExtracted', $storage_struct->{'docbook_files_dates_h'}->{$d});
            }

            $storage_struct->{'tsv_struct'} = $tsv_struct;
            $storage_struct->{'storage-group-id'} = $st_gr_id;
            $storage_struct->{'storage-item-id'} = $storage_number;
        }
    }

    # check scanned directories which are associated with several DSpace (storage) items
    foreach my $dir (keys %{$doc_struct->{'storage_items_by_scanned_dir'}}) {
        if (scalar(@{$doc_struct->{'storage_items_by_scanned_dir'}->{$dir}}) > 1) {
            if (grep {$_ eq $dir} @{$data_desc_struct->{'known_scanned_documents_included_into_several_storage_items'}}) {
                next;
            }

            if (!defined($o->{'ignore-duplicate-fund-id'})) {
                Carp::confess("Scanned directory [$dir] matches several storage items: [" .
                    join(",", map {$_->{'storage-group-id'} . "/" . $_->{'storage-item-id'}}
                        @{$doc_struct->{'storage_items_by_scanned_dir'}->{$dir}}) .
                    "]; maybe use --ignore-duplicate-fund-id?");
            }
        }
    }

    # check that all the scanned dirs were matched with some storage item,
    # except for some special documents
    foreach my $sd (@{$scanned_dirs->{'scanned_docs'}->{'array'}}) {
        if (grep {$_ eq $sd} @{$data_desc_struct->{'scanned_documents_without_id'}}) {
            next;
        }

        if (!defined($doc_struct->{'storage_items_by_scanned_dir'}->{$sd})) {
            Carp::confess("Scanned directory [$sd] (external_archive_storage_base in config file) didn't match any storage item");
        }
    }

    # check that one html file matches not more than 1 storage item
    foreach my $html (keys %{$doc_struct->{'storage_items_by_ocr_html'}}) {
        if (scalar(@{$doc_struct->{'storage_items_by_ocr_html'}->{$html}}) > 1) {
            Carp::confess("HTML file [$html] matches several storage items: [" .
                join(",", map {$_->{'storage-group-id'} . "/" . $_->{'storage-item-id'}}
                    @{$doc_struct->{'storage_items_by_ocr_html'}->{$html}}) .
                "]");
        }
    }
    # check that one pdf file matches not more than 1 storage item
    foreach my $pdf (keys %{$doc_struct->{'storage_items_by_ocr_pdf'}}) {
        if (scalar(@{$doc_struct->{'storage_items_by_ocr_pdf'}->{$pdf}}) > 1) {
            Carp::confess("PDF file [$pdf] matches several storage items: [" .
                join(",", map {$_->{'storage-group-id'} . "/" . $_->{'storage-item-id'}}
                    @{$doc_struct->{'storage_items_by_ocr_pdf'}->{$pdf}}) .
                "]");
        }
    }

    # - check that there are no unmatched html files
    foreach my $html (@{$html_files->{'ocr_html_files'}->{'array'}}) {
        if (!defined($doc_struct->{'storage_items_by_ocr_html'}->{$html})) {
            Carp::confess("HTML file [$html] didn't match any storage item");
        }
    }
    # - check that there are no unmatched pdf files
    foreach my $pdf (@{$pdf_files->{'ocr_pdf_files'}->{'array'}}) {
        if (!defined($doc_struct->{'storage_items_by_ocr_pdf'}->{$pdf})) {
            Carp::confess("PDF file [$pdf] didn't match any storage item");
        }
    }

    $SDM::Archive::runtime->{'csv_struct'} = $doc_struct;
    return $SDM::Archive::runtime->{'csv_struct'};
}

# outputs tsv record for ADDITION into DSpace (with plus sign
# as the DSpace id of the item)
#
# expects hashref
#   - with the names of fields of the output record as the keys of the hash
#   - and the values of the output record as the values of the hash
#   - all the hash references are ignored (see _helper struct created by
#     tsv_struct_push_metadata_value function)
#
sub tsv_output_record {
    my ($tsv_record, $o) = @_;
    $o = {} unless $o;

    $o->{'mode'} = 'values' unless $o->{'mode'};

    my $out_array = [];

    my $clean_tsv_record = {};
    foreach my $k (keys %{$tsv_record}) {
        # as of Nov 2017 skips only _help struct
        next if ref($tsv_record->{$k}) eq 'HASH';

        $clean_tsv_record->{$k} = $tsv_record->{$k};
    }

    if ($o->{'mode'} eq 'labels') {
        # id must be the _first_ column in tsv:
        # https://github.com/DSpace/DSpace/blob/master/dspace-api/src/main/java/org/dspace/app/bulkedit/DSpaceCSV.java#L522
        my $labels = ["id", sort(keys %{$clean_tsv_record})];
    
        $out_array = [];
        foreach my $v (@{$labels}) {
            $v =~ s/"/""/g;
            push @{$out_array}, '"' . $v . '"';
        }
    } elsif ($o->{'mode'} eq 'values') {
        $out_array = ["+"];
        foreach my $field_name (sort keys %{$clean_tsv_record}) {
            my $field_value = $clean_tsv_record->{$field_name};
            
            if (ref($field_value) eq 'ARRAY') {
                $field_value = join("||", @{$field_value});
            }

            $field_value =~ s/"/""/g;
            push @{$out_array}, '"' . $field_value . '"';
        }
    }
    
    print join(",", @{$out_array}) . "\n";
}

sub get_storage_item {
    my ($opts) = @_;
    
    $opts = {} unless $opts;

    foreach my $o (qw/external-tsv storage-group-id storage-item-id o/) {
        Carp::confess("get_storage_item: expects [$o]")
            unless defined($opts->{$o});
    }

    my $csv_struct = tsv_read_and_validate($opts->{'external-tsv'}, $opts->{'o'});

    return undef
        unless defined($csv_struct->{'by_storage_group'}->{$opts->{'storage-group-id'}});
    return undef
        unless defined($csv_struct->{'by_storage_group'}->{$opts->{'storage-group-id'}}->{$opts->{'storage-item-id'}});

    return $csv_struct->{'by_storage_group'}->{$opts->{'storage-group-id'}}->{$opts->{'storage-item-id'}};
}

sub storage_id_csv_to_dspace {
    my ($opts) = @_;
    $opts = {} unless $opts;
    foreach my $i (qw/storage-group-id storage-item-id language/) {
        Carp::confess("Programmer error: expected [$i]")
            unless defined($opts->{$i});
    }
    
    Carp::confess("Prefix not defined for language [$opts->{'language'}]")
        unless defined($data_desc_struct->{'dspace.identifier.other[' . $opts->{'language'} . ']-prefix'});
    Carp::confess("Nonexistent storage group id [$opts->{'storage-group-id'}]")
        unless defined($data_desc_struct->{'AE'}->{'storage_groups'}->{$opts->{'storage-group-id'}});

    my $dspace_id_string = $data_desc_struct->{'dspace.identifier.other[' . $opts->{'language'} . ']-prefix'} .
        ' ' . $opts->{'storage-item-id'} . ' (' .
        $data_desc_struct->{'AE'}->{'storage_groups'}->{$opts->{'storage-group-id'}}->{'name_readable_' . $opts->{'language'}} .
        ')';
    
    return $dspace_id_string;
}

sub storage_id_dspace_to_csv {
    my ($str, $language) = @_;
    
    $language = "en" unless $language;

    Carp::confess("Programmer error: need DSpace identifier.other value")
        unless $str;
    Carp::confess("Configuration error: language [$language] doesn't have associated dc.identifier prefx")
        unless defined($data_desc_struct->{'dspace.identifier.other[' . $language . ']-prefix'});

    my $st_item_id; 
    foreach my $st_gr_id (keys %{$data_desc_struct->{'AE'}->{'storage_groups'}}) {
        my $pfx = $data_desc_struct->{'dspace.identifier.other[' . $language . ']-prefix'};
        my $storage_group_txt = $data_desc_struct->{'AE'}->{'storage_groups'}->{$st_gr_id}->{'name_readable_' . $language};
        my $rx = qr/^${pfx}\s+(\d+)\s+\(${storage_group_txt}\)$/;

#        print $str . "\n" . $rx . "\n"; exit;

        if ($str =~ /$rx/) {
            return {
                'storage-group-id' => $st_gr_id,
                'storage-item-id' => $1,
                };
        }
    }

    return undef;
}

sub read_dspace_xml_schema {
    my ($o) = @_;
    Carp::confess("Programmer error: need file_name and schema_name")
        unless $o && $o->{'file_name'} && $o->{'schema_name'};
    
    Carp::confess("File [$o->{'file_name'}] must exist")
        unless -e $o->{'file_name'};

    my $item_schema_xml = XML::Simple::XMLin($o->{'file_name'});

    Carp::confess("Unknown schema layout in [$o->{'file_name'}]")
        unless
#            $item_schema_xml->{'schema'} &&
#            $item_schema_xml->{'schema'} eq $o->{'schema_name'} &&
            $item_schema_xml->{'dcvalue'} &&
            ref($item_schema_xml->{'dcvalue'}) eq 'ARRAY';
        
    if (!defined($item_schema_xml->{'schema'})) {
        $item_schema_xml->{'schema'} = $o->{'schema_name'};
    }

    return $item_schema_xml;
}

sub read_dspace_collection {
    my ($dir) = @_;

    my $dspace_exported_colletion = Yandex::Tools::read_dir($dir);
    my $invalid_directories = [grep {$_ !~ /^(item_)?\d+$/ || ! -d $dir . "/" . $_} @{$dspace_exported_colletion}];
    Carp::confess("--dspace-exported-collection should point to the directory containing DSpace collection in Simple Archive Format")
        if scalar(@{$dspace_exported_colletion}) == 0;
    Carp::confess("Unexpected items in DSpace export directory [$dir]: " . join(",", @{$invalid_directories}))
        if scalar(@{$invalid_directories});

    my $dspace_items = {};

    DSPACE_ITEM: foreach my $seq (sort {$a cmp $b} @{$dspace_exported_colletion}) {
        my $item_path = $o->{'dspace-exported-collection'} . "/" . $seq;
        my $item_files = Yandex::Tools::read_dir($item_path, {'output_type' => 'hashref'});
        
        foreach my $f (qw/dublin_core.xml contents/) {
            Carp::confess("Invalid DSpace Simple Archive Format layout in [$item_path], $f doesn't exist")
                unless defined($item_files->{$f});
        }

        my $item_schema_struct = read_dspace_xml_schema({
            'file_name' => $item_path . "/dublin_core.xml",
            'schema_name' => 'dc',
            });

        my $item_struct;
        DCVALUES: foreach my $dcvalue (@{$item_schema_struct->{'dcvalue'}}) {
            if ($dcvalue->{'element'} eq 'identifier' &&
                $dcvalue->{'qualifier'} eq 'other' &&
                $dcvalue->{'language'} eq 'en') {

                my $st_item = storage_id_dspace_to_csv($dcvalue->{'content'});
                if ($st_item) {
                    $dspace_items->{$st_item->{'storage-group-id'}} = {}
                        unless $dspace_items->{$st_item->{'storage-group-id'}};
                    $dspace_items->{$st_item->{'storage-group-id'}}->{$st_item->{'storage-item-id'}} = {
                        'item-path' => $item_path,
                        'item-path-contents' => $item_files,
                        'dublin_core.xml' => $item_schema_struct,
                        'storage-group-id' => $st_item->{'storage-group-id'},
                        'storage-item-id' => $st_item->{'storage-item-id'},
                        };

                    $item_struct = $dspace_items->{$st_item->{'storage-group-id'}}->{$st_item->{'storage-item-id'}};

                    last DCVALUES;
                }
            }
        }

        # not able to identify item directory as belonging
        # to the previously imported from csv; skip the item.
        next unless $item_struct;

        $item_struct->{'contents'} = read_file_scalar($item_path . "/contents");
        
        # SAFBuilder doesn't produce /handle
        if (-e $item_path . "/handle") {
            $item_struct->{'handle'} = trim(read_file_scalar($item_path . "/handle"), " \n");
        }
    }

    return $dspace_items;
}

sub prepare_docbook_makefile {
    my ($build_base, $full_docbook_path) = @_;

    my ($filename, $dirs) = File::Basename::fileparse($full_docbook_path);
    
    my $entity_name = $filename;
    $entity_name =~ s/\..+$//g;
    
    my $entities = {
        $entity_name => {'SYSTEM' => $full_docbook_path},
        };

    # one entity (document) references another one - this was justified
    # when I was preparing afk-works as a single document, but now when
    # the focus has changed from one "book" to a digitized archive
    # such documents should no longer exist.
    #
    # basically: add workaround for the documents digitized before 2014,
    # and don't create cross-referenced documents in the future
    #
    if ($entity_name eq 'of-10141-0112') {
        $entities->{'of-12497-0541'} = "";
    }

    my $dspace_html_docbook_template = qq{<?xml version="1.0" encoding="UTF-8"?>

<!DOCTYPE book PUBLIC "-//OASIS//DTD DocBook XML V4.4//EN"
  "/usr/share/xml/docbook/schema/dtd/4.4/docbookx.dtd" [
  <!ENTITY liniya "
<informaltable frame='none' pgwide='1'><tgroup cols='1' align='center' valign='top' colsep='0' rowsep='0'>
<colspec colname='c1'/><tbody><row><entry><para>&boxh;&boxh;&boxh;&boxh;&boxh;&boxh;&boxh;</para></entry></row></tbody>
</tgroup></informaltable>
 ">

  };
  
   foreach my $e_name (sort keys %{$entities}) {
      if (ref($entities->{$e_name})) {
          $dspace_html_docbook_template .= '<!ENTITY ' . $e_name . ' SYSTEM "' . $entities->{$e_name}->{'SYSTEM'} . '">' . "\n";
      } else {
          $dspace_html_docbook_template .= '<!ENTITY ' . $e_name . ' "' . $entities->{$e_name} . '">' . "\n";
      }
   }
   
   $dspace_html_docbook_template .= qq{
]>

<article id="} . $entity_name . qq{" lang="ru">
<articleinfo>
<author>
<firstname>Александр</firstname>
<othername>Федорович</othername>
<surname>Котс</surname>
</author>
</articleinfo>

&} . $entity_name . qq{;
</article>
    };

#    print $dspace_html_docbook_template . "\n";

    my $tmp_docbook_name = $build_base . "/$entity_name.docbook";
    write_file_scalar($tmp_docbook_name, $dspace_html_docbook_template);

    return $tmp_docbook_name;
}

SDM::Archive::prepare_config();
$data_desc_struct = $SDM::Archive::data_desc_struct;

if ($o->{'dump-config'}) {
    print Data::Dumper::Dumper($data_desc_struct);
    print Data::Dumper::Dumper($SDM::Archive::runtime);
    print Data::Dumper::Dumper($SDM::Archive::authors_canonical);
}
elsif ($o->{'data-split-by-tab'}) {
    my $line_number = 0;
    while (my $l = <STDIN>) {
        $line_number = $line_number + 1;
        my $fields = [split("\t", $l, -1)];
        my $i = 0;
        foreach my $f (@{$fields}) {
            $i = $i + 1;
            print $line_number . "." . $i . ": " . $f . "\n";
        }
    }    
}
elsif ($o->{'data-split-by-comma'}) {
    my $csv = Text::CSV->new();

    my $line_number = 0;
    while (my $l = <STDIN>) {
        $line_number = $line_number + 1;

        $csv->parse($l);

        my $fields = [$csv->fields()];
        
        my $i = 0;
        foreach my $f (@{$fields}) {
            $i = $i + 1;
            print $line_number . "." . $i . ": " . $f . "\n";
        }
        print "\n";
    }    
}
elsif ($o->{'descriptor-dump'}) {
    my $d = $o->{'descriptor-dump'} . "\n";
    $d = trim($d);

    if (!$d) {
        while (my $l = <STDIN>) {
            $d .= $l;
        }
    }

    my $ds = separated_list_to_struct($d);

    foreach my $f (@{$ds->{'array'}}) {
        print $ds->{'by_name1'}->{$f} . ": " . $f . "\n";
    }
}
elsif ($o->{'dump-csv-item'}) {
    Carp::confess("Need --external-tsv")
        unless $o->{'external-tsv'};

    my ($st_gr_id, $st_number) = split(" ", safe_string($o->{'dump-csv-item'}));
    Carp::confess("Need storage_group and storage_number (try --dump-csv-item '1 1')")
        unless $st_gr_id && $st_number;

    my $st_item = get_storage_item({
        'external-tsv' => $o->{'external-tsv'},
        'storage-group-id' => $st_gr_id,
        'storage-item-id' => $st_number,
        'o' => $o,
        });
  
    Carp::confess("Unable to find [$st_gr_id/$st_number] in csv")
        unless $st_item;

    if ($o->{'tsv-output'}) {
        tsv_output_record($st_item->{'tsv_struct'}, {'mode' => 'labels'});
        tsv_output_record($st_item->{'tsv_struct'});
    } else {
        print Data::Dumper::Dumper($st_item);
    }
}
elsif ($o->{'list-storage-items'}) {
    Carp::confess("Need --external-tsv")
        unless $o->{'external-tsv'};
  
    my $doc_struct = tsv_read_and_validate($o->{'external-tsv'}, $o);

    foreach my $st_gr_id (keys %{$doc_struct->{'by_storage_group'}}) {
        foreach my $storage_number (sort {$a <=> $b} keys %{$doc_struct->{'by_storage_group'}->{$st_gr_id}}) {
            my $storage_struct = $doc_struct->{'by_storage_group'}->{$st_gr_id}->{$storage_number};

            if ($o->{'titles'}) {
                print
                    "storage group (" . $data_desc_struct->{'AE'}->{'storage_groups'}->{$st_gr_id}->{'name_readable_en'} . ") " .
                    "storage item " . $storage_number . ": " . $storage_struct->{'tsv_struct'}->{'dc.title[ru]'} . "\n";
            } else {
                print
                    "storage group (" . $data_desc_struct->{'AE'}->{'storage_groups'}->{$st_gr_id}->{'name_readable_en'} . ") " .
                    "storage item " . $storage_number . ": " . scalar(@{$storage_struct->{'documents'}}) . " items\n";
            }
        }
    }
}
elsif ($o->{'dump-tsv-struct'}) {
    Carp::confess("Need --external-tsv")
        unless $o->{'external-tsv'};

    my $in_doc_struct = tsv_read_and_validate($o->{'external-tsv'}, $o);

    if ($o->{'debug'}) {
        if ($o->{'only-by-storage'}) {
            print Data::Dumper::Dumper($in_doc_struct->{'by_storage_group'});
        } else {
            print Data::Dumper::Dumper($in_doc_struct);
        }
    }

    print "total input lines: " . $in_doc_struct->{'total_input_lines'} . "\n";
    print "total data lines: " . scalar(@{$in_doc_struct->{'array'}}) . "\n";
    foreach my $st_gr_id (sort keys %{$in_doc_struct->{'by_storage_group'}}) {
        print
            "total items in storage group [$st_gr_id] (" .
            $data_desc_struct->{'AE'}->{'storage_groups'}->{$st_gr_id}->{'name_readable_en'} .
            "): " . scalar(keys %{$in_doc_struct->{'by_storage_group'}->{$st_gr_id}}) . "\n";
    }

    foreach my $fund_number (sort {$a <=> $b} keys %{$in_doc_struct->{'storage_items_by_fund_number'}}) {
        print uc($in_doc_struct->{'funds'}->{$fund_number}->{'type'}) . " " . $fund_number . ": " .
            scalar(keys %{$in_doc_struct->{'storage_items_by_fund_number'}->{$fund_number}}) . " storage items\n";
    }
}
elsif ($o->{'initial-import'}) {
#
# original data used for A.E. Kohts archive: data/kohts-initial-in.txt
# tsv file imported into dspace: data/kohts-initial-out.csv
#
    
    Carp::confess("Need either --external-tsv or --kamis-database")
        unless $o->{'external-tsv'} || $o->{'kamis-database'};

    Carp::confess("Need --target-collection-handle")
        unless $o->{'target-collection-handle'};
    my $target_collection_handle = $o->{'target-collection-handle'};

    my $in_doc_struct;
    if ($o->{'external-tsv'}) {
        $in_doc_struct = tsv_read_and_validate($o->{'external-tsv'}, $o);
    }
    else {
        $in_doc_struct = read_nn_archive_from_kamis($o->{'kamis-database'}, $o);
    }

    my $output_labels;
    foreach my $st_gr_id (sort keys %{$in_doc_struct->{'by_storage_group'}}) {
        foreach my $in_id (sort {$a <=> $b} keys %{$in_doc_struct->{'by_storage_group'}->{$st_gr_id}}) {
            # print $st_gr_id . ":" . $in_id . "\n";
            
            next unless defined($in_doc_struct->{'by_storage_group'}->{$st_gr_id}->{$in_id}->{'tsv_struct'});

            my $tsv_record = $in_doc_struct->{'by_storage_group'}->{$st_gr_id}->{$in_id}->{'tsv_struct'};
            $tsv_record->{'collection'} = $target_collection_handle;

            if (!$output_labels) {
                tsv_output_record($tsv_record, {'mode' => 'labels'});
                $output_labels = 1;
            }
            tsv_output_record($tsv_record);
        }
    }
}
elsif ($o->{'dump-scanned-docs'}) {
    my $resources = read_scanned_docs({'debug' => $o->{'debug'}});
    print Data::Dumper::Dumper($resources);
}
elsif ($o->{'dump-ocr-html-docs'}) {
    my $resources = read_ocr_html_docs();
    print Data::Dumper::Dumper($resources);
}
elsif ($o->{'dump-ocr-pdf-docs'}) {
    my $resources = read_ocr_pdf_docs();
    print Data::Dumper::Dumper($resources);
}
elsif ($o->{'dump-docbook-sources'}) {
    my $resources = read_docbook_sources();
    print Data::Dumper::Dumper($resources);
}
elsif ($o->{'dump-dspace-exported-collection'}) {
    Carp::confess("--dspace-exported-collection should point to the directory, got [" . safe_string($o->{'dspace-exported-collection'}) . "]")
        unless $o->{'dspace-exported-collection'} && -d $o->{'dspace-exported-collection'};

    my $dspace_collection = read_dspace_collection($o->{'dspace-exported-collection'});
    print Data::Dumper::Dumper($dspace_collection);
}
elsif ($o->{'dump-dspace-exported-item'}) {
    Carp::confess("--dspace-exported-collection should point to the directory, got [" . safe_string($o->{'dspace-exported-collection'}) . "]")
        unless $o->{'dspace-exported-collection'} && -d $o->{'dspace-exported-collection'};

    my ($st_gr_id, $st_it_id) = split(" ", safe_string($o->{'dump-dspace-exported-item'}));
    Carp::confess("Need storage_group and storage_number (try --dump-dspace-exported-item '1 1')")
        unless $st_gr_id && $st_it_id;

    my $dspace_collection = read_dspace_collection($o->{'dspace-exported-collection'});
    Carp::confess("Unable to find item in DSpace export")
        unless defined($dspace_collection->{$st_gr_id}) && defined($dspace_collection->{$st_gr_id}->{$st_it_id});

    print Data::Dumper::Dumper($dspace_collection->{$st_gr_id}->{$st_it_id});
}
elsif ($o->{'import-bitstream'}) {
    Carp::confess("Need --external-tsv")
        unless $o->{'external-tsv'};
    Carp::confess("--dspace-exported-collection should point to the directory, got [" . safe_string($o->{'dspace-exported-collection'}) . "]")
        unless $o->{'dspace-exported-collection'} && -d $o->{'dspace-exported-collection'};
    
    my ($st_gr_id, $st_it_id) = split(" ", safe_string($o->{'import-bitstream'}));
    Carp::confess("Need storage_group and storage_number (try --import-bitstream '1 1')")
        unless $st_gr_id && $st_it_id;

    my $st_item = get_storage_item({
        'external-tsv' => $o->{'external-tsv'},
        'storage-group-id' => $st_gr_id,
        'storage-item-id' => $st_it_id,
        'o' => $o,
        });
    
    Carp::confess("Unable to find item [$st_gr_id/$st_it_id] in csv")
        unless $st_item;

    my $dspace_collection = read_dspace_collection($o->{'dspace-exported-collection'});
    Carp::confess("Unable to find item in DSpace export")
        unless defined($dspace_collection->{$st_gr_id}) && defined($dspace_collection->{$st_gr_id}->{$st_it_id});

    my $dspace_collection_item = $dspace_collection->{$st_gr_id}->{$st_it_id};
    if ($dspace_collection_item->{'contents'} ne '' ) {
        Carp::confess("Unable to add bitstreams to the item which already has bitstreams (not implemented yet)");
    }

    my $updated_item = sync_dspace_item_from_external_storage({
        'external_storage_item' => $st_item,
        'dspace_collection_item' => $dspace_collection_item,
        'dry-run' => $o->{'dry-run'},
        });

    print "prepared DSpace item [$dspace_collection_item->{'item-path'}]\n";

    # print Data::Dumper::Dumper($dspace_collection_item);
    # print Data::Dumper::Dumper($st_item);
}
elsif ($o->{'import-bitstreams'}) {
    Carp::confess("Need --external-tsv")
        unless $o->{'external-tsv'};
    Carp::confess("--dspace-exported-collection should point to the directory, got [" . safe_string($o->{'dspace-exported-collection'}) . "]")
        unless $o->{'dspace-exported-collection'} && -d $o->{'dspace-exported-collection'};
    if ($o->{'limit'}) {
        if (!SDM::Archive::Utils::is_integer($o->{'limit'}, {'positive-only' => 1})) {
            Carp::confess("--limit N requires N to be positive integer");
        }
    }

    my $scanned_dirs = read_scanned_docs({'must_exist' => 1});
    my $html_files = read_ocr_html_docs({'must_exist' => 1});
    my $pdf_files = read_ocr_pdf_docs({'must_exist' => 1});
    my $r2_struct = read_docbook_sources({'must_exist' => 1});

    my $in_doc_struct = tsv_read_and_validate($o->{'external-tsv'}, $o);
    my $dspace_collection = read_dspace_collection($o->{'dspace-exported-collection'});

    my $updated_items = 0;

    DSPACE_COLLECTION: foreach my $st_gr_id (sort {$a <=> $b} keys %{$dspace_collection}) {

        Carp::confess("Can't find storage group [$st_gr_id] in external-csv [$o->{'external-tsv'}], something is very wrong")
            unless defined($in_doc_struct->{'by_storage_group'}->{$st_gr_id});
        
        DSPACE_ITEM: foreach my $st_it_id (sort {$a <=> $b} keys %{$dspace_collection->{$st_gr_id}}) {

            my $dspace_collection_item = $dspace_collection->{$st_gr_id}->{$st_it_id};

            # if there are bitstreams in the item, skip it
            if ($dspace_collection_item->{'contents'}) {
                #print "skipping [$st_gr_id/$st_it_id] which has already some bitstreams\n";
                next DSPACE_ITEM;
            }
            
            my $st_item = get_storage_item({
                'external-tsv' => $o->{'external-tsv'},
                'storage-group-id' => $st_gr_id,
                'storage-item-id' => $st_it_id,
                'o' => $o,
                });
            
            if (!defined($st_item)) {
                # silently skip the items which are in DSpace
                # but which we can't find in incoming tsv
                next DSPACE_ITEM;
            }
        
            my $updated_item = sync_dspace_item_from_external_storage({
                'external_storage_item' => $st_item,
                'dspace_collection_item' => $dspace_collection_item,
                'dry-run' => $o->{'dry-run'},
                });
            
            if ($updated_item) {
                $updated_items = $updated_items + 1;
                SDM::Archive::do_log("added [" . $updated_item . "] bitstreams to the item [$st_gr_id/$st_it_id], " .
                    "DSpace Archive [$dspace_collection_item->{'item-path'} " . (safe_string($dspace_collection_item->{'handle'})) . "]");

                if ($o->{'limit'} && $updated_items == $o->{'limit'}) {
                    last DSPACE_COLLECTION;
                }
            }    
        }
    }
}
elsif ($o->{'build-docbook-for-dspace'}) {
    Carp::confess("Need --docbook-filename")
        unless $o->{'docbook-filename'};
    
    my $full_docbook_path = $data_desc_struct->{'docbook_source_base'} . "/docbook/" . $o->{'docbook-filename'};
    Carp::confess("--docbook-filename points to nonexistent file (resolved to $full_docbook_path)")
        unless -e $full_docbook_path;

    my $docbook_id = $o->{'docbook-filename'};
    $docbook_id =~ s/\.docbook$//;

    my $build_base = "/tmp/build-docbook-for-dspace.$$";
    File::Path::make_path($build_base);

    my $tmp_docbook_name = prepare_docbook_makefile($build_base, $full_docbook_path);

    if ($o->{'no-xsltproc'}) {
        print "prepared docbook file [$tmp_docbook_name]\n";
        exit 0;
    }

    my $cmd = 'xsltproc --xinclude ' .
        '--stringparam base.dir ' . $data_desc_struct->{'docbook_dspace_html_out_base'} . "/ " .
        '--stringparam use.id.as.filename 1 ' .
        '--stringparam root.filename "" ' .
        $data_desc_struct->{'docbook_source_base'} . '/build/docbook-html-dspace.xsl ' .
        $tmp_docbook_name;
    my $r = IPC::Cmd::run_forked($cmd);
    Carp::confess("Error generating DSpace html file, cmd [$cmd]: " . Data::Dumper::Dumper($r))
        if $r->{'exit_code'} ne 0;

    if ($r->{'merged'} =~ /Writing\s+?(.+?)\sfor/s) {
        print "built: " . $1 . "\n";
    } else {
        Carp::confess("Unable to extract filename written by DocBook (protocol changed?) from: " . $r->{'merged'});
    }

    my $cmd2 = 'xsltproc -o ' . $tmp_docbook_name . '.fo ' .
        $data_desc_struct->{'docbook_source_base'} . '/build/docbook-fo.xsl ' .
        $tmp_docbook_name;
    my $r2 = IPC::Cmd::run_forked($cmd2);
    Carp::confess("Error generating DSpace FO file, cmd [$cmd2]: " . Data::Dumper::Dumper($r2))
        if $r2->{'exit_code'} ne 0;

    Carp::confess("FONTS directory [" . safe_string($data_desc_struct->{'docbook_fonts_base'}) . "] must contain: fop.xconf, fop-hyph.jar and fonts subdirectory with fonts")
        unless $data_desc_struct->{'docbook_fonts_base'} &&
            -d $data_desc_struct->{'docbook_fonts_base'} &&
            -e $data_desc_struct->{'docbook_fonts_base'} . "/fop.xconf" &&
            -e $data_desc_struct->{'docbook_fonts_base'} . "/fop-hyph.jar" &&
            -d $data_desc_struct->{'docbook_fonts_base'} . "/fonts";

    foreach my $l (qw/fop.xconf fop-hyph.jar fonts/) {
        symlink(
            $data_desc_struct->{'docbook_fonts_base'} . "/" . $l,
            $build_base . "/" . $l
            ) ||
            Carp::confess("Unable to symlink [" .
                $data_desc_struct->{'docbook_fonts_base'} . "/" . $l .
                "] to [" .
                $build_base . "/" . $l .
                "]: $!");
    }

    my $cmd3 =
        'cd ' . $build_base . ' && ' .
        'export FOP_HYPHENATION_PATH=' . $build_base . '/fop-hyph.jar && ' .
        'fop -c fop.xconf ' . $tmp_docbook_name . '.fo ' .
        ' -pdf ' . $data_desc_struct->{'docbook_dspace_pdf_out_base'} . "/" . $docbook_id . ".pdf";
    my $r3 = IPC::Cmd::run_forked($cmd3);
    Carp::confess("Error generating DSpace PDF file, cmd [$cmd3]: " . Data::Dumper::Dumper($r3))
        if $r3->{'exit_code'} ne 0;

    print "built: " . $data_desc_struct->{'docbook_dspace_pdf_out_base'} . "/" . $docbook_id . ".pdf" . "\n";

    File::Path::rmtree($build_base);

}
elsif ($o->{'validate-tsv'}) {
    Carp::confess("Need --external-tsv")
        unless $o->{'external-tsv'};

    my $in_doc_struct = tsv_read_and_validate($o->{'external-tsv'}, $o);
    print "$o->{'external-tsv'} seems to be ok\n";
}
elsif ($o->{'preprocess-book'}) {
    Carp::confess("Need --book-name")
        unless defined($o->{'book-name'});

    my $full_book_path = $ENV{'ARCHIVE_ROOT'} . "/books/" . $o->{'book-name'};
    Carp::confess("--book-name points to nonexistent directory (resolved to $full_book_path)")
        unless -e $full_book_path;

    my $filename_filter;
    if (defined($o->{'filename-filter'})) {
        $filename_filter = $o->{'filename-filter'};
    }

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
                if (waitpid($cpid, POSIX::WNOHANG) == -1) {
                    delete ($children->{$cpid});
                }
            }
            Time::HiRes::usleep(100_000);
        }
    };

    foreach my $stepnumber (sort keys %{$steps}) {
        my $step = $steps->{$stepnumber};  

        next unless $step->{'filename_stdout_tool'};
        
        my $tool_path = $ENV{'ARCHIVE_ROOT'} . "/tools/filters/" . $step->{'filename_stdout_tool'};
        if (! -x $tool_path) {
            Carp::confess("Invalid processing tool: $tool_path");
        }

        my $docbook_files = Yandex::Tools::read_dir($full_book_path . "/docbook", {'output_type' => 'hashref'});

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
                    print "updated: $docbook_file\n";
                }
                exit 0;
            } else {
                Carp::confess("unable to fork: $!");
            }
        }
    }

    $wait_free_resource->(0);
}
elsif ($o->{'validate-pagination'}) {
    Carp::confess("Need --docbook-filename")
        unless $o->{'docbook-filename'};
    
    my $full_docbook_path = $data_desc_struct->{'docbook_source_base'} . "/docbook/" . $o->{'docbook-filename'};
    Carp::confess("--docbook-filename points to nonexistent file (resolved to $full_docbook_path)")
        unless -e $full_docbook_path;

    my $pages = {};

    my $f = read_file_array($full_docbook_path);

    my $previous_page_number;
     
    my $i = 0;
    foreach my $l (@{$f}) {
        $i++;

        if ($l =~ /original_page" url="(.+?)"/) {
            my $page_number = $1;

            if ($pages->{$page_number}) {
                if ($o->{'autoincrement-duplicate-page-number'}) {
                    $page_number++;
                    $l =~ s/url=".+?"/url="$page_number"/;
                }
                else {
                    Carp::confess("Page [$page_number] defined twice (line $pages->{$page_number} and line $i)");
                }
            }
            if ($previous_page_number && $page_number < $previous_page_number) {
                Carp::confess("Page [$page_number] goes after [$previous_page_number]");
            }

            $pages->{$page_number} = $i;
            $previous_page_number = $page_number;
        }

        print $l . "\n";
    }
}
elsif ($o->{'create-kohtsnn-collection'}) {
    my $target_community = SDM::Archive::DSpace::get_community_by_name("Архив");
    if (!$target_community) {
        my $new_comm = SDM::Archive::DSpace::rest_call({
            'verb' => 'post',
            'action' => 'communities',
            'request' => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<community>
    <name>Архив</name>
    <copyrightText>Государственный Дарвиновский Музей</copyrightText>
    <introductoryText></introductoryText>
    <shortDescription></shortDescription>
    <sidebarText></sidebarText>
</community>
',
            'request_type' => 'xml',
            });

        $target_community = SDM::Archive::DSpace::get_community_by_name("Архив");
        if (!$target_community) {
            Carp::confess("Community [Архив] doesn't exist and unable to create");
        }
    }

    my $target_collection = SDM::Archive::DSpace::get_collection({
        'community_obj' => $target_community,
        'collection_name' => $data_desc_struct->{'NN'}->{'dspace-collection-name'},
        });
    if (!$target_collection) {
        my $new_comm = SDM::Archive::DSpace::rest_call({
            'verb' => 'post',
            'link' => $target_community->{'link'} . "/collections",
            'request' => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<collection>
  <name>' . $data_desc_struct->{'NN'}->{'dspace-collection-name'} . '</name>
  <type></type>
  <copyrightText></copyrightText>
  <introductoryText></introductoryText>
  <shortDescription></shortDescription>
  <sidebarText></sidebarText>
</collection>

',
            'request_type' => 'xml',
            });

        $target_collection = SDM::Archive::DSpace::get_collection({
            'community_obj' => $target_community,
            'collection_name' => $data_desc_struct->{'NN'}->{'dspace-collection-name'},
            });
        if (!$target_collection) {
            Carp::confess("Collection [' .
              $data_desc_struct->{'NN'}->{'dspace-collection-name'} .
              '] doesn't exist and unable to create");
        }
    }

    print "target collection:\n" . Data::Dumper::Dumper($target_collection);
}
elsif ($o->{'create-kohtsae-community-and-collection'}) {
    my $target_community = SDM::Archive::DSpace::get_community_by_name("Архив");
    if (!$target_community) {
        my $new_comm = SDM::Archive::DSpace::rest_call({
            'verb' => 'post',
            'action' => 'communities',
            'request' => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<community>
    <name>Архив</name>
    <copyrightText>Государственный Дарвиновский Музей</copyrightText>
    <introductoryText></introductoryText>
    <shortDescription></shortDescription>
    <sidebarText></sidebarText>
</community>
',
            'request_type' => 'xml',
            });

        $target_community = SDM::Archive::DSpace::get_community_by_name("Архив");
        if (!$target_community) {
            Carp::confess("Community [Архив] doesn't exist and unable to create");
        }
    }

    my $target_collection = SDM::Archive::DSpace::get_collection({
        'community_obj' => $target_community,
        'collection_name' => $data_desc_struct->{'AE'}->{'dspace-collection-name'},
        });
    if (!$target_collection) {
        my $new_comm = SDM::Archive::DSpace::rest_call({
            'verb' => 'post',
            'link' => $target_community->{'link'} . "/collections",
            'request' => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<collection>
  <name>' . $data_desc_struct->{'AE'}->{'dspace-collection-name'} . '</name>
  <type></type>
  <copyrightText></copyrightText>
  <introductoryText></introductoryText>
  <shortDescription></shortDescription>
  <sidebarText></sidebarText>
</collection>

',
            'request_type' => 'xml',
            });

        $target_collection = SDM::Archive::DSpace::get_collection({
            'community_obj' => $target_community,
            'collection_name' => $data_desc_struct->{'AE'}->{'dspace-collection-name'},
            });
        if (!$target_collection) {
            Carp::confess("Collection [" .
                $data_desc_struct->{'AE'}->{'dspace-collection-name'} .
                "] doesn't exist and unable to create");
        }
    }

    print "target collection:\n" . Data::Dumper::Dumper($target_collection);
}
elsif ($o->{'rest-add-bitstreams'}) {
    my $target_community = SDM::Archive::DSpace::get_community_by_name("Архив");
    my $target_collection = SDM::Archive::DSpace::get_collection({
        'community_obj' => $target_community,
        'collection_name' => $data_desc_struct->{'AE'}->{'dspace-collection-name'},
        });
    my $target_item = SDM::Archive::DSpace::get_item({
        'collection_obj' => $target_collection,
        'storage_group' => 1,
        'storage_item' => 77,
        });
    Carp::confess("Unable to find target item")
        unless $target_item;

    my $target_item_full = SDM::Archive::DSpace::get_item({
        'collection_obj' => $target_collection,
        'item_id' => $target_item->{'id'},
        });
    print Data::Dumper::Dumper($target_item_full);

    if (scalar(@{$target_item_full->{'bitstreams'}})) {
        Carp::confess("Adding bitstreams to the items with bitstreams not implemented yet");
    }

    my $bitstream_data = read_file_scalar("/_gdm/raw-afk/of-15845-0137/of-15845-0137-001.jpg", {'binary' => 1});
    my $bitstream_add_result = SDM::Archive::DSpace::rest_call({
        'verb' => 'post',
        'link' => $target_item_full->{'link'} . "/bitstreams/?name=of-15845-0137-001.jpg",
        'request_binary' => $bitstream_data,
        'request_type' => 'json',
        });
    print Data::Dumper::Dumper($bitstream_add_result);
}
elsif ($o->{'dspace-rest-get-item'}) {
    Carp::confess("Please specify item id")
        unless defined($o->{'dspace-rest-get-item'});

    my $target_community = SDM::Archive::DSpace::get_community_by_name("Архив");
    my $target_collection = SDM::Archive::DSpace::get_collection({
        'community_obj' => $target_community,
        'collection_name' => $data_desc_struct->{'AE'}->{'dspace-collection-name'},
        });

    my $target_item_full = SDM::Archive::DSpace::get_item({
        'collection_obj' => $target_collection,
        'item_id' => $o->{'dspace-rest-get-item'},
        });
    print Data::Dumper::Dumper($target_item_full);
}
elsif ($o->{'dspace-rest-get-items'}) {
    Carp::confess("Please specify item ids")
        unless defined($o->{'dspace-rest-get-items'});

    my $target_community = SDM::Archive::DSpace::get_community_by_name("Архив");
    my $target_collection = SDM::Archive::DSpace::get_collection({
        'community_obj' => $target_community,
        'collection_name' => $data_desc_struct->{'AE'}->{'dspace-collection-name'},
        });

    my $ids = [split(",", $o->{'dspace-rest-get-items'})];

    foreach my $id (@{$ids}) {
        # silently process handles (and maybe more)
        my $item = SDM::Archive::DSpace::get_item({
            'collection_obj' => $target_collection,
            'item_id' => $id,
            });
    
        my $res = SDM::Archive::DSpace::item_list_print({
            'collection_obj' => $target_collection,
            'item_id' => $item->{'id'},
            });
        print $res . "\n";
    }
}
elsif ($o->{'rest-test'}) {
    my $target_community = SDM::Archive::DSpace::get_community_by_name("Архив");
    print Data::Dumper::Dumper($target_community);

    my $target_collection = SDM::Archive::DSpace::get_collection({
        'community_obj' => $target_community,
        'collection_name' => $data_desc_struct->{'AE'}->{'dspace-collection-name'},
        });
    print Data::Dumper::Dumper($target_collection);

    my $coll_items = SDM::Archive::DSpace::get_collection_items({
        'collection_obj' => $target_collection,
        });
    print Data::Dumper::Dumper($coll_items);
}
elsif ($o->{'scan-list-without-ocr'}) {
    my $target_community = SDM::Archive::DSpace::get_community_by_name("Архив");
    my $target_collection = SDM::Archive::DSpace::get_collection({
        'community_obj' => $target_community,
        'collection_name' => $data_desc_struct->{'AE'}->{'dspace-collection-name'},
        });

    if ($o->{'limit'}) {
        if (!SDM::Archive::Utils::is_integer($o->{'limit'}, {'positive-only' => 1})) {
            Carp::confess("--limit N requires N to be positive integer, got [$o->{'limit'}]");
        }
    }

    my $coll_items = SDM::Archive::DSpace::get_collection_items({
        'collection_obj' => $target_collection,
        'expand' => 'bitstreams',
        'limit' => $o->{'limit'} || 4000,
        });

    ITEMS: foreach my $item (@{$coll_items}) {
        my $has_ocr;
        if (scalar(@{$item->{'bitstreams'}})) {
            BITSTREAMS: foreach my $bitstream (@{$item->{'bitstreams'}}) {
                if ($bitstream->{'mimeType'} eq 'text/html' ||
                    $bitstream->{'mimeType'} eq 'application/pdf') {

                    $has_ocr = 1;
                    last BITSTREAMS;
                }
            }
        }

        if (!$has_ocr) {
            my $target_item_full = SDM::Archive::DSpace::get_item({
                'collection_obj' => $target_collection,
                'item_id' => $item->{'id'},
                });

            my $desc = SDM::Archive::DSpace::get_metadata_by_key($target_item_full->{'metadata'}, 'dc.description');
            if (ref($desc) eq 'ARRAY') {
                my $id = SDM::Archive::DSpace::get_metadata_by_key($target_item_full->{'metadata'}, 'dc.identifier.other', {'language' => 'ru'});
                print $id->{'value'} . "\n";
            }
            else {
                print $desc->{'value'} . "\n";
            }
        }
    }
}
elsif ($o->{'scan-list-without-scan'}) {
    my $target_community = SDM::Archive::DSpace::get_community_by_name("Архив");
    my $target_collection = SDM::Archive::DSpace::get_collection({
        'community_obj' => $target_community,
        'collection_name' => $data_desc_struct->{'AE'}->{'dspace-collection-name'},
        });
    if ($o->{'limit'}) {
        if (!SDM::Archive::Utils::is_integer($o->{'limit'}, {'positive-only' => 1})) {
            Carp::confess("--limit N requires N to be positive integer, got [$o->{'limit'}]");
        }
    }

    my $coll_items = SDM::Archive::DSpace::get_collection_items({
        'collection_obj' => $target_collection,
        'expand' => 'bitstreams',
        'limit' => $o->{'limit'} || 4000,
        });

    ITEMS: foreach my $item (@{$coll_items}) {
        my $has_scans;
        if (scalar(@{$item->{'bitstreams'}})) {
            BITSTREAMS: foreach my $bitstream (@{$item->{'bitstreams'}}) {
                if ($bitstream->{'mimeType'} eq 'image/jpeg') {
                    $has_scans = 1;
                    last BITSTREAMS;
                }
            }
        }

        if (!$has_scans) {
            my $target_item_full = SDM::Archive::DSpace::get_item({
                'collection_obj' => $target_collection,
                'item_id' => $item->{'id'},
                });

            my $scanScheduled = SDM::Archive::DSpace::get_metadata_by_key($target_item_full->{'metadata'}, 'sdm-archive.date.scanScheduled');
            if ($scanScheduled) {
                next ITEMS;
            }
            
            my $res = SDM::Archive::DSpace::item_list_print({
                'collection_obj' => $target_collection,
                'item_id' => $item->{'id'},
                });
            print $res . "\n";
        }
    }
}
elsif ($o->{'scan-schedule-scan'}) {
    my $target_collection_name;

    if (!$o->{'target-collection'}) {
        $target_collection_name = $data_desc_struct->{'AE'}->{'dspace-collection-name'};
    }
    else {
        if (!defined($data_desc_struct->{$o->{'target-collection'}})) {
            Carp::confess("Non-existent collection: " . $o->{'target-collection'});
        }

        $target_collection_name = $data_desc_struct->{$o->{'target-collection'}}->{'dspace-collection-name'};
    }

    my $target_community = SDM::Archive::DSpace::get_community_by_name("Архив");
    my $target_collection = SDM::Archive::DSpace::get_collection({
        'community_obj' => $target_community,
        'collection_name' => $target_collection_name,
        });

    my $now = SDM::Archive::Utils::get_time();

    my $scan_requested = [];

    my $ids = [split(",", $o->{'scan-schedule-scan'})];
    ID: foreach my $id (@{$ids}) {
        my $item = SDM::Archive::DSpace::get_item({
            'collection_obj' => $target_collection,
            'item_id' => $id,
            });

        if (scalar(@{$item->{'bitstreams'}})) {
            Carp::carp(
                "SKIPPED: item [$item->{'id'} $item->{'handle'}] already has " .
                scalar(@{$item->{'bitstreams'}}) .
                " bistreams, specify --rescan to request another scan round"
                );
            next ID;
        }

        my $scanScheduled = SDM::Archive::DSpace::get_metadata_by_key($item->{'metadata'}, 'sdm-archive.date.scanScheduled');
        if (!$scanScheduled) {
            my $res = SDM::Archive::DSpace::add_item_metadata({
                'item' => $item,
                'metadata' => {
                    'key' => 'sdm-archive.date.scanScheduled',
                    'value' => join("-", $now->{'year'}, $now->{'month_padded'}, $now->{'mday_padded'}),
                    'language' => '',
                    },
                });
            push @{$scan_requested}, $item;
        }
        else {
            Carp::carp("SKIPPED: item [$item->{'id'} $item->{'handle'}] has already been requested to be scanned on $scanScheduled");
            next ID;
        }
    }

    my $i = 0;
    my $mail_text = "\n\n";
    foreach my $item (@{$scan_requested}) {
        $i++;
        my $res = SDM::Archive::DSpace::item_list_print({
            'collection_obj' => $target_collection,
            'item_id' => $item->{'id'},
            });
        $res =~ s/(^[^\s]+\s+[^\s]+\s+)//;
        $mail_text .= $i . ") " . $res . "\n";
    }
    print $mail_text;
}
elsif ($o->{'scan-list-scheduled-for-scan'}) {
    my $target_community = SDM::Archive::DSpace::get_community_by_name("Архив");
    my $target_collection = SDM::Archive::DSpace::get_collection({
        'community_obj' => $target_community,
        'collection_name' => $data_desc_struct->{'AE'}->{'dspace-collection-name'},
        });
    if ($o->{'limit'}) {
        if (!SDM::Archive::Utils::is_integer($o->{'limit'}, {'positive-only' => 1})) {
            Carp::confess("--limit N requires N to be positive integer, got [$o->{'limit'}]");
        }
    }

    my $coll_items = SDM::Archive::DSpace::get_collection_items({
        'collection_obj' => $target_collection,
        'expand' => 'metadata',
        'limit' => $o->{'limit'} || 4000,
        });
    ITEMS: foreach my $item (@{$coll_items}) {
        my $scanScheduled = SDM::Archive::DSpace::get_metadata_by_key($item->{'metadata'}, 'sdm-archive.date.scanScheduled');
        if ($scanScheduled) {
            my $item_w_bitstreams = SDM::Archive::DSpace::get_item({
                'collection_obj' => $target_collection,
                'item_id' => $item->{'id'},
                });
            
            my $has_scans;
            if (scalar(@{$item_w_bitstreams->{'bitstreams'}})) {
                BITSTREAMS: foreach my $bitstream (@{$item_w_bitstreams->{'bitstreams'}}) {
                    if ($bitstream->{'mimeType'} eq 'image/jpeg') {
                        $has_scans = 1;
                        last BITSTREAMS;
                    }
                }
            }

            # TODO: add check of metadata field filled in when new scans are added to the archive
            if (!$has_scans) {
                my $res = SDM::Archive::DSpace::item_list_print({
                    'collection_obj' => $target_collection,
                    'item_id' => $item->{'id'},
                    });
                print $res . "\n";
            }
        }
    }
}
elsif ($o->{'scan-add-scans'}) {
    #
    # can update items with newly added bitstreams (can't replace bitstreams)
    #
    Carp::confess("Need item_id")
        unless SDM::Archive::Utils::is_integer($o->{'scan-add-scans'}, {'positive-only' => 1});
    Carp::confess("Need --from /path")
        unless defined($o->{'from'}) && -d $o->{'from'};

    my $target_community = SDM::Archive::DSpace::get_community_by_name("Архив");
    my $target_collection = SDM::Archive::DSpace::get_collection({
        'community_obj' => $target_community,
        'collection_name' => $data_desc_struct->{'AE'}->{'dspace-collection-name'},
        });
    my $target_item = SDM::Archive::DSpace::get_item({
        'collection_obj' => $target_collection,
        'item_id' => $o->{'scan-add-scans'},
        });
    Carp::confess("Unable to find target item")
        unless $target_item;

    my $i = SDM::Archive::DSpace::get_item({
        'collection_obj' => $target_collection,
        'item_id' => $target_item->{'id'},
        });

    my $now = SDM::Archive::Utils::get_time();
    my $digitized;
    my $textExtracted;

    my $new_bitstreams = Yandex::Tools::read_dir($o->{'from'});
    ITEM_ELEMENT: foreach my $f (@{$new_bitstreams}) {

        # skip hidden files
        next if $f =~ /^\./;

        if (! -f $o->{'from'} . "/" . $f) {
            Carp::confess("Unexpected element [" . $o->{'from'} . "/" . $f . "]");
        }
        if ($f !~ /\.(jpg|txt)$/) {
            Carp::confess("Unexpected element [" . $o->{'from'} . "/" . $f . "]");
        }

        if (scalar(@{$i->{'bitstreams'}})) {
            foreach my $bs (@{$i->{'bitstreams'}}) {
                if ($bs->{'name'} eq $f) {
                    Carp::carp("Bitstream named [$bs->{'name'}] already exists in item [$i->{'id'} $i->{'handle'}]");
                    next ITEM_ELEMENT;
                }
            }
        }

        $digitized = 1;
        my $bitstream_data = read_file_scalar($o->{'from'} . "/" . $f, {'binary' => 1});
        my $bitstream_add_result = SDM::Archive::DSpace::rest_call({
            'verb' => 'post',
            'link' => $i->{'link'} . "/bitstreams/?name=" . $f,
            'request_binary' => $bitstream_data,
            'request_type' => 'json',
            });

        SDM::Archive::do_log(
            "dspace server [" . $SDM::Archive::runtime->{'dspace_rest'}->{'dspace_server'} . "] " .
            "added [" . $f . "] to the item [$i->{'id'} $i->{'handle'}]"
            );
    }

    if ($digitized) {
        my $now_date = join("-", $now->{'year'}, $now->{'month_padded'}, $now->{'mday_padded'});
        my $res = SDM::Archive::DSpace::add_item_metadata({
            'item' => $i,
            'metadata' => {
                'key' => 'sdm-archive.date.digitized',
                'value' => $now_date,
                'language' => '',
                },
            });
        $res = SDM::Archive::DSpace::update_item_metadata({
            'item' => $i,
            'metadata' => {
                'key' => 'dc.date.accessioned',
                'value' => $now_date,
                'language' => '',
                },
            });
    }
}
elsif ($o->{'dspace-update-date-accesioned-with-scanned'}) {
    my $target_community = SDM::Archive::DSpace::get_community_by_name("Архив");
    my $target_collection = SDM::Archive::DSpace::get_collection({
        'community_obj' => $target_community,
        'collection_name' => $data_desc_struct->{'AE'}->{'dspace-collection-name'},
        });

    my $coll_items = SDM::Archive::DSpace::get_collection_items({
        'collection_obj' => $target_collection,
        'expand' => 'metadata',
        'limit' => $o->{'limit'} || 4000,
        });

    ITEMS: foreach my $item (@{$coll_items}) {
        my $dateDigitized = SDM::Archive::DSpace::get_metadata_by_key($item->{'metadata'}, 'sdm-archive.date.digitized');
        my $dateAccesioned = SDM::Archive::DSpace::get_metadata_by_key($item->{'metadata'}, 'dc.date.accessioned');

        if ($dateDigitized) {
            my $lastDigitizedDate;

            if (ref($dateDigitized) eq 'ARRAY') {
                foreach my $ddate (@{$dateDigitized}) {
                    if (!$lastDigitizedDate || $lastDigitizedDate lt $ddate->{'value'}) {
                        $lastDigitizedDate = $ddate->{'value'};
                    }
                }
            }
            else {
                $lastDigitizedDate = $dateDigitized->{'value'};
            }

            if ($dateAccesioned->{'value'} eq $lastDigitizedDate) {
                next ITEMS;
            }

            my $res = SDM::Archive::DSpace::update_item_metadata({
                'item' => $item,
                'metadata' => {
                    'key' => 'dc.date.accessioned',
                    'value' => $lastDigitizedDate,
                    'language' => '',
                    },
                });
        }
    }
}
elsif ($o->{'dspace-update-storageItemEqualized'}) {
    my $target_community = SDM::Archive::DSpace::get_community_by_name("Архив");
    my $target_collection = SDM::Archive::DSpace::get_collection({
        'community_obj' => $target_community,
        'collection_name' => $data_desc_struct->{'AE'}->{'dspace-collection-name'},
        });

    my $coll_items = SDM::Archive::DSpace::get_collection_items({
        'collection_obj' => $target_collection,
        'expand' => 'metadata',
        'limit' => $o->{'limit'} || 4000,
        });
    ITEMS: foreach my $item (@{$coll_items}) {
        my $storageItem = SDM::Archive::DSpace::get_metadata_by_key($item->{'metadata'}, 'sdm-archive.misc.storageItem');
        my $storageItemEqualized = SDM::Archive::DSpace::get_metadata_by_key($item->{'metadata'}, 'sdm-archive.misc.storageItemEqualized');

        if (!$storageItemEqualized || sprintf("%04d", $storageItem->{'value'}) ne $storageItemEqualized->{'value'}) {
            my $res = SDM::Archive::DSpace::update_item_metadata({
                'item' => $item,
                'metadata' => {
                    'key' => 'sdm-archive.misc.storageItemEqualized',
                    'value' => sprintf("%04d", $storageItem->{'value'}),
                    'language' => '',
                    },
                });
        }
    }
}
elsif ($o->{'scan-schedule-ocr'}) {
    # input: 1 item; which metadata field to set?
}
elsif ($o->{'scan-list-scheduled-for-ocr'}) {
}
elsif ($o->{'scan-add-ocr'}) {
    # which metadata field(s) to set?
}
elsif ($o->{'oracle-parse'}) {
    #
    # create database kamis_import DEFAULT CHARACTER SET utf8;
    #
    # aconsole.pl --oracle-dump-file MEDIA_DATA_TABLE.sql --oracle-parse
    # - reads SQL developer produced table dump
    # - splits into statements
    # - caches stats into .stats.nfreeze
    #
    # aconsole.pl --oracle-dump-file MEDIA_DATA_TABLE.sql --oracle-parse --generate-mysql-table-def
    # - produces ready to be used table definition for mysql (based on stats from the previous step)
    #
    # manually create the table (copy/paste)
    #
    # aconsole.pl --oracle-dump-file MEDIA_DATA_TABLE.sql --oracle-parse --fill-local-mysql
    # - populates mysql table (created at the previous step)
    #
    # alter table DARVIN_KLASS add index id_bas (id_bas);
    # alter table DARVIN_PAI_KLA add index PAICODE (PAICODE);
    # alter table DARVIN_KLROL add index id_bas (id_bas);
    # alter table DARVIN_ARTIST add index id_bas (id_bas);
    # alter table DARVIN_PAINTS add index id_bas (ID_BAS);
    # alter table DARVIN_PAINTS add index ntxran_nomkp (NTXRAN, NOMKP);
    # alter table DARVIN_PAINTS add index ntxran_nomk1 (NTXRAN, NOMK1);
    #

    Carp::confess("Need --oracle-dump-file to parse, got [" . safe_string($o->{'oracle-dump-file'}) . "]")
        unless $o->{'oracle-dump-file'};

    my $stats_cache_filename = $o->{'oracle-dump-file'} . ".stats.nfreeze";

    my $stats = {
        'table_name' => undef,
        'max-f-length' => {},
        'only-digits' => {},
        };

    if (-e $stats_cache_filename) {
        my $stats_tmp = Storable::thaw(IOW::File::read_file_scalar($stats_cache_filename));
        my $old_version;
        foreach my $k (keys %{$stats}) {
            if (! exists($stats_tmp->{$k})) {
                $old_version = 1;
                last;
            }
        }
        foreach my $k (keys %{$stats_tmp}) {
            if (! exists($stats->{$k})) {
                $old_version = 1;
                last;
            }
        }
        if (!$old_version) {
            $stats = $stats_tmp;
        }
    }

    my $mysql_table;
    if (defined($stats->{'table_name'})) {
        print Data::Dumper::Dumper($stats);

        $mysql_table = {
            'table_name' => $stats->{'table_name'},
            'data_type' => {},
        };
        $mysql_table->{'table_name'} =~ s/\./_/g;

        if (defined($o->{'local-mysql-target-tablename'})) {
            $mysql_table->{'table_name'} = $o->{'local-mysql-target-tablename'};
        }

        my $rec_ok;
        my $text_fields_needed = 0;
        
        while (!$rec_ok) {
            my $record_size = 0;
            my $text_fields_created = 0;

            foreach my $field_name (
                sort { $stats->{'max-f-length'}->{$b} <=> $stats->{'max-f-length'}->{$a} }
                keys %{$stats->{'max-f-length'}}
                ) {

                if ($stats->{'only-digits'}->{$field_name}) {
                    $mysql_table->{'data_type'}->{$field_name} = "int";
                    $record_size += 8;
                } else {
                    if ($text_fields_created < $text_fields_needed) {
                        $mysql_table->{'data_type'}->{$field_name} = "text";
                        $text_fields_created++;                       
                    } else {
                        my $size = 2**(int(log($stats->{'max-f-length'}->{$field_name})/log(2))+1);
                        $mysql_table->{'data_type'}->{$field_name} = "varchar(" . $size . ")";
                        $record_size += $size * 3;
                    }
                }
            }

            if ($record_size < 65000) {
                $rec_ok = 1;
            } else {
                $text_fields_needed++;
                print "record too large: $record_size, changing $text_fields_needed longest fields to text\n";
            }
        }
        print Data::Dumper::Dumper($mysql_table);

        if ($o->{'generate-mysql-table-def'}) {
            my $def = "create table " . $mysql_table->{'table_name'} . " (\n";
    
            foreach my $field_name (sort keys %{$mysql_table->{'data_type'}}) {
                $def .= "  " . $field_name . " " .
                    $mysql_table->{'data_type'}->{$field_name} .
                    ",\n";
            }
            chop($def);
            chop($def);
            $def .= "\n);";

            print "\n" . $def . "\n";
        }

        if (!$o->{'fill-local-mysql'} && !$o->{'dump'}) {
            exit;
        }
    }

    my $current_window = "";
    my $current_record;
    my $rec = 0;
    
    my $dbh = SDM::Archive::DB::get_kamis_db();

    my $process_record = sub {
      my ($current_record) = @_;

      if ($current_record =~ /Insert into\s([^\s]+?)\s*?\(([^\)]+?)\)\s*values\s*\((.+)\);/s) {

        my ($table_name, $field_list, $value_list) = ($1, $2, $3);

        if ($stats->{'table_name'} && $stats->{'table_name'} ne $table_name) {
          Carp::confess("at least two different tables ($stats->{'table_name'}, $table_name) are populated in the file, please split");
        }
        if (!$stats->{'table_name'}) {
          $stats->{'table_name'} = $table_name;
        }

        my $record = {
          'field_position_by_name' => {},
          'field_name_by_position' => {},
          'values_by_field_name' => {},
        };

        my $i = 0;
        foreach my $f (split(/,/s, $field_list, -1)) {
          $record->{'field_position_by_name'}->{$f} = $i;
          $record->{'field_name_by_position'}->{$i} = $f;
          $i++;
        }

        $i = 0;
        my $values = [];
        $value_list =~ s/''/___single_quote___/g;
        while ($value_list =~ /^,?(null|'([^']+?)')(.*)$/s) {
          my ($value, $left_values) = ($1, $3);
          $value =~ s/^\'//;
          $value =~ s/\'$//;

          if (!defined($record->{'field_name_by_position'}->{$i})) {
            Carp::confess("Record [$rec], field number [$i] exists in value list, but is not found in the fields list; current_record: $current_record");
          }

          if ($value ne 'null') {
            $value =~ s/___single_quote___/'/g;
            $record->{'values_by_field_name'}->{$record->{'field_name_by_position'}->{$i}} = $value;

            if (!defined($stats->{'max-f-length'}->{$record->{'field_name_by_position'}->{$i}}) ||
                $stats->{'max-f-length'}->{$record->{'field_name_by_position'}->{$i}} < length($value)) {
              $stats->{'max-f-length'}->{$record->{'field_name_by_position'}->{$i}} = length($value);
                }
    
                if (!defined($stats->{'only-digits'}->{$record->{'field_name_by_position'}->{$i}}) ||
                    $stats->{'only-digits'}->{$record->{'field_name_by_position'}->{$i}}
                   ) {
                  if ($value !~ /^\d+$/) {
                    $stats->{'only-digits'}->{$record->{'field_name_by_position'}->{$i}} = 0;
                  }
              else {
                    $stats->{'only-digits'}->{$record->{'field_name_by_position'}->{$i}} = 1;
              }
                  }
              } else {
                if (!defined($stats->{'max-f-length'}->{$record->{'field_name_by_position'}->{$i}})) {
                  $stats->{'max-f-length'}->{$record->{'field_name_by_position'}->{$i}} = 0;
                }
                if (!defined($stats->{'only-digits'}->{$record->{'field_name_by_position'}->{$i}})) {
                  $stats->{'only-digits'}->{$record->{'field_name_by_position'}->{$i}} = 1;
                }
              }

          $value_list = $left_values;
          $i++;
        }

        if ($o->{'dump'}) {
          print Data::Dumper::Dumper($record->{'values_by_field_name'});
        }
        if ($o->{'fill-local-mysql'}) {
          my $fields = join(",", sort keys %{$record->{'values_by_field_name'}});
          my $values_q = join(",", map {"?"} sort keys %{$record->{'values_by_field_name'}});
          my $sth = SDM::Archive::DB::execute_statement({
                 'dbh' => \$dbh,
                 'sql' => "insert into $mysql_table->{'table_name'} ($fields) values ($values_q)",
                     'bound_values' => [
                         map {
                             $record->{'values_by_field_name'}->{$_}
                         }
                         sort keys %{$record->{'values_by_field_name'}}],
          });
        }

      }
    };

    my $fh;
    open($fh, "<" . $o->{'oracle-dump-file'}) || Carp::confess("Unable to read from [" . safe_string($o->{'oracle-dump-file'}) . "]");
    binmode($fh, ':encoding(UTF-8)');

    while (my $l = <$fh>) {
    
        $current_window .= $l;

        if (length($current_window) > 32768) {
            Carp::confess("Got record bigger than 32K or unknown format; current_window follows: " . $current_window);
        }

        if ($current_window =~ /^(.*?)(Insert into.+?)\n(Insert into.+)$/s) {
            $rec++;

            $current_record = $2;
            $current_window = $3;

            $process_record->($current_record);
        }
    }
    close($fh);
  
    # process last record
    $process_record->($current_window);

    print Data::Dumper::Dumper($stats);
    IOW::File::write_file_scalar($stats_cache_filename, Storable::nfreeze($stats));
    print "written table [$stats->{'table_name'}] stats into $stats_cache_filename; rerun to proceed\n";
}
elsif ($o->{'dspace-update-classification-groups-from-kamis-15845'}) {
        my $kamis_groups = {};

  my $dbh = SDM::Archive::DB::get_kamis_db();
  my $sth = SDM::Archive::DB::execute_statement({
    'dbh' => \$dbh,
    'sql' => "
      select DARVIN_PAINTS.NOMKP, DARVIN_KLASS.ALLNAMES
      from
        DARVIN_PAINTS
          inner join
        DARVIN_PAI_KLA on DARVIN_PAI_KLA.PAICODE = DARVIN_PAINTS.ID_BAS
          inner join
        DARVIN_KLASS on DARVIN_KLASS.ID_BAS = DARVIN_PAI_KLA.KLASCOD
      where
        DARVIN_PAINTS.status=1 AND
        DARVIN_PAINTS.fond=16 and
        DARVIN_PAINTS.txran=1 and
        instr(DARVIN_PAINTS.nomkp, '15845') and
        DARVIN_KLASS.id_kl = 86
      order
        by DARVIN_PAINTS.NOMKP, DARVIN_KLASS.ID_KL",
    'bound_values' => [],
  });
  while (my $row = $sth->fetchrow_hashref()) {
    if ($row->{'NOMKP'} !~ /^([^\s]+)\s([^\/]+)\/(.+)$/) {
      Carp::confess("Unknown NOMKP format: " . Data::Dumper::Dumper($row));
    }
    my ($fond, $storage_item) = ($2, $3);

    if ($row->{'ALLNAMES'} !~ /^([^\s]+).*$/) {
      Carp::confess("Unknown ALLNAMES format: " . Data::Dumper::Dumper($row));
    }
    my $classification_group = $1;
    $classification_group =~ s/А/A/g;
    $classification_group =~ s/Б/B/g;
    $classification_group =~ s/В/C/g;

    my $cc = SDM::Archive::match_classification_group_by_code($classification_group);
    Carp::confess("Unable to find classification group for [$classification_group]: " . Data::Dumper::Dumper($row))
      unless $cc;

    $kamis_groups->{$fond . "/". $storage_item} = $cc;
#   print $fond . " " . $storage_item . " " . $cc . "\n";
  }

  my $target_community = SDM::Archive::DSpace::get_community_by_name("Архив");
  my $target_collection = SDM::Archive::DSpace::get_collection({
      'community_obj' => $target_community,
      'collection_name' => $data_desc_struct->{'AE'}->{'dspace-collection-name'},
  });

  my $coll_items = SDM::Archive::DSpace::get_collection_items({
      'collection_obj' => $target_collection,
      'expand' => 'metadata',
      'limit' => $o->{'limit'} || 4000,
  });

  ITEMS: foreach my $item (@{$coll_items}) {
    my $dspace_fond = SDM::Archive::DSpace::get_metadata_by_key($item->{'metadata'}, 'sdm-archive.misc.fond');
    my $dspace_st_item = SDM::Archive::DSpace::get_metadata_by_key($item->{'metadata'}, 'sdm-archive.misc.storageItem');

    if (!$dspace_fond) {
      Carp::confess("sdm-archive.misc.fond not defined for item: " . Data::Dumper::Dumper($item));
    }
    if (ref($dspace_fond) ne 'HASH') {
            # doesn't happen for 15845 items
      next ITEMS;
    }
    if (!$dspace_st_item) {
      Carp::confess("sdm-archive.misc.storageItem not defined for item: " . Data::Dumper::Dumper($item));
    }
    if (ref($dspace_st_item) ne 'HASH') {
            # doesn't happen for 15845 items
      next ITEMS;
    }

    if (!$kamis_groups->{$dspace_fond->{'value'} . "/" . $dspace_st_item->{'value'}}) {
      next ITEMS;
    }

    my $cc_code = SDM::Archive::DSpace::get_metadata_by_key($item->{'metadata'}, 'sdm-archive.misc.classification-code');
    if ($cc_code) {
      print "classification code for [" . $dspace_fond->{'value'} . "/" . $dspace_st_item->{'value'} . "] already defined, skipping\n";
      next ITEMS;
    }

#   print $dspace_fond->{'value'} . "/" . $dspace_st_item->{'value'} . ": setting sdm-archive.misc.classification-code to [" .
#       $kamis_groups->{$dspace_fond->{'value'} . "/" . $dspace_st_item->{'value'}} . "]\n";
    my $res;
    $res = SDM::Archive::DSpace::update_item_metadata({
        'item' => $item,
        'metadata' => {
            'key' => 'sdm-archive.misc.classification-code',
            'value' => $kamis_groups->{$dspace_fond->{'value'} . "/" . $dspace_st_item->{'value'}},
            'language' => '',
        },
    });
    $res = SDM::Archive::DSpace::update_item_metadata({
        'item' => $item,
        'metadata' => {
            'key' => 'sdm-archive.misc.classification-group',
            'value' => $data_desc_struct->{'AE'}->{'storage_groups'}->{'1'}->{'classification_codes'}->{$kamis_groups->{$dspace_fond->{'value'} . "/" . $dspace_st_item->{'value'}}},
            'language' => '',
        },
    });
  }
}
elsif ($o->{'browse-kamis-by-fond-number'}) {
    my ($of_nvf, $fond_num) = split("-", $o->{'browse-kamis-by-fond-number'});

    Carp::confess("Usage: --browse-kamis-by-fond-number of-9627")
        unless $of_nvf && $fond_num;

    if ($of_nvf eq 'of') {
        $of_nvf = 'ОФ';
    }
    if ($of_nvf eq 'nvf') {
        $of_nvf = 'НВФ';
    }

    my $dbh = SDM::Archive::DB::get_kamis_db();
    my $sth = SDM::Archive::DB::execute_statement({
        'dbh' => \$dbh,
        'sql' => "
            select
                *
            from
                DARVIN_PAINTS
            where
                NOMK1 = ? AND
                NTXRAN = ?
            ",
        'bound_values' => [$fond_num, $of_nvf],
        });

    my $huge_data = {
        'distribution_by_number_of_pages' => {},
        };
    my $data = {
        'total_documents' => 0,
        'total_pages' => 0,
        };

    while (my $row = $sth->fetchrow_hashref()) {
        $data->{'total_documents'} ++;

        if (defined($row->{'KOLLIST'})) {
            my $num = $row->{'KOLLIST'};
            $num =~ s/[^\d\+]//g;
            $num = eval($num);
            $data->{'total_pages'} += $num;

            $huge_data->{'distribution_by_number_of_pages'}->{$num} = 0
                unless defined($huge_data->{'distribution_by_number_of_pages'}->{$num});
            $huge_data->{'distribution_by_number_of_pages'}->{$num} ++;
        }

        if ($o->{'dump'}) {
            print Data::Dumper::Dumper(SDM::Archive::DB::non_null_fields($row));
        }
    }

    print join("\t", "N", "DocPgs", "Docs", "TotPages") . "\n";
    my $output_lines = 0;
    my $output_pages = 0;
    foreach my $k (sort {
        $huge_data->{'distribution_by_number_of_pages'}->{$b} <=>
        $huge_data->{'distribution_by_number_of_pages'}->{$a} 
        } keys %{$huge_data->{'distribution_by_number_of_pages'}})  {
        
        $output_lines ++;
        $output_pages += $huge_data->{'distribution_by_number_of_pages'}->{$k} * $k;
        next if $output_pages >= $data->{'total_pages'} ;
        
        print join("\t",
          $output_lines,
          $k,
          $huge_data->{'distribution_by_number_of_pages'}->{$k},
          $output_pages) . "\n";
    }

    $data->{'average_pages_per_document'} = $data->{'total_pages'} / ($data->{'total_documents'} ? $data->{'total_documents'} : 1);

    print Data::Dumper::Dumper($data);
}
elsif ($o->{'browse-kamis-klass'}) {
    my $dbh = SDM::Archive::DB::get_kamis_db();
    my $sth = SDM::Archive::DB::execute_statement({
        'dbh' => \$dbh,
        'sql' => "
            select
                *
            from
                DARVIN_KLASS
            ",
        'bound_values' => [],
        });
    while (my $row = $sth->fetchrow_hashref()) {
        if ($o->{'dump'}) {
            print Data::Dumper::Dumper(SDM::Archive::DB::non_null_fields($row));
        }
    }
}
elsif ($o->{'browse-kamis-local-summary'}) {
    #
    # DARVIN_PAINTS - main documents/objects list 
    # DARVIN_PAINTS.ID_BAS - unique document identifier
    #
    #
    # DARVIN_PAI_KLA - options of documents/objects
    # (additional to those contained in DARVIN_PAINTS fields)
    #   - DARVIN_PAINTS -- one to many DARVIN_PAI_KLA
    #     DARVIN_PAI_KLA.PAICODE = DARVIN_PAINTS.ID_BAS
    #   - DARVIN_KLASS -- one to many DARVIN_PAI_KLA
    #     DARVIN_PAI_KLA.KLASCOD = DARVIN_KLASS.ID_BAS
    # 
    #
    my $data2 = {
        'total_documents' => 0,
        'unique_field_samples' => {},
        'unique_klass_field_values' => {},
        };

    my $dbh = SDM::Archive::DB::get_kamis_db();

    foreach my $i (split(" ", $o->{'browse-kamis-local-summary'})) {

        my ($of_nvf, $fund_number) = split(/\-/, $i);
        Carp::confess("Usage: --browse-kamis-local-summary 'of-9627 of-9628'")
            unless $of_nvf && $fund_number;

        $of_nvf =~ s/OF/ОФ/i;
        $of_nvf =~ s/NVF/НВФ/i;
            
        my $sth = SDM::Archive::DB::execute_statement({
            'dbh' => \$dbh,
            'sql' => "select * from DARVIN_PAINTS where NOMK1 = ? AND NTXRAN = ?",
            'bound_values' => [$fund_number, $of_nvf],
            });

        my $huge_data = {
            'by_NOMK' => {},
            'distribution_by_number_of_pages' => {},
            'tsv_struct' => {},
            };
        my $data = {
          'min' => {},
          'max' => {},
          'AVTOR_unique' => {},
          'total_pages' => 0,
          'total_documents' => 0,
          };
        while (my $row = $sth->fetchrow_hashref()) {

            my $row_clean = SDM::Archive::DB::non_null_fields($row);
            foreach my $f (keys %{$row_clean}) {
                $data2->{'unique_field_samples'}->{$f} = $row_clean->{$f}
                    unless defined($data2->{'unique_field_samples'}->{$f});
            }
            
            $data2->{'total_documents'} ++;

            $data->{'total_documents'} ++;

            if (!defined($row->{'NOMK2'})) {
                print Data::Dumper::Dumper("NOMK2 not defined: ", SDM::Archive::DB::non_null_fields($row));
                next;
            }

            $huge_data->{'by_NOMK'}->{$row->{'NOMK1'}}->{$row->{'NOMK2'}}->{'__db_row'} = $row;
            
            $data->{'min'}->{$row->{'NOMK1'}} = 99999999
                unless defined($data->{'min'}->{$row->{'NOMK1'}});
            $data->{'max'}->{$row->{'NOMK1'}} = 0
                unless defined($data->{'max'}->{$row->{'NOMK1'}});

            if ($data->{'max'}->{$row->{'NOMK1'}} < $row->{'NOMK2'}) {
                $data->{'max'}->{$row->{'NOMK1'}} = $row->{'NOMK2'};
            }
            if ($data->{'min'}->{$row->{'NOMK1'}} > $row->{'NOMK2'}) {
                $data->{'min'}->{$row->{'NOMK1'}} = $row->{'NOMK2'};
            }

            my $klass = SDM::Archive::DB::kamis_get_paint_klass_by_paints_id_bas($row->{'ID_BAS'});
            foreach my $e (@{$klass}) {
                $data2->{'unique_klass_field_values'}->{$e->{'ID_KL'}} = {}
                    unless defined($data2->{'unique_klass_field_values'}->{$e->{'ID_KL'}});

                $data2->{'unique_klass_field_values'}->{$e->{'ID_KL'}}->{$e->{'NAME'}} = 1
                    unless defined($data2->{'unique_klass_field_values'}->{$e->{'ID_KL'}}->{$e->{'NAME'}});

                $data2->{'unique_klass_field_values'}->{$e->{'ID_KL'}}->{$e->{'NAME'}} ++;
            }

            if ($o->{'dump'}) {
                print Data::Dumper::Dumper(SDM::Archive::DB::non_null_fields($row));
                foreach my $e (@{$klass}) {
                    print Data::Dumper::Dumper(SDM::Archive::DB::non_null_fields($e));
                }
            }
        }

        print "total documents: " . $data->{'total_documents'} . "\n";

        print "top 10 documents by the number of pages \n";
        foreach my $nomk1 (keys %{$data->{'min'}}) {
            for (my $i = $data->{'min'}->{$nomk1}; $i <= $data->{'max'}->{$nomk1}; $i++) {
                if (!defined($huge_data->{'by_NOMK'}->{$nomk1}->{$i})) {
                    print "missing: $i\n";
                }
            }
        }

        my $printed = 0;
        foreach my $k (sort {
            $huge_data->{'distribution_by_number_of_pages'}->{$b} <=>
            $huge_data->{'distribution_by_number_of_pages'}->{$a} 
            } keys %{$huge_data->{'distribution_by_number_of_pages'}})  {
            
            next if $printed > 10;
            
            print $k . ": " . $huge_data->{'distribution_by_number_of_pages'}->{$k} . "\n";
            $printed++;
        }

        $data->{'average_pages_per_document'} = $data->{'total_pages'} / $data->{'total_documents'};

        print Data::Dumper::Dumper($data);
    }
    
    print Data::Dumper::Dumper($data2);
}
elsif ($o->{'browse-kamis-get-paints-by-id'}) {
    my $dbh = SDM::Archive::DB::get_kamis_db();
    my $sth = SDM::Archive::DB::execute_statement({
        'dbh' => \$dbh,
        'sql' => "select * from DARVIN_PAINTS where ID_BAS = ?",
        'bound_values' => [$o->{'browse-kamis-get-paints-by-id'}],
        });
    while (my $row = $sth->fetchrow_hashref()) {
        print Data::Dumper::Dumper(SDM::Archive::DB::non_null_fields($row));

        my $klass = SDM::Archive::DB::kamis_get_paint_klass_by_paints_id_bas($row->{'ID_BAS'});
        foreach my $e (@{$klass}) {
            print Data::Dumper::Dumper(SDM::Archive::DB::non_null_fields($e));
        }
    }
}
elsif ($o->{'oracle-test'}) {
    my $dbh = DBI->connect(
        'dbi:Oracle:host=localhost;sid=ORCL;port=1521',
        'darvin',
        'd', {
            RaiseError => 1,
            AutoCommit => 0,
            LongReadLen => 1000000,
        })
        || Carp::confess($DBI::errstr);
#    my $sth = $dbh->prepare("SELECT * from MEDIA where id_bas = 477380")
#        || Carp::confess ("Couldn't prepare 1st statement: " . $dbh->errstr);

#    my $sth = $dbh->prepare("SELECT * from PAINTS where id_bas = 295634")
#        || Carp::confess ("Couldn't prepare 1st statement: " . $dbh->errstr);

    my $sth = $dbh->prepare("SELECT * from MEDIA_FILE where MEDCODE = 477379")
        || Carp::confess ("Couldn't prepare 1st statement: " . $dbh->errstr);

    $sth->execute;
    while (my $row = $sth->fetchrow_hashref()) {
        print join(" ", $row->{'MEDCODE'}, $row->{'PART_NAME'}, length($row->{'BIN'})) . "\n";
#        print Data::Dumper::Dumper(SDM::Archive::DB::non_null_fields($row));
        File::Path::make_path("/tmp/" . $row->{'MEDCODE'});
        IOW::File::write_file_scalar("/tmp/" . $row->{'MEDCODE'} . "/" . $row->{'PART_NAME'} . ".jpg", $row->{'BIN'});
    }
    $sth->finish;
    $dbh->disconnect;
}
elsif ($o->{'command-list'}) {
    print join("\n", "", sort map {"--" . $_} @{$o_names}) . "\n";
}
else {
    Carp::confess("\nNeed command line parameter (run aconsole.pl --command-list to get full list)\n");
}
