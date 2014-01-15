#!/usr/bin/perl

use strict;
use warnings;

$| = 1;
use utf8;
use Data::Dumper;
use IPC::Cmd;
use Getopt::Long;
use Carp;
use File::Path;
use Text::CSV::Hashify;

binmode STDOUT, ':encoding(UTF-8)';
my $o = {};
Getopt::Long::GetOptionsFromArray(\@ARGV, $o,
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
    );

Carp::confess("Need --input-file")
    unless $o->{'input-file'};
Carp::confess("--extract-authors and --check-authors are mutually exclusive")
    if $o->{'extract-authors'} && $o->{'check-authors'};
Carp::confess("--extract-authors|--check-authors mode needs only --input-file")
    if ($o->{'extract-authors'} || $o->{'check-authors'}) &&
       ($o->{'output-dir'} || $o->{'output-metadata-tsv'} || $o->{'target-collection-handle'});
Carp::confess("Need --output-dir or --output-metadata-tsv")
    unless $o->{'check-authors'} || $o->{'extract-authors'} || $o->{'output-dir'} || $o->{'output-metadata-tsv'};
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

if ($o->{'include-collection-ids'}) {
    $o->{'include-collection-ids'} =~ s/-/\//g;
    $o->{'include-collection-ids'} =~ s/of\//ОФ-/g;
    $o->{'include-collection-ids'} =~ s/nvf\//НВФ-/g;
  
#    print "matching against [$o->{'include-collection-ids'}]\n";
}

# read xls output and populate $list
my $list = [];
my $fh;
open($fh, "<" . $o->{'input-file'}) || Carp::confess("Can't open [$o->{'input-file'}] for reading");
binmode $fh, ':encoding(UTF-8)';
while (my $l = <$fh>) {
    push @{$list}, $l;
}
close($fh);

my $output_fh;
if ($o->{'output-metadata-tsv'}) {
    open($output_fh, ">" . $o->{'output-metadata-tsv'}) ||
            Carp::confess("unable to write to [" . $o->{'output-metadata-tsv'} . "]");
    binmode $output_fh, ':encoding(UTF-8)';

    # header
    print $output_fh "id,collection,dc.contributor.author[eng],dc.contributor.author[rus],dc.creator[eng],dc.creator[rus],dc.date.accessioned,dc.date.available,dc.date.created[eng],dc.description.provenance[en],dc.description[rus],dc.identifier.other[rus],dc.identifier.uri,dc.language.iso[eng],dc.publisher[eng],dc.publisher[rus],dc.subject[rus],dc.title[rus],dc.type[eng]\n";
}

my $afk_status_def = [qw/
    date_of_status
    status
    number_of_pages
    id
    of_number
    nvf_number
    number_suffix
    storage_number
    doc_id
    classification_code
    doc_name
    doc_property_full
    doc_property_genuine
    doc_type
    doc_date
    doc_desc
    archive_date
    /];

my $dspace_metadata_export = [qw/
id
collection
dc.contributor.author[eng]
dc.contributor.author[rus]
dc.creator[eng]
dc.creator[rus]
dc.date.accessioned
dc.date.available
dc.date.created[eng]
dc.description.provenance[en]
dc.description[rus]
dc.identifier.other[rus]
dc.identifier.uri
dc.language.iso[eng]
dc.publisher[eng]
dc.publisher[rus]
dc.subject[rus]
dc.title[rus]
dc.type[eng]
    /];

my $description_labels = {
    'doc_property_full' => 'Полнота: ',
    'doc_property_genuine' => 'Подлинность: ',
    'doc_type' => 'Способ воспроизведения: ',
    'doc_desc' => 'Примечания: ',
    };
my $authors_canonical = {
"Barlow N." => [
    {"name" => "Emma Nora Barlow", "lang" => "eng"},
    ],
"Edwards W.N." => [
    {"name" => "Wilfred Norman Edwards", "lang" => "eng"},
    ],
"Артоболевский В.М." => ["Владимир Михайлович Артоболевский", ],
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
"Игнатьева В.Н." => [],
"Кожевников Г.А." => [],
"Конёнкова М.И." => [],
"Конюс А.Г." => [],
"Котс А." => [
    "Александр Федорович Котс",
    {"name" => "Alexander Erich Kohts (Coates)", "lang" => "eng"},
    ],
"Котс А.Р." => ["Александр Рудольфович Котс"],
"Котс А.Ф." => [
    "Александр Федорович Котс",
    {"name" => "Alexander Erich Kohts (Coates)", "lang" => "eng"},
    ],
"Котс Р.А." => [
    "Рудольф Александрович Котс",
    {"name" => "Rudolf (Roody) Alfred Kohts", "lang" => "eng"},
    ],
"Крупская Н.К." => [],
"Крушинский Л.В." => [],
"Ладыгина - Котс Н.Н." => [
    "Надежда Николаевна Ладыгина-Котс",
    {"name" => "Nadezhda Ladygina-Kohts", "lang" => "eng"},
    ],
"Лоренц Ф.К." => [],
"Малахова М.Ф." => [],
"Минцлова А.Р." => [],
"Муцетони В.М." => [],
"Неизвестный автор" => [
    "Неизвестный автор",
    {"name" => "Unknown author", "lang" => "eng"},
    ],
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
    };

# find dspace handle by afk_status_of_nvf_number
my $map = {
    };
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

my $id = 0;

DOCUMENT: foreach my $line (@{$list}) {
    my $line_array = [split("\t", $line, -1)];
    my $line_struct = {};
    my $i = 0;
    foreach my $fvalue (@{$line_array}) {
        $line_struct->{$afk_status_def->[$i]} = $fvalue;
        $i++;
    }

    # skip title
    next if $line_struct->{'date_of_status'} eq 'date of status';

    $id++;

    # the order is important, $doc_name is repeatedly transformed and cropped at the right side
    my $doc_name = $line_struct->{'doc_name'};
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

        if ($line_struct->{'doc_type'}) {
            $line_struct->{'doc_type'} .= ", " . $doc_type_extracted;
        }       
        else {
            $line_struct->{'doc_type'} = $doc_type_extracted;
        }
    }
    if ($doc_name =~ /^(.+)Описание:(.+?)$/) {
        $doc_name = $1;
        my $doc_desc = $2;
        $doc_desc =~ s/\s+$//;
        $doc_desc =~ s/^\s+?//;
        $doc_desc =~ s/\s\s/ /g;

        if ($line_struct->{'doc_desc'}) {
            $line_struct->{'doc_desc'} .= ", " . $doc_desc;
        }
        else {
            $line_struct->{'doc_desc'} = $doc_desc;
        }
    }
    if ($doc_name =~ /^(.+)Время создания:(.+?)$/) {
        $doc_name = $1;
        my $doc_date = $2;
        $doc_date =~ s/\s+$//;
        $doc_date =~ s/^\s+?//;
        $doc_date =~ s/\s\s/ /g;

        if ($line_struct->{'doc_date'}) {
            $line_struct->{'doc_date'} .= ", " . $doc_date;
        }
        else {
            $line_struct->{'doc_date'} = $doc_date;
        }
    }
    
    my $doc_authors = [];
    while ($doc_name && $doc_name =~ /^Автор:\s([Нн]еизвестный\sавтор|Ладыгина\s\-\sКотс\sН.\s?Н.|[^\s]+?\s+?([^\s]?\.?\s?[^\s]?\.?|))(\s|,)(.+)$/) {
        my $author = $1;
        $doc_name = $3;
        
        if ($o->{'extract-authors'}) {
            print $1 . "\n";
        }
        elsif ($o->{'check-authors'}) {
            if (!$authors_canonical->{$author}) {
                print "unknown author: [$author]\n";
            }
        }
        else {
            if ($authors_canonical->{$author}) {
                foreach my $a_struct (@{$authors_canonical->{$author}}) {
                    if (ref($a_struct) eq '') {
                        push @{$doc_authors}, {"name" => $a_struct, "lang" => "rus"};
                    }
                    else {
                        push @{$doc_authors}, $a_struct;
                    }
                }
            }
            else {
                push @{$doc_authors}, {"name" => $author, "lang" => "rus"};
            }
        }
    }
    if (!scalar(@{$doc_authors})) {
        push @{$doc_authors}, {"name" => "Александр Федорович Котс", "lang" => "rus"}, {"name" => "Alexander Erich Kohts (Coates)", "lang" => "eng"};
    }

    $doc_name =~ s/^\s+//;
    $doc_name =~ s/\s+$//;
    $doc_name =~ s/\s\s/ /g;

    if ($line_struct->{'doc_date'} =~ /^[\[]*(\d\d\d\d)[\]]*$/) {
        $line_struct->{'doc_date'} = $1;
    }
    if ($line_struct->{'doc_date'} =~ /^\s*$/) {
        $line_struct->{'doc_date'} = "unknown";
    }

    my $collection_identifier;
    if ($line_struct->{'of_number'}) {
        $collection_identifier = "ОФ-" . $line_struct->{'of_number'} .
            ($line_struct->{'number_suffix'} ? "/" . $line_struct->{'number_suffix'} : "");
    }
    elsif ($line_struct->{'nvf_number'}) {
        $collection_identifier = "НВФ-" . $line_struct->{'nvf_number'} .
            ($line_struct->{'number_suffix'} ? "/" . $line_struct->{'number_suffix'} : "");
    }
#    else {
#        Carp::confess("No of_number and no nvf_number: " . Data::Dumper::Dumper($line_struct));
#    }

    # filter out only those which we need
    if ($o->{'include-collection-ids'}) {
        if ($collection_identifier) {
            if ($o->{'include-collection-ids'} !~ /\b$collection_identifier\b/) {
                next DOCUMENT;
            }
            else {
            }
        }
        else {
            next DOCUMENT;
        }
    }

    # "dspace import" mode, generates directory with subdirectory containing dublin_core.xml,
    # doesn't account for multiple authorship
    if ($o->{'output-dir'}) {
        my $descriptions = [];
        foreach my $f (qw/doc_property_full doc_property_genuine doc_type doc_desc/) {
            if ($line_struct->{$f} && $line_struct->{$f} !~ /^\s*$/) {
                push @{$descriptions}, '
  <dcvalue element="description" qualifier="none" language="rus">' . $description_labels->{$f} . $line_struct->{$f} . '</dcvalue>';
            }
        }

        my $dc_filepath = $o->{'output-dir'} . "/" . sprintf("%05d", $id);
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
  <dcvalue element="date" qualifier="created" language="eng">' . $line_struct->{'doc_date'} . '</dcvalue>' .
    ($line_struct->{'storage_number'} ? '
  <dcvalue element="identifier" qualifier="other" language="rus">Место хранения: ' . $line_struct->{'storage_number'} . '</dcvalue>' : "") . 
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
    }
    elsif ($o->{'output-metadata-tsv'}) {
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
            if ($line_struct->{$f} && $line_struct->{$f} !~ /^\s*$/) {
                push @{$descriptions}, $description_labels->{$f} . $line_struct->{$f};
            }
        }

        my $identifiers = [];
        if ($line_struct->{'storage_number'}) {
            push @{$identifiers}, "Место хранения: " . $line_struct->{'storage_number'};
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
            $line_struct->{'doc_date'},
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
    }
}

if ($o->{'output-metadata-tsv'}) {
    close($output_fh);
}
