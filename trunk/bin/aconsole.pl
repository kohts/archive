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
#       convert tab separated dump (UTF-8 encoded) of contents
#       of A.E. Kohts archives (which are tracked in KAMIS in SDM,
#       part of the archive was tracked in DBX file previously)
#       into TSV text file ready to be imported into DSpace
#       (the process relies on custom metadata fields as defined
#       in sdm-archive.xml schema)
#
#       Usage example (outputs to STDOUT):
#       aconsole.pl --initial-import --external-tsv /file/name --target-collection-handle 123456789/2
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

my $data_desc_struct;
my $o_names = [
    'bash-completion-list',
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
    'dump-tsv-raw',
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
    'titles',
    'validate-tsv',
    'create-kohtsae-community-and-collection',
    'preprocess-book',
    'book-name=s',
    'filename-filter=s',
    'validate-pagination',
    'autoincrement-duplicate-page-number',
    'ignore-duplicate-fund-id',
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
            last SCAN_DIRS;
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

    SCAN_DIRS: foreach my $scan_dir (@{$st_item->{'scanned_document_directories'}}) {
        
        # this shouldn't happen in production as external_archive_storage_base
        # shouldn't change when this script is run; during tests though
        # this happened (because upload of archive to the test server
        # took about several weeks because of the slow network)
        next unless defined($r_struct->{'files'}->{$scan_dir});

        if ($o->{'dry-run'}) {
            print "would try to add HTML document to [$dspace_collection_item->{'storage-group-id'}/$dspace_collection_item->{'storage-item-id'}]\n";
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

sub find_author {
    my ($author) = @_;

    my $doc_authors = [];

    my $push_found_author = sub {
        my ($author_canonical) = @_;

        Carp::confess("Invalid canonical author name [$author_canonical]")
            unless defined($data_desc_struct->{'authors_canonical'}->{$author_canonical});

        if (scalar (@{$data_desc_struct->{'authors_canonical'}->{$author_canonical}}) == 0) {
            push @{$doc_authors}, {"name" => $author_canonical, "lang" => "ru"};

            if (length($author) > length($author_canonical)) {
                Carp::confess("Please include [$author] into [$author_canonical]");
            }
        } else {
            foreach my $a_struct (@{$data_desc_struct->{'authors_canonical'}->{$author_canonical}}) {
                if (ref($a_struct) eq '') {
                    push @{$doc_authors}, {"name" => $a_struct, "lang" => "ru"};

                    if (length($author) > length($a_struct)) {
                        Carp::confess("Please include [$author] into [$author_canonical]");
                    }
                } else {
                    push @{$doc_authors}, $a_struct;
                }
            }
        }
    };
   
    if (defined($data_desc_struct->{'authors_canonical'}->{$author})) {
        $push_found_author->($author);
    } else {
        my $canonical_search_author = "";
        if ($author =~ /^(.+)\s(.+)\s(.+)$/) {
            my ($lastname, $firstname, $middlename) = ($1, $2, $3);
            $canonical_search_author = $lastname . substr($firstname, 0, 1) . substr($middlename, 0, 1);
        } elsif ($author =~ /^(.+)\s(.+)$/) {
            my ($lastname, $firstname) = ($1, $2);
            $canonical_search_author = $lastname . substr($firstname, 0, 1);
        }

        foreach my $author_short (keys %{$data_desc_struct->{'authors_canonical'}}) {
            my ($tmp1, $tmp2) = ($author_short, $canonical_search_author);
            $tmp1 =~ s/[,\.\s]//g;
            $tmp2 =~ s/[,\.\s]//g;
            if ($tmp1 eq $tmp2 || $author eq $author_short) {
                $push_found_author->($author_short);
            }
              
            foreach my $author_struct (@{$data_desc_struct->{'authors_canonical'}->{$author_short}}) {
                my $check = [];
                if (ref($author_struct) eq '') {
                    push @{$check}, $author_struct;
                } else {
                    push @{$check}, $author_struct->{'name'};
                }

                foreach my $a (@{$check}) {
                    my ($tmp1, $tmp2) = ($a, $author);
                    $tmp1 =~ s/[,\.\s]//g;
                    $tmp2 =~ s/[,\.\s]//g;
                    if ($tmp1 eq $tmp2) {
                        $push_found_author->($author_short);
                    }
                }
            }
        }
    }

    if (scalar(@{$doc_authors}) == 0) {
        Carp::confess("Unable to find canonical author for [$author]");
    }

    return $doc_authors;
}

sub extract_authors {
    my ($text) = @_;

    my $doc_authors = [];
    
    $text =~ s/Автор: Ладыгина. Котс/Автор: Ладыгина-Котс/;
    $text =~ s/Автор: Ладыгина - Котс/Автор: Ладыгина-Котс/;

    while ($text && $text =~ /^\s*Автор:\s([Нн]еизвестный\sавтор|Ладыгина\s*?\-\s*?Котс\s?Н.\s?Н.|[^\s]+?\s+?([^\s]?\.?\s?[^\s]?\.?|))(\s|,)(.+)$/) {
        my $author = $1;
        $text = $4;

        my $doc_authors1 = find_author($author);
        push @{$doc_authors}, @{$doc_authors1};
    }

    $text = trim($text);
    if ($text && $text =~ /^и др\.(.+)/) {
        $text = $1;
    }

    if (!scalar(@{$doc_authors})) {
        push @{$doc_authors}, {"name" => "Котс, Александр Федорович", "lang" => "ru"}, {"name" => "Kohts (Coates), Alexander Erich", "lang" => "en"};
    }

    return {
        'extracted_struct' => $doc_authors,
        'trimmed_input' => $text,
        };
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
    my ($fname) = @_;
    Carp::confess("Programmer error: need filename")
        unless defined($fname) && $fname ne "";

    my $contents = "";
    my $fh;
    open($fh, "<" . $fname) || Carp::confess("Can't open [$fname] for reading");
    binmode($fh, ':encoding(UTF-8)');
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
                " (consider redefining in ~/.aconsole.pl or /etc/aconsole.pl; sample in trunk/tools/.aconsole.pl)");
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
                " (consider redefining in ~/.aconsole.pl or /etc/aconsole.pl; sample in trunk/tools/.aconsole.pl)");
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
                " (consider redefining in ~/.aconsole.pl or /etc/aconsole.pl; sample in trunk/tools/.aconsole.pl)");
        }
    }

    return $SDM::Archive::runtime->{'read_ocr_html_docs'}
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
        'by_storage' => {},
        'funds' => {},
        'storage_items_by_fund_number' => {},
        'title_line' => {},
        'total_input_lines' => 0,
        
        # scanned dir -> array of storage_struct items
        'storage_items_by_scanned_dir' => {},
 
        # html -> array of storage_struct items
        'storage_items_by_ocr_html' => {},
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

        if ($o->{'dump-tsv-raw'}) {
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
                unless defined($data_desc_struct->{'storage_groups'}->{$st_gr_id});

            $doc_struct->{'by_storage'}->{$st_gr_id} = {}
                unless $doc_struct->{'by_storage'}->{$st_gr_id};
        }

        my $st_id;
        if ($data_desc_struct->{'storage_groups'}->{$st_gr_id}->{'name'} eq 'Novikova') {
            $st_id = $line_struct->{'by_field_name'}->{'storage_number'};
        } else {
            $st_id = $line_struct->{'by_field_name'}->{'number_suffix'};
        }
        if (!$st_id) {
            print Data::Dumper::Dumper($line_struct);
            Carp::confess("Unable to detect storage_number for line [$doc_struct->{'total_input_lines'}]");
        }

        my $storage_struct = $doc_struct->{'by_storage'}->{$st_gr_id}->{$st_id} // {'documents' => []};
        push @{$storage_struct->{'documents'}}, $line_struct;
        $doc_struct->{'by_storage'}->{$st_gr_id}->{$st_id} = $storage_struct;
    
        if ($fund_number) {
            $doc_struct->{'storage_items_by_fund_number'}->{$fund_number} = {}
                unless $doc_struct->{'storage_items_by_fund_number'}->{$fund_number};
            $doc_struct->{'storage_items_by_fund_number'}->{$fund_number}->{$st_id} = $storage_struct;
        }
    }

    my $scanned_dirs = read_scanned_docs();
    my $html_files = read_ocr_html_docs();
    my $r2_struct = read_docbook_sources();

    my $today_yyyy_mm_dd = date_from_unixtime(time());

    foreach my $st_gr_id (keys %{$doc_struct->{'by_storage'}}) {
        foreach my $storage_number (sort {$a <=> $b} keys %{$doc_struct->{'by_storage'}->{$st_gr_id}}) {
            my $storage_struct = $doc_struct->{'by_storage'}->{$st_gr_id}->{$storage_number};

            $storage_struct->{'scanned_document_directories'} = [];
            $storage_struct->{'scanned_document_directories_h'} = {};
            $storage_struct->{'ocr_html_document_directories'} = [];
            $storage_struct->{'ocr_html_document_directories_h'} = {};
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
                } elsif (safe_string($opts->{'resource'}) eq 'html') {
                    $resource_struct = $html_files->{'ocr_html_files'};
                    $resource_tmp_name = 'ocr_html_document_directories';
                    $resource_perm_name = 'storage_items_by_ocr_html';
                } elsif (safe_string($opts->{'resource'}) eq 'docbook') {
                    $resource_struct = $r2_struct->{'docbook_files'};
                    $resource_tmp_name = 'docbook_files_dates';
                    $resource_perm_name = 'storage_items_by_docbook';
                } else {
                    Carp::confess("Programmer error: resource type must be one of: scan, html");
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
                        # of-10141-193_478 os the name of the corresponding html file
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
            if ($data_desc_struct->{'storage_groups'}->{$st_gr_id}->{'name'} eq 'Novikova') {
                $try_external_resource->({ 'resource' => 'scan', 'prefix' => 'eh', 'n' => $storage_number, });
            }

            my $predefined_storage_struct;
            if (defined($data_desc_struct->{'storage_groups'}->{$st_gr_id}->{'storage_items'}) &&
                defined($data_desc_struct->{'storage_groups'}->{$st_gr_id}->{'storage_items'}->{$storage_number})) {
                $predefined_storage_struct = $data_desc_struct->{'storage_groups'}->{$st_gr_id}->{'storage_items'}->{$storage_number};                
            }

            my $tsv_struct_helper = {};
            
            # $tsv_struct should contain either default or empty values
            # for all the fields which will be output to csv (empty value
            # could be further changed to meaningful value)
            my $tsv_struct = {
                'dc.contributor.author[en]' => "",
                'dc.contributor.author[ru]' => "",
                'dc.creator[en]' => "",
                'dc.creator[ru]' => "",

                # http://dublincore.org/documents/dcmi-terms/#terms-created
                # Date of creation of the resource.
                'dc.date.created' => "",

                # http://dublincore.org/documents/dcmi-terms/#terms-issued
                # Date of formal issuance (e.g., publication) of the resource.
                #
                # https://jira.duraspace.org/browse/DS-1481
                #  By default, "dc.date.issued" is no longer set to [today] when it's empty
                # (see DS-1745). Therefore, Items deposited via SWORD or bulk upload
                # will not be assigned a "dc.date.issued" unless specified.
#                'dc.date.issued' => '',
                
                # this is a "calculated" field which contains information from
                # a number of other fields (i.e. it should be possible to rebuild
                # this field at any point in time given other fields)
                'dc.description[ru]' => "",

                'dc.identifier.other[ru]' => "",

                # dc.identifier.uri would be populated during metadata-import 
                # 'dc.identifier.uri' => '', # http://hdl.handle.net/123456789/4

                'dc.language.iso[en]' => 'ru',
                'dc.publisher[en]' => 'State Darwin Museum',
                'dc.publisher[ru]' => 'Государственный Дарвиновский Музей',
                'dc.subject[en]' => 'Museology',
                'dc.subject[ru]' => 'Музейное дело',
                'dc.title[ru]' => "",
                'dc.type[en]' => 'Text',
                'sdm-archive.date.digitized' => '',
                'sdm-archive.date.cataloged' => $today_yyyy_mm_dd,
                'sdm-archive.date.textExtracted' => '',
                'sdm-archive.misc.classification-code' => '',
                'sdm-archive.misc.classification-group' => '',
                'sdm-archive.misc.completeness' => '',
                'sdm-archive.misc.authenticity' => '',
                'sdm-archive.misc.inventoryGroup' => $data_desc_struct->{'storage_groups'}->{$st_gr_id}->{'name'},
                'sdm-archive.misc.storageItem' => $storage_number,
                'sdm-archive.misc.fond' => '',
#                'sdm-archive.misc.archive' => '',
            };

            # appends value for metadata field, duplicate values
            # are not appended (all the metadata fields are allowed
            # to contain more than value - array is used if there's
            # more than one value for the field)
            #
            # returns appended value (if input $metadata_value was stored)
            # or undef (if supplied value has already existed and was not
            # appended therefore)
            #
            # does some finegrained cleanup of metadata field values
            # (depending on the name of populated metadata field)
            #
            my $push_metadata_value = sub {
                my ($metadata_name, $metadata_value) = @_;

                $tsv_struct->{$metadata_name} = ""
                    unless defined($tsv_struct->{$metadata_name});
                
                return undef unless defined($metadata_value) && $metadata_value ne "";

                my $cleanup_done;
                while (!$cleanup_done) {
                    my $orig_value = $metadata_value;

                    if ($metadata_name eq 'dc.title[ru]') {
                        # remove start-end double-quotes
                        if ($metadata_value =~ /^"(.+)"$/) {
                            $metadata_value = $1;
                        }

                        # remove trailing dot
                        if ($metadata_value =~ /\.$/) {
                            $metadata_value = substr($metadata_value, 0, length($metadata_value) - 1);
                        }

                        # only remove opening and closing square brackets
                        # when there are not square brackets inside of the title, e.g.
                        # [Codtenschein] . [Документ, имеющий отношение к биографии А.Ф.Котса]
                        if ($metadata_value =~ /^\[([^\[]+)\]$/) {
                            $metadata_value = $1;
                        }
                    } elsif ($metadata_name eq 'dc.date.created') {
                        if ($metadata_value =~ /^\[([^\[]+)\]$/) {
                            $metadata_value = $1;
                        }
                    }

                    if ($orig_value eq $metadata_value) {
                        $cleanup_done = 1;
                    }
                }

                if (!defined($tsv_struct_helper->{$metadata_name})) {
                    $tsv_struct_helper->{$metadata_name} = {};
                }

                if (defined($tsv_struct_helper->{$metadata_name}->{$metadata_value})) {
                    # do not add same values several times
                    return undef;
                } else {
                    $tsv_struct_helper->{$metadata_name}->{$metadata_value} = 1;

                    if (!defined($tsv_struct->{$metadata_name})) {
                        $tsv_struct->{$metadata_name} = $metadata_value;
                    } else {
                        if (ref($tsv_struct->{$metadata_name}) eq '') {
                            if ($tsv_struct->{$metadata_name} eq '') {
                                $tsv_struct->{$metadata_name} = $metadata_value;
                            } else {
                                $tsv_struct->{$metadata_name} = [$tsv_struct->{$metadata_name}, $metadata_value];
                            }
                        } else {
                            push @{$tsv_struct->{$metadata_name}}, $metadata_value;
                        }
                    }

                    return $metadata_value;
                }
            };

            if ($predefined_storage_struct) {
                my $extracted_author;
                if ($predefined_storage_struct =~ /^(.+), переписка$/) {
                    $extracted_author = $1;
                
                    my $doc_authors1 = find_author($extracted_author);
                    foreach my $author (@{$doc_authors1}) {
                        $push_metadata_value->('dc.contributor.author[' . $author->{'lang'} . ']', $author->{'name'});
                        $push_metadata_value->('dc.creator[' . $author->{'lang'} . ']', $author->{'name'});
                    }
                }
                $push_metadata_value->('dc.title[ru]', $predefined_storage_struct);
            }

            # - detect and store storage paths here against $data_desc_struct->{'external_archive_storage_base'}
            # - check "scanned" status (should be identical for all the documents in the storage item)
            STORAGE_PLACE_ITEMS: foreach my $item (@{$storage_struct->{'documents'}}) {

                if (safe_string($item->{'by_field_name'}->{'scanned_doc_id'}) eq '') {
                    Carp::confess("Input TSV invalid format: scanned_doc_id is empty for item " . Data::Dumper::Dumper($item));
                }

                my $title_struct = extract_authors($item->{'by_field_name'}->{'doc_name'});
                foreach my $author (@{$title_struct->{'extracted_struct'}}) {
                    $push_metadata_value->('dc.contributor.author[' . $author->{'lang'} . ']', $author->{'name'});
                    $push_metadata_value->('dc.creator[' . $author->{'lang'} . ']', $author->{'name'});
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
                    $push_metadata_value->('dc.title[ru]', $meta->{'trimmed_input'});
                }

                $doc_type = $push_metadata_value->('sdm-archive.misc.document-type', $doc_type);
                $doc_desc = $push_metadata_value->('sdm-archive.misc.notes', $doc_desc);

                $doc_date = $push_metadata_value->('dc.date.created', $doc_date);

                $push_metadata_value->('dc.identifier.other[ru]', storage_id_csv_to_dspace({
                    'storage-group-id' => $st_gr_id,
                    'storage-item-id' => $storage_number,
                    'language' => 'ru',
                    }));
                $push_metadata_value->('dc.identifier.other[en]', storage_id_csv_to_dspace({
                    'storage-group-id' => $st_gr_id,
                    'storage-item-id' => $storage_number,
                    'language' => 'en',
                    }));

                $item->{'by_field_name'}->{'doc_property_full'} =
                    $push_metadata_value->('sdm-archive.misc.completeness', $item->{'by_field_name'}->{'doc_property_full'});
                $item->{'by_field_name'}->{'doc_property_genuine'} = 
                    $push_metadata_value->('sdm-archive.misc.authenticity', $item->{'by_field_name'}->{'doc_property_genuine'});
                $item->{'by_field_name'}->{'archive_date'} =
                    $push_metadata_value->('sdm-archive.misc.archive-date', $item->{'by_field_name'}->{'archive_date'});

                if ($item->{'by_field_name'}->{'classification_code'} &&
                    defined($data_desc_struct->{'storage_groups'}->{$st_gr_id}->{'classification_codes'})
                    ) {

                    foreach my $itcc (split("/", $item->{'by_field_name'}->{'classification_code'})) {
                        $itcc =~ s/[\.,\(\)\s\*]//g;
                        
                        # replace russian with latin (just in case)
                        $itcc =~ s/А/A/g;
                        $itcc =~ s/В/B/g;
                        $itcc =~ s/С/C/g;

                        my $found_cc_group;
                        foreach my $cc (keys %{$data_desc_struct->{'storage_groups'}->{$st_gr_id}->{'classification_codes'}}) {
                            my $tmp_cc = $cc;
                            $tmp_cc =~ s/[\.,\(\)]//g;
                            
                            if ($tmp_cc eq $itcc) {
                                $push_metadata_value->('sdm-archive.misc.classification-group',
                                    $data_desc_struct->{'storage_groups'}->{$st_gr_id}->{'classification_codes'}->{$cc});
                                $push_metadata_value->('sdm-archive.misc.classification-code',
                                    $cc);
                                $found_cc_group = 1;
                            }
                        }

                        if (!$found_cc_group && substr($itcc, length($itcc) - 1) !~ /[0-9]/) {
                            $itcc = substr($itcc, 0, length($itcc) - 1);

                            foreach my $cc (keys %{$data_desc_struct->{'storage_groups'}->{$st_gr_id}->{'classification_codes'}}) {
                                my $tmp_cc = $cc;
                                $tmp_cc =~ s/[\.,\(\)]//g;
                                
                                if ($tmp_cc eq $itcc) {
                                    $push_metadata_value->('sdm-archive.misc.classification-group',
                                        $data_desc_struct->{'storage_groups'}->{$st_gr_id}->{'classification_codes'}->{$cc});
                                    $push_metadata_value->('sdm-archive.misc.classification-code',
                                        $cc);
                                    $found_cc_group = 1;
                                }
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
                    $push_metadata_value->('sdm-archive.misc.fond', "ОФ-" . $item->{'by_field_name'}->{'of_number'});

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
                        'resource' => 'docbook',
                        'prefix' => 'of',
                        'n' => $item->{'by_field_name'}->{'of_number'},
                        'n2' => $item->{'by_field_name'}->{'number_suffix'},
                        });
                } else {
                    $push_metadata_value->('sdm-archive.misc.fond', "НВФ-" . $item->{'by_field_name'}->{'nvf_number'});

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
                $push_metadata_value->('dc.description[ru]', $item_desc);

                $try_external_resource->({
                    'resource' => 'scan',
                    'resource_name' => $item->{'by_field_name'}->{'scanned_doc_id'},
                    });
            }

            foreach my $d (keys %{$storage_struct->{'scanned_document_directories_h'}}) {
                foreach my $d_day (@{$storage_struct->{'scanned_document_directories_h'}->{$d}}) {
                    $push_metadata_value->('sdm-archive.date.digitized', $d_day);
                }
            }
            foreach my $d (keys %{$storage_struct->{'docbook_files_dates_h'}}) {
                $push_metadata_value->('sdm-archive.date.textExtracted', $storage_struct->{'docbook_files_dates_h'}->{$d});
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
                    "]");
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

    # - check that there are no unmatched html files
    foreach my $html (@{$html_files->{'ocr_html_files'}->{'array'}}) {
        if (!defined($doc_struct->{'storage_items_by_ocr_html'}->{$html})) {
            Carp:confess("HTML file [$html] didn't match any storage item");
        }
    }

    $SDM::Archive::runtime->{'csv_struct'} = $doc_struct;
    return $SDM::Archive::runtime->{'csv_struct'};
}

# outputs tsv record for ADDITION into DSpace (with plus sign
# as the DSpace id of the item)
#
# expects hashref with names of the output record as the keys
# of the hash and values of the output record as the values
# of the hash.
#
sub tsv_output_record {
    my ($tsv_record, $o) = @_;
    $o = {} unless $o;

    $o->{'mode'} = 'values' unless $o->{'mode'};

    my $out_array = [];

    if ($o->{'mode'} eq 'labels') {
        # id must be the _first_ column in tsv:
        # https://github.com/DSpace/DSpace/blob/master/dspace-api/src/main/java/org/dspace/app/bulkedit/DSpaceCSV.java#L522
        my $labels = ["id", sort(keys %{$tsv_record})];
    
        $out_array = [];
        foreach my $v (@{$labels}) {
            $v =~ s/"/""/g;
            push @{$out_array}, '"' . $v . '"';
        }
    } elsif ($o->{'mode'} eq 'values') {
        $out_array = ["+"];
        foreach my $field_name (sort keys %{$tsv_record}) {
            my $field_value = $tsv_record->{$field_name};
            
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
        unless defined($csv_struct->{'by_storage'}->{$opts->{'storage-group-id'}});
    return undef
        unless defined($csv_struct->{'by_storage'}->{$opts->{'storage-group-id'}}->{$opts->{'storage-item-id'}});

    return $csv_struct->{'by_storage'}->{$opts->{'storage-group-id'}}->{$opts->{'storage-item-id'}};
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
        unless defined($data_desc_struct->{'storage_groups'}->{$opts->{'storage-group-id'}});

    my $dspace_id_string = $data_desc_struct->{'dspace.identifier.other[' . $opts->{'language'} . ']-prefix'} .
        ' ' . $opts->{'storage-item-id'} . ' (' .
        $data_desc_struct->{'storage_groups'}->{$opts->{'storage-group-id'}}->{'name_readable_' . $opts->{'language'}} .
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
    foreach my $st_gr_id (keys %{$data_desc_struct->{'storage_groups'}}) {
        my $pfx = $data_desc_struct->{'dspace.identifier.other[' . $language . ']-prefix'};
        my $storage_group_txt = $data_desc_struct->{'storage_groups'}->{$st_gr_id}->{'name_readable_' . $language};
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
        my $item_files = Yandex::Tools::read_dir($item_path, {'output-format' => 'hashref'});
        
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

    foreach my $st_gr_id (keys %{$doc_struct->{'by_storage'}}) {
        foreach my $storage_number (sort {$a <=> $b} keys %{$doc_struct->{'by_storage'}->{$st_gr_id}}) {
            my $storage_struct = $doc_struct->{'by_storage'}->{$st_gr_id}->{$storage_number};

            if ($o->{'titles'}) {
                print
                    "storage group (" . $data_desc_struct->{'storage_groups'}->{$st_gr_id}->{'name_readable_en'} . ") " .
                    "storage item " . $storage_number . ": " . $storage_struct->{'tsv_struct'}->{'dc.title[ru]'} . "\n";
            } else {
                print
                    "storage group (" . $data_desc_struct->{'storage_groups'}->{$st_gr_id}->{'name_readable_en'} . ") " .
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
            print Data::Dumper::Dumper($in_doc_struct->{'by_storage'});
        } else {
            print Data::Dumper::Dumper($in_doc_struct);
        }
    }

    print "total input lines: " . $in_doc_struct->{'total_input_lines'} . "\n";
    print "total data lines: " . scalar(@{$in_doc_struct->{'array'}}) . "\n";
    foreach my $st_gr_id (sort keys %{$in_doc_struct->{'by_storage'}}) {
        print
            "total items in storage group [$st_gr_id] (" .
            $data_desc_struct->{'storage_groups'}->{$st_gr_id}->{'name_readable_en'} .
            "): " . scalar(keys %{$in_doc_struct->{'by_storage'}->{$st_gr_id}}) . "\n";
    }

    foreach my $fund_number (sort {$a <=> $b} keys %{$in_doc_struct->{'storage_items_by_fund_number'}}) {
        print uc($in_doc_struct->{'funds'}->{$fund_number}->{'type'}) . " " . $fund_number . ": " .
            scalar(keys %{$in_doc_struct->{'storage_items_by_fund_number'}->{$fund_number}}) . " storage items\n";
    }
}
elsif ($o->{'initial-import'}) {
    Carp::confess("Need --external-tsv")
        unless $o->{'external-tsv'};

    Carp::confess("Need --target-collection-handle")
        unless $o->{'target-collection-handle'};
    my $target_collection_handle = $o->{'target-collection-handle'};

    my $in_doc_struct = tsv_read_and_validate($o->{'external-tsv'}, $o);

    my $output_labels;
    foreach my $st_gr_id (sort keys %{$in_doc_struct->{'by_storage'}}) {
        foreach my $in_id (sort {$a <=> $b} keys %{$in_doc_struct->{'by_storage'}->{$st_gr_id}}) {
            # print $st_gr_id . ":" . $in_id . "\n";
            
            next unless defined($in_doc_struct->{'by_storage'}->{$st_gr_id}->{$in_id}->{'tsv_struct'});

            my $tsv_record = $in_doc_struct->{'by_storage'}->{$st_gr_id}->{$in_id}->{'tsv_struct'};
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
        if ($o->{'limit'} !~ /^\d+$/ || $o->{'limit'} == 0) {
            Carp::confess("--limit N requires N to be positive integer");
        }
    }

    my $scanned_dirs = read_scanned_docs({'must_exist' => 1});
    my $html_files = read_ocr_html_docs({'must_exist' => 1});
    my $r2_struct = read_docbook_sources({'must_exist' => 1});

    my $in_doc_struct = tsv_read_and_validate($o->{'external-tsv'}, $o);
    my $dspace_collection = read_dspace_collection($o->{'dspace-exported-collection'});

    my $updated_items = 0;

    DSPACE_COLLECTION: foreach my $st_gr_id (sort {$a <=> $b} keys %{$dspace_collection}) {

        Carp::confess("Can't find storage group [$st_gr_id] in external-csv [$o->{'external-tsv'}], something is very wrong")
            unless defined($in_doc_struct->{'by_storage'}->{$st_gr_id});
        
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
elsif ($o->{'create-kohtsae-community-and-collection'}) {
    Carp::confess("Need dspace_rest_url configuration option in /etc/aconsole.pl")    
        unless defined($data_desc_struct->{'dspace_rest_url'});
    Carp::confess("Need dspace_upload_user_email configuration option in /etc/aconsole.pl")    
        unless defined($data_desc_struct->{'dspace_upload_user_email'});
    Carp::confess("Need dspace_upload_user_pass configuration option in /etc/aconsole.pl")    
        unless defined($data_desc_struct->{'dspace_upload_user_pass'});

    my $login_token = SDM::Archive::dspace_rest_call({
        'verb' => 'post',
        'action' => 'login',
        'request' => '{"email": "' . $data_desc_struct->{'dspace_upload_user_email'} .
            '", "password": "' . $data_desc_struct->{'dspace_upload_user_pass'} . '"}',
        'request_type' => 'json',
        'dspace_token' => '',
        });
    Carp::confess("Unable to login: $!")
        if !$login_token;
    
    #print $login_token . "\n";

    my $communities = SDM::Archive::dspace_rest_call({
        'verb' => 'get',
        'action' => 'communities',
        'request' => '{}',
        'request_type' => 'json',
        'dspace_token' => $login_token,
        });

    my $comm_struct;
    eval {
        $comm_struct = JSON::decode_json($communities);
    };
    if ($@) {
        Carp::confess("Error parsing json: " . $@);
    }

    my $target_community;
    foreach my $c (@{$comm_struct}) {
        if ($c->{'name'} eq 'Архив') {
            $target_community = $c;
        }
    }

    if (!$target_community) {
        my $new_comm = SDM::Archive::dspace_rest_call({
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
            'dspace_token' => $login_token,
            });

        $communities = SDM::Archive::dspace_rest_call({
            'verb' => 'get',
            'action' => 'communities',
            'request' => '{}',
            'request_type' => 'json',
            'dspace_token' => $login_token,
            });

        my $comm_struct;
        eval {
            $comm_struct = JSON::decode_json($communities);
        };
        if ($@) {
            Carp::confess("Error parsing json: " . $@);
        }

        foreach my $c (@{$comm_struct}) {
            if ($c->{'name'} eq 'Архив') {
                $target_community = $c;
            }
        }
        
        if (!$target_community) {
            Carp::confess("Community [Архив] doesn't exist and unable to create");
        }
    }

#    print Data::Dumper::Dumper($target_community);
    
    my $collections = SDM::Archive::dspace_rest_call({
        'verb' => 'get',
        'link' => $target_community->{'link'} . "/collections",
        'request' => '{}',
        'request_type' => 'json',
        'dspace_token' => $login_token,
        });
    my $coll_struct;
    eval {
        $coll_struct = JSON::decode_json($collections);
    };
    if ($@) {
        Carp::confess("Error parsing json: " . $@);
    }

#    print Data::Dumper::Dumper($coll_struct);
    my $target_collection;
    foreach my $c (@{$coll_struct}) {
        if ($c->{'name'} eq 'Архив А.Ф. Котс') {
            $target_collection = $c;
        }
    }

    if (!$target_collection) {
        my $new_comm = SDM::Archive::dspace_rest_call({
            'verb' => 'post',
            'link' => $target_community->{'link'} . "/collections",
            'request' => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<collection>
  <name>Архив А.Ф. Котс</name>
  <type></type>
  <copyrightText></copyrightText>
  <introductoryText></introductoryText>
  <shortDescription></shortDescription>
  <sidebarText></sidebarText>
</collection>

',
            'request_type' => 'xml',
            'dspace_token' => $login_token,
            });

        $collections = SDM::Archive::dspace_rest_call({
            'verb' => 'get',
            'link' => $target_community->{'link'} . "/collections",
            'request' => '{}',
            'request_type' => 'json',
            'dspace_token' => $login_token,
            });
        my $coll_struct;
        eval {
            $coll_struct = JSON::decode_json($collections);
        };
        if ($@) {
            Carp::confess("Error parsing json: " . $@);
        }

        foreach my $c (@{$coll_struct}) {
            if ($c->{'name'} eq 'Архив А.Ф. Котс') {
                $target_collection = $c;
            }
        }

        if (!$target_collection) {
            Carp::confess("Collection [Архив А.Ф. Котс] doesn't exist and unable to create");
        }
    }

    print "target collection:\n" . Data::Dumper::Dumper($target_collection);
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
else {
    Carp::confess("Need command line parameter, one of: " . join("\n", "", sort map {"--" . $_} @{$o_names}) . "\n");
}
