#!/usr/bin/perl
#
# This is a utility program intended to convert tab separated dump
# of contents of A.E. Kohts archives (which has been tracked
# in several external systems) into TSV text file ready to be imported
# into DSpace.
#
# Subset of Dublin Core metadata fields are populated together
# with SDM specific metadata fields. Schema for these SDM specific
# metadata fields should be loaded into DSpace prior to the import
# of TSV generated by this utility.
#
# There are two main modes of operation of the utility: initial import
# and mass update of metadata in external system with consequent
# update of information in DSpace. First mode implies that DSpace
# database is empty (at least it should not contain any information
# about the items which are being loaded from external system),
# while in the second mode this utility should produce TSV
# which will update already existing items.
#
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
# A.E. Kohts SDM archives items are also uniquely identified, historically
# archives were catalogued in two takes.
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

use strict;
use warnings;

use utf8;

use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

# Data::Dumper to output UTF-8
# http://www.perlmonks.org/?node_id=759457
$Data::Dumper::Useqq = 1;
{
    no warnings 'redefine';
    sub Data::Dumper::qquote {
        my $s = shift;
        return "'$s'";
    }
}

use IPC::Cmd;
use Getopt::Long;
use Carp;
use File::Path;
use Text::CSV::Hashify;

# unbuffered output
$| = 1;

binmode(STDOUT, ':encoding(UTF-8)');

my $o_names = [
    'input-file=s',
    'output-dir=s',
    'output-metadata-tsv=s',
    'include-collection-ids=s',
    'target-collection-handle=s',
    'map-file=s',
    'extract-authors',
    'check-authors',
    'add-items',
    'add-not-in-map',
    'dump-titles',
    'dump-tsv-raw',
    'dump-tsv-struct',
    'dump-storage-stats',
    'dump-titles-by-storage-number=s',
    'dump-data-desc',
    ];
my $o = {};
Getopt::Long::GetOptionsFromArray(\@ARGV, $o, @{$o_names});

my $description_labels = {
    'doc_property_full' => 'Полнота: ',
    'doc_property_genuine' => 'Подлинность: ',
    'doc_type' => 'Способ воспроизведения: ',
    'doc_desc' => 'Примечания: ',
    };

my $data_desc_struct = {
    'external_archive_storage_base' => 'c:/_gdm/raw-afk',    

    'input_tsv_fields' => [qw/
        date_of_status
        status
        number_of_pages
        id
        of_number
        nvf_number
        number_suffix
        storage_number
        scanned_doc_id
        classification_code
        doc_name
        doc_property_full
        doc_property_genuine
        doc_type
        doc_date
        doc_desc
        archive_date
        /],

    'authors_canonical' => {
        "Barlow N." => [ {"name" => "Barlow, Emma Nora", "lang" => "eng"}, ],
        "Edwards W.N." => [ {"name" => "Edwards, Wilfred Norman", "lang" => "eng"}, ],
        "Артоболевский В.М." => [ "Артоболевский, Владимир Михайлович", ],
        "Белоголовый Ю.А." => [],
        "Берг А.Н." => [],
        "Биашвили В.Я." => [],
        "Бобринский Н.А." => [],
        "Бунчур А.," => [],
        "Бутурлин С.А." => [],
        "Васильев Е.Н." => [],
        "Ватагин В.А." => [],
        "Волкац Д.С." => [],
        "Голиков А." => [],
        "Дембовский Я.К." => [],
        "Дементьев Г.П." => [],
        "Дробыш А." => [],
        "Дурова-Садовская А.В." => [],
        "Жандармов А.П." => [],
        "Железнякова О.У." => [],
        "Житков Б.М." => [],
        "Завадовский Б.М." => [],
        "Захаров В." => [],
        "Игнатьева В.Н." => [],
        "Кожевников Г.А." => [],
        "Конёнкова М.И." => [],
        "Конюс А.Г." => [],
        "Котс А." => [ "Котс, Александр Федорович", {"name" => "Kohts (Coates), Alexander Erich", "lang" => "eng"}, ],
        "Котс А.Р." => ["Котс, Александр Рудольфович"],
        "Котс А.Ф." => [ "Котс, Александр Федорович", {"name" => "Kohts (Coates), Alexander Erich", "lang" => "eng"}, ],
        "Котс Р.А." => [ "Котс, Рудольф Александрович", {"name" => "Kohts, Rudolf (Roody) Alfred", "lang" => "eng"}, ],
        "Крупская Н.К." => [ "Крупская, Надежда Константиновна", ],
        "Крушинский Л.В." => [],
        "Ладыгина - Котс Н.Н." => [ "Ладыгина-Котс, Надежда Николаевна", {"name" => "Ladygina-Kohts, Nadezhda Nikolaevna", "lang" => "eng"}, ],
        "Лоренц Ф.К." => [],
        "Малахова М.Ф." => [],
        "Минцлова А.Р." => [],
        "Муцетони В.М." => [],
        "Неизвестный автор" => [ "Неизвестный автор", {"name" => "Unknown author", "lang" => "eng"}, ],
        "Песков В.М." => [],
        "Петров Ф.Н." => [],
        "Полосатова Е.В." => [],
        "Потапов М.М." => [],
        "Псахис Б.С." => [],
        "Пупершлаг Е.А." => [],
        "Рейнвальд Л.Л." => [],
        "Сироткин М.A." => [],
        "Слудский А.А." => [],
        "Смолин П.П." => [],
        "Сосновский И.П." => [],
        "Спангенберг Е.П." => [],
        "Суворов И.П." => [],
        "Сукачев В.Н." => [],
        "Туров С.С." => [],
        "Фабри К.Э." => [],
        "Федулов Ф.Е." => [],
        "Хануков А." => [],
        "Хахлов В.А." => [],
        "Цингер В.Я." => [],
        "Чибисов Н.Е." => [],
        "Шиллингер Ф.Ф." => [],
        "Шперлинг М." => [],
        "Штернберг П.К." => [],
        },
    
    'storage_groups' => {
        1 => {
            'name' => 'Novikova',
            'funds' => [qw/
                           1237
                           1363 1364 1365 1366 1367 1368
                           2116
                           6912
                           9595 9596 9597 9598 9599 9600 9601 9602 9603 9604 9605 9606 9607 9608 9609
                           9626 9649 9650 9651 9662 9664
                           9749 9764 9765 9766 9767 9771 9774 9775 9776 9768 9772 9773 
                           10109
                           10141
                           10621
                           12430 12497
                           /],
        },
        2 => {
            'name' => 'Kalacheva',
            'funds' => ['15845'],
            },
        },
    };

$data_desc_struct->{'storage_groups_by_fund_number'} = {};
$data_desc_struct->{'storage_groups_by_name'} = {};

foreach my $st_gr_id (keys %{$data_desc_struct->{'storage_groups'}}) {
    Carp::confess("storage group name must be unique")
        if $data_desc_struct->{'storage_groups_by_name'}->{$data_desc_struct->{'storage_groups'}->{$st_gr_id}->{'name'}};
    
    $data_desc_struct->{'storage_groups'}->{$st_gr_id}->{'id'} = $st_gr_id;
    $data_desc_struct->{'storage_groups_by_name'}->{$data_desc_struct->{'storage_groups'}->{$st_gr_id}->{'name'}} =
        $data_desc_struct->{'storage_groups'}->{$st_gr_id};
    
    foreach my $fund_id (@{$data_desc_struct->{'storage_groups'}->{$st_gr_id}->{'funds'}}) {
        if ($data_desc_struct->{'storage_groups_by_fund_number'}->{$fund_id}) {
            Carp::confess("Fund [$fund_id] used more than once, please fix");
        }

        $data_desc_struct->{'storage_groups_by_fund_number'}->{$fund_id} = $st_gr_id;
    }
}

sub tsv_read_and_validate {
    my ($input_file, $o) = @_;

    $o = {} unless $o;

    my $doc_struct = {
        'array' => [],
        'by_line_number' => {},
        'by_storage' => {},
        'funds' => {},
        'storage_items_by_fund_number' => {},
        'title_line' => {},
        'total_input_lines' => 0,
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

        my $line_struct = {
            'field_values_array' => [split("\t", $line, -1)],
            'by_field_name' => {},
            };

        my $i = 0;
        foreach my $fvalue (@{$line_struct->{'field_values_array'}}) {
            $fvalue =~ s/\s+$//s;
            $line_struct->{'by_field_name'}->{$data_desc_struct->{'input_tsv_fields'}->[$i]} = $fvalue;
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

    return $doc_struct;
}

if ($o->{'dump-data-desc'}) {
    print Data::Dumper::Dumper($data_desc_struct);
    exit 0;
} elsif ($o->{'dump-tsv-struct'}) {
    Carp::confess("Need --input-file") unless $o->{'input-file'};

    my $in_doc_struct = tsv_read_and_validate($o->{'input-file'});

    print Data::Dumper::Dumper($in_doc_struct);
    print "total number of input lines: " . $in_doc_struct->{'total_input_lines'} . "\n";
    print "total data lines: " . scalar(@{$in_doc_struct->{'array'}}) . "\n";
    foreach my $st_gr_id (sort keys %{$in_doc_struct->{'by_storage'}}) {
        print "total items in storage group [$st_gr_id]: " . scalar(keys %{$in_doc_struct->{'by_storage'}->{$st_gr_id}}) . "\n";
    }

    foreach my $fund_number (sort {$a <=> $b} keys %{$in_doc_struct->{'storage_items_by_fund_number'}}) {
        print uc($in_doc_struct->{'funds'}->{$fund_number}->{'type'}) . " " . $fund_number . ": " .
            scalar(keys %{$in_doc_struct->{'storage_items_by_fund_number'}->{$fund_number}}) . " storage items\n";
    }

    foreach my $st_gr_id (keys %{$in_doc_struct->{'by_storage'}}) {
        foreach my $storage_number (sort {$a <=> $b} keys %{$in_doc_struct->{'by_storage'}->{$st_gr_id}}) {
            my $storage_struct = $in_doc_struct->{'by_storage'}->{$st_gr_id}->{$storage_number};
            
            # - detect and store storage paths here against $data_desc_struct->{'external_archive_storage_base'}
            # - check "scanned" status (should be identical for all the documents in the storage item)
            print Data::Dumper::Dumper($storage_struct);
            adfsdfdexit;

            my $storage_items;
            my $status = "not scanned";

            my $scanned_doc_id;
            STORAGE_ITEM: foreach my $item (@{$in_doc_struct->{'by_storage'}->{$st_gr_id}->{$storage_number}}) {
                if ($item->{'by_field_name'}->{'status'} eq 'scanned' ||
                    $item->{'by_field_name'}->{'status'} eq 'ocr' ||
                    $item->{'by_field_name'}->{'status'} eq 'docbook') {
                    
                    if ($scanned_doc_id && $item->{'by_field_name'}->{'scanned_doc_id'} ne $scanned_doc_id) {
                        $scanned_doc_id = undef;
                        last STORAGE_ITEM;
                    }

                    $scanned_doc_id = $item->{'by_field_name'}->{'scanned_doc_id'};
                    $status = "scanned";
                } else {
                    $scanned_doc_id = undef;
                    last STORAGE_ITEM;
                }
            }

            if ($scanned_doc_id) {
                $storage_items = 1;
            } else {
                $storage_items = scalar(@{$in_doc_struct->{'by_storage'}->{$st_gr_id}->{$storage_number}});
            }

            if ($o->{'dump-storage-stats'}) {
                print "storage group [$st_gr_id] storage number [$storage_number] ($status): " . $storage_items . " item" .
                    ($storage_items > 1 ? "s" : "") . "\n";
            }
        }
    }
} else {
    Carp::confess("--extract-authors and --check-authors are mutually exclusive")
        if $o->{'extract-authors'} && $o->{'check-authors'};
    Carp::confess("--extract-authors|--check-authors mode needs only --input-file")
        if ($o->{'extract-authors'} || $o->{'check-authors'}) &&
           ($o->{'output-dir'} || $o->{'output-metadata-tsv'} || $o->{'target-collection-handle'});

    Carp::confess("Need one of: --output-dir, --output-metadata-tsv, --check-authors, --extract-authors, " .
        "--dump-titles, --dump-tsv-raw, --dump-storage-stats")
        unless
            $o->{'check-authors'} || $o->{'extract-authors'} ||
            $o->{'output-dir'} || $o->{'output-metadata-tsv'} ||
            $o->{'dump-titles'} || $o->{'dump-tsv-raw'} ||
            $o->{'dump-storage-stats'} || $o->{'dump-titles-by-storage-number'};

    Carp::confess("--output-dir and --output-metadata-tsv are mutually exclusive")
        if $o->{'output-dir'} && $o->{'output-metadata-tsv'};
    Carp::confess("Output directory [$o->{'output-dir'}] must not exist")
        if $o->{'output-dir'} && -d $o->{'output-dir'};
    Carp::confess("Output metadata file [$o->{'output-metadata-tsv'}] must not exist")
        if $o->{'output-metadata-tsv'} && -e $o->{'output-metadata-tsv'};
    Carp::confess("metadata --add-items mode needs --target-collection-handle")
        if $o->{'output-metadata-tsv'} && $o->{'add-items'} && ! $o->{'target-collection-handle'};

    Carp::confess("--add-items and --map-file don't work with --output-dir yet")
        if $o->{'output_dir'} && ($o->{'add-items'} || $o->{'map-file'});
    Carp::confess("--add-items and --map-file are mutually exclusive")
        if $o->{'add-items'} && $o->{'map-file'};
    Carp::confess("metadata mode needs --add-items or --map-file")
        if $o->{'output-metadata-tsv'} && ! $o->{'add-items'} && ! $o->{'map-file'};
    Carp::confess("--map-file [$o->{'map-file'}] must exist")
        if $o->{'map-file'} && ! -e $o->{'map-file'};
    Carp::confess("--add-not-in-map is an option of --map-file which was not specified")
        if $o->{'add-not-in-map'} && !$o->{'map-file'};

    my $output_fh;
    if ($o->{'output-metadata-tsv'}) {
        open($output_fh, ">" . $o->{'output-metadata-tsv'}) ||
                Carp::confess("unable to write to [" . $o->{'output-metadata-tsv'} . "]");
        binmode($output_fh, ':encoding(UTF-8)');

        # header
        print $output_fh "id,collection,dc.contributor.author[eng],dc.contributor.author[rus],dc.creator[eng],dc.creator[rus],dc.date.accessioned,dc.date.available,dc.date.created[eng],dc.description.provenance[en],dc.description[rus],dc.identifier.other[rus],dc.identifier.uri,dc.language.iso[eng],dc.publisher[eng],dc.publisher[rus],dc.subject[rus],dc.title[rus],dc.type[eng]\n";
    }

    # find dspace handle by afk_status_of_nvf_number
    my $map = {};
    if ($o->{'map-file'}) {
        my $map_hash = Text::CSV::Hashify->new({
            'file' => $o->{'map-file'},
            'format' => 'aoh',
            });

        foreach my $d (@{$map_hash->all()}) {
            next unless $d->{'dc.identifier.other[rus]'};

            my ($storage_number, $of_nvf_id) = split(/\|\|/, $d->{'dc.identifier.other[rus]'}, -1);
            next unless $of_nvf_id;

            my $handle = $d->{'dc.identifier.uri'};
            $handle =~ s%http://hdl.handle.net/%%;

            $map->{$of_nvf_id} = {
                'id' => $d->{'id'},
                'handle' => $handle,
                'dspace_storage' => $storage_number,
                'orig_obj' => $d,
                };
        }
    }

    my $in_doc_struct = tsv_read_and_validate($o->{'input-file'});

    my $line_number = 0;
    LINE_STRUCT: foreach my $line_struct (@{$in_doc_struct->{'array'}}) {
        $line_number++;

        # the order is important, $doc_name is repeatedly transformed and cropped at the right side
        my $doc_name = $line_struct->{'by_field_name'}->{'doc_name'};
        $doc_name =~ s/""/"/g;
        $doc_name =~ s/^"//;
        $doc_name =~ s/"$//;
        $doc_name =~ s/^Котс А.Ф.//;
        $doc_name =~ s/\s\,\s/\, /g;
        $doc_name =~ s/\s\:\s/\: /g;
        $doc_name =~ s/\s\;\s/\; /g;
        $doc_name =~ s/\s\./\./g;
        $doc_name =~ s/\&/\&amp\;/g;
        $doc_name =~ s/^\s+//;
        $doc_name =~ s/\s+$//;
        $doc_name =~ s/\s\s/ /g;

        if ($doc_name =~ /^(.+)Техника:(.+?)$/) {
            $doc_name = $1;
            my $doc_type_extracted = $2;
            $doc_type_extracted =~ s/\s+$//;
            $doc_type_extracted =~ s/^\s+?//;
            $doc_type_extracted =~ s/\s\s/ /g;

            if ($line_struct->{'by_field_name'}->{'doc_type'}) {
                $line_struct->{'by_field_name'}->{'doc_type'} .= ", " . $doc_type_extracted;
            }       
            else {
                $line_struct->{'by_field_name'}->{'doc_type'} = $doc_type_extracted;
            }
        }
        if ($doc_name =~ /^(.+)Описание:(.+?)$/) {
            $doc_name = $1;
            my $doc_desc = $2;
            $doc_desc =~ s/\s+$//;
            $doc_desc =~ s/^\s+?//;
            $doc_desc =~ s/\s\s/ /g;

            if ($line_struct->{'by_field_name'}->{'doc_desc'}) {
                $line_struct->{'by_field_name'}->{'doc_desc'} .= ", " . $doc_desc;
            }
            else {
                $line_struct->{'by_field_name'}->{'doc_desc'} = $doc_desc;
            }
        }
        if ($doc_name =~ /^(.+)Время создания:(.+?)$/) {
            $doc_name = $1;
            my $doc_date = $2;
            $doc_date =~ s/\s+$//;
            $doc_date =~ s/^\s+?//;
            $doc_date =~ s/\s\s/ /g;

            if ($line_struct->{'by_field_name'}->{'doc_date'}) {
                $line_struct->{'by_field_name'}->{'doc_date'} .= ", " . $doc_date;
            } else {
                $line_struct->{'by_field_name'}->{'doc_date'} = $doc_date;
            }
        }
        
        my $doc_authors = [];
        while ($doc_name && $doc_name =~ /^Автор:\s([Нн]еизвестный\sавтор|Ладыгина\s*?\-\s*?Котс\s?Н.\s?Н.|[^\s]+?\s+?([^\s]?\.?\s?[^\s]?\.?|))(\s|,)(.+)$/) {
            my $author = $1;
            $doc_name = $4;
            
            if ($o->{'extract-authors'}) {
                print $1 . "\n";
            }
            elsif ($o->{'check-authors'}) {
                if (!$data_desc_struct->{'authors_canonical'}->{$author}) {
                    print "unknown author: [$author]\n";
                }
            }
            else {
                if ($data_desc_struct->{'authors_canonical'}->{$author}) {
                    foreach my $a_struct (@{$data_desc_struct->{'authors_canonical'}->{$author}}) {
                        if (ref($a_struct) eq '') {
                            push @{$doc_authors}, {"name" => $a_struct, "lang" => "rus"};
                        }
                        else {
                            push @{$doc_authors}, $a_struct;
                        }
                    }
                }
                else {
                    if ($author =~ /^([^\.]+?)\s+?(.*)$/) {
                        my ($lastname, $othername) = ($1, $2);
                        push @{$doc_authors}, {"name" => $lastname . ", " . $othername, "lang" => "rus"};
                    } else {
                        push @{$doc_authors}, {"name" => $author, "lang" => "rus"};
                    }
                }
            }
        }
        if (!scalar(@{$doc_authors})) {
            push @{$doc_authors}, {"name" => "Александр Федорович Котс", "lang" => "rus"}, {"name" => "Alexander Erich Kohts (Coates)", "lang" => "eng"};
        }

        $doc_name =~ s/^\s+//;
        $doc_name =~ s/\s+$//;
        $doc_name =~ s/\s\s/ /g;

        if ($line_struct->{'by_field_name'}->{'doc_date'} =~ /^[\[]*(\d\d\d\d)[\]]*$/) {
            $line_struct->{'by_field_name'}->{'doc_date'} = $1;
        }
        if ($line_struct->{'by_field_name'}->{'doc_date'} =~ /^\s*$/) {
            $line_struct->{'by_field_name'}->{'doc_date'} = "unknown";
        }

        my $collection_identifier;
        if ($line_struct->{'by_field_name'}->{'of_number'}) {
            $collection_identifier = "ОФ-" . $line_struct->{'by_field_name'}->{'of_number'} .
                ($line_struct->{'by_field_name'}->{'number_suffix'} ? "/" . $line_struct->{'by_field_name'}->{'number_suffix'} : "");
        } elsif ($line_struct->{'by_field_name'}->{'nvf_number'}) {
            $collection_identifier = "НВФ-" . $line_struct->{'by_field_name'}->{'nvf_number'} .
                ($line_struct->{'by_field_name'}->{'number_suffix'} ? "/" . $line_struct->{'by_field_name'}->{'number_suffix'} : "");
        }
    #    else {
    #        Carp::confess("No of_number and no nvf_number: " . Data::Dumper::Dumper($line_struct));
    #    }

        # filter out only those which we need
        if ($o->{'include-collection-ids'}) {
            if ($collection_identifier) {
                if ($o->{'include-collection-ids'} !~ /\b$collection_identifier\b/) {
                    next LINE_STRUCT;
                } else {
                }
            } else {
                next LINE_STRUCT;
            }
        }

        # "dspace import" mode, generates directory with subdirectory containing dublin_core.xml,
        # doesn't account for multiple authorship
        if ($o->{'output-dir'}) {
            my $descriptions = [];
            foreach my $f (qw/doc_property_full doc_property_genuine doc_type doc_desc/) {
                if ($line_struct->{'by_field_name'}->{$f} && $line_struct->{'by_field_name'}->{$f} !~ /^\s*$/) {
                    push @{$descriptions}, '
      <dcvalue element="description" qualifier="none" language="rus">' . $description_labels->{$f} . $line_struct->{'by_field_name'}->{$f} . '</dcvalue>';
                }
            }

            my $dc_filepath = $o->{'output-dir'} . "/" . sprintf("%05d", $line_number);
            File::Path::make_path($dc_filepath);
            open($output_fh, ">" . $dc_filepath . "/dublin_core.xml") ||
                Carp::confess("unable to write to [" . $dc_filepath . "/dublin_core.xml" . "]");
            binmode $output_fh, ':encoding(UTF-8)';

            my $author_xml = "";
            foreach my $a (@{$doc_authors}) {
                $author_xml .= '
      <dcvalue element="contributor" qualifier="author" language="' . $a->{'lang'} . '">' . $a->{'name'} . '</dcvalue>
      <dcvalue element="creator" qualifier="none" language="' . $a->{'lang'} . '">' . $a->{'name'} . '</dcvalue>';
            }

            print $output_fh '<?xml version="1.0" encoding="utf-8" standalone="no"?>
    <dublin_core schema="dc">' . $author_xml . '
      <dcvalue element="date" qualifier="created" language="eng">' . $line_struct->{'by_field_name'}->{'doc_date'} . '</dcvalue>' .
        ($line_struct->{'by_field_name'}->{'storage_number'} ? '
      <dcvalue element="identifier" qualifier="other" language="rus">Место хранения: ' . $line_struct->{'by_field_name'}->{'storage_number'} . '</dcvalue>' : "") . 
        ($collection_identifier ? '
      <dcvalue element="identifier" qualifier="other" language="rus">' . $collection_identifier . '</dcvalue>' : "") .
        join("", @{$descriptions}) . '
      <dcvalue element="language" qualifier="iso" language="eng">rus</dcvalue>
      <dcvalue element="publisher" qualifier="none" language="eng">State Darwin Museum</dcvalue>
      <dcvalue element="publisher" qualifier="none" language="rus">Государственный Дарвиновский Музей</dcvalue>
      <dcvalue element="subject" qualifier="none" language="rus">Музейное дело</dcvalue>
      <dcvalue element="title" qualifier="none" language="rus">' . $doc_name . '</dcvalue>
      <dcvalue element="type" qualifier="none" language="eng">Text</dcvalue>
    </dublin_core>
    ';
            close($output_fh);
        } elsif ($o->{'output-metadata-tsv'}) {
            my $author_rus = [];
            my $author_eng = [];
            foreach my $a (@{$doc_authors}) {
                if ($a->{'lang'} eq 'eng') {
                    push @{$author_eng}, $a->{'name'};
                }
                else {
                    push @{$author_rus}, $a->{'name'};
                }
            }

            my $descriptions = [];
            foreach my $f (qw/doc_property_full doc_property_genuine doc_type doc_desc/) {
                if ($line_struct->{'by_field_name'}->{$f} && $line_struct->{'by_field_name'}->{$f} !~ /^\s*$/) {
                    push @{$descriptions}, $description_labels->{$f} . $line_struct->{'by_field_name'}->{$f};
                }
            }

            my $identifiers = [];
            if ($line_struct->{'by_field_name'}->{'storage_number'}) {
                push @{$identifiers}, "Место хранения: " . $line_struct->{'by_field_name'}->{'storage_number'};
            }
            if ($collection_identifier) {
                push @{$identifiers}, $collection_identifier;
            }

            if ($o->{'map-file'} && !$map->{$collection_identifier}) {
                if (!$o->{'add-not-in-map'}) {
                    Carp::confess("unable to find [$collection_identifier] in --map-file");
                }
                else {
                    $o->{'prev_add-items'} = $o->{'add-items'};
                    $o->{'add-items'} = 1;
                }
            }
            
            my $record = [
                #id,
                ($o->{'add-items'} ? "+" : $map->{$collection_identifier}->{'id'} || ""),
                #collection,
                ($o->{'add-items'} ? $o->{'target-collection-handle'} : $map->{$collection_identifier}->{'orig_obj'}->{'collection'}),
                #dc.contributor.author[eng],
                #dc.contributor.author[rus],
                #dc.creator[eng],
                #dc.creator[rus],
                join("||", @{$author_eng}),
                join("||", @{$author_rus}),
                join("||", @{$author_eng}),
                join("||", @{$author_rus}),
                #dc.date.accessioned,
                ($o->{'add-items'} ? "" : $map->{$collection_identifier}->{'orig_obj'}->{'dc.date.accessioned'}),
                #dc.date.available,
                ($o->{'add-items'} ? "" : $map->{$collection_identifier}->{'orig_obj'}->{'dc.date.available'}),
                #dc.date.created[eng],
                $line_struct->{'by_field_name'}->{'doc_date'},
                #dc.description.provenance[en],
                ($o->{'add-items'} ? "" : $map->{$collection_identifier}->{'orig_obj'}->{'dc.description.provenance[en]'}),
                #dc.description[rus],
                join("||", @{$descriptions}),
                #dc.identifier.other[rus],
                join("||", @{$identifiers}),
                #dc.identifier.uri,
                ($o->{'add-items'} ? "" : $map->{$collection_identifier}->{'orig_obj'}->{'dc.identifier.uri'}),
                #dc.language.iso[eng],
                "rus",
                #dc.publisher[eng],
                "State Darwin Museum",
                #dc.publisher[rus],
                "Государственный Дарвиновский Музей",
                #dc.subject[rus],
                "Музейное дело",
                #dc.title[rus],
                $doc_name,
                #dc.type[eng]\n";
                "Text",
                ];

            print $output_fh join(",",
                map {my $s = $_ ; $s =~ s/"/""/g; '"' . $s . '"'} @{$record}
                ) . "\n";

            if ($o->{'prev_add-items'}) {
                $o->{'add-items'} = $o->{'prev_add-items'};
                delete($o->{'prev_add-items'});
            }
        } elsif ($o->{'dump-titles'}) {
            print $doc_name . "\n";
        }
    }

    if ($o->{'output-metadata-tsv'}) {
        close($output_fh);
    }
}
