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
#       tsv_to_dspace.pl --validate-tsv --external-tsv /file/name
#   
#   --initial-import
#       convert tab separated dump (UTF-8 encoded) of contents
#       of A.E. Kohts archives (which are tracked in KAMIS in SDM,
#       part of the archive was tracked in DBX file previously)
#       into TSV text file ready to be imported into DSpace
#       (the process relies on custom metadata fields as defined
#       in sdm-archive-workflow.xml schema)
#
#       Usage example (outputs to STDOUT):
#       tsv_to_dspace.pl --initial-import --external-tsv /file/name --target-collection-handle 123456789/2
#
#
#   --build-docbook-for-dspace
#       build html bitstream for the requested docbook file (which
#       should exist in docbook_source_base); this mode should be run
#       before running --import-bitstreams (which then imports
#       bitstreams into DSpace)
#
#       Usage example:
#       tsv_to_dspace.pl --build-docbook-for-dspace --docbook-filename of-15845-0004.docbook
#
#
#   --import-bitstreams
#       - read the list of available bitstreams:
#           * scanned images of documents (external_archive_storage_base)
#           * html files of documents passed through OCR (docbook_dspace_out_base)
#       - match them with items in TSV file
#       - append the items into DSpace exported collection (which was prepared
#         with "dspace export").
#
#       During processing this utility creates symlinks to the bitstream
#       files in item directories and updates "contents" files.
#
#       Usage example:
#       tsv_to_dspace.pl --import-bitstreams --external-tsv /file/name --dspace-exported-collection /pa/th
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
#       define in $data_desc_struct). Produces csv output for dspace
#       with --tsv-output or Dumper struct without.
#       Usage example: tsv_to_dspace.pl --external-tsv afk-status.txt --dump-csv-item '1 1' --tsv-output
#
#     --dump-scanned-docs
#     --dump-ocr-html-docs
#     --dump-docbook-sources
#     --dump-dspace-exported-collection
#       read and dump the prepared structure
#
#     --dump-tsv-struct - reads TSV and outputs whole perl struct which
#       is then used to create output CSV; also outputs some statistics
#       Usage example: tsv_to_dspace.pl --external-tsv afk-status.txt --dump-tsv-struct | less
#
#     --list-storage-items - lists all storage items by storage group
#       and outputs either the number of documents in the storage item
#       or the title.
#       Usage example: tsv_to_dspace.pl --external-tsv afk-status.txt --list-storage-items [--titles]
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

use strict;
use warnings;

use utf8;

use DateTime;
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

use Carp;
use File::Basename;
use File::Path;
use Getopt::Long;
use IPC::Cmd;
use Log::Log4perl;
use Text::CSV;
use XML::Simple;

# unbuffered output
$| = 1;

binmode(STDIN, ':encoding(UTF-8)');
binmode(STDOUT, ':encoding(UTF-8)');

my $runtime = {};
my $o_names = [
    'bash-completion',
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
    ];
my $o = {};
Getopt::Long::GetOptionsFromArray(\@ARGV, $o, @{$o_names});

my $data_desc_struct = {
    
    # These document id(s) are used in different storage items
    # in "Novikova" storage group.
    # 
    # There are several cases:
    #   (1) one logical item occupies several storage items
    #       which is the case of nvf-6912-14;15;16
    #
    #   (2) one item is present in the one storage item and
    #       (seemingly) is not present in the other;
    #       case of of-10141-0450
    #
    #   (3) there are two different items which are referenced
    #       with the same id
    #   
    # (2) could either be the result of error during exchange
    # of documents between storage items (for the reason of more
    # convenient exploration of the archive)
    #
    'known_scanned_documents_included_into_several_storage_items' => [
        'nvf-6912-14;15;16',
        'of-10141-0450', # storage items 726 and 1162
        'nvf-2116-0416', # storage items 161 and 320 (contents are different)
        
        'of-12497-0168', # August 2014: have to be scanned and checked

        ],

    # documents which are associated with the A.E. Kohts archive
    # but are not part of it
    'scanned_documents_without_id' => [
        'dnevnik-mashinistki', # diary of the typist of A.E. Kohts (as presented by I.P. Kalacheva)
        ],

    'external_archive_storage_base' => '/gone/root/raw-afk',
    'external_archive_storage_timezone' => 'Europe/Moscow',

    'docbook_source_base' => '/home/petya/github/kohts/archive/trunk/books/afk-works',
    'docbook_dspace_out_base' => '/var/www/html/OUT/afk-works/html-dspace',

    'dspace.identifier.other[en]-prefix' => 'Storage item',
    'dspace.identifier.other[ru]-prefix' => 'Место хранения',

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
        author_is_aekohts
        /],

    'authors_canonical' => {
        "Артоболевский В.М." => [ "Артоболевский, Владимир Михайлович", ],
        "Афанасьев В.А." => [ "Афанасьев, Виталий Аристархович" ],
        "Бадамшин Б.И." => [ "Бадамшин, Бурган Изъятулович" ],
        "Белоголовый Ю.А." => [ "Белоголовый, Юрий Аполлонович" ],
        "Беляев М.М." => [ "Беляев, Михаил Михайлович", ],
        "Белышев В.А." => [],
        "Берг А.Н." => [],
        "Биашвили В.Я." => [],
        "Бобринский Н.А." => [ "Бобринский, Николай Алексеевич" ],
        "Бунчур А.," => [],
        "Бутурлин С.А." => [],
        "Васильев Е.Н." => [],
        "Варсанофьева В.А." => [ "Варсанофьева, Вера Александровна" ],
        "Ватагин В.А." => [ "Ватагин, Василий Алексеевич", {"name" => "Vatagin, Vasily", "lang" => "en"}, ],
        "Вахромеев К.А." => [ "Вахромеев, Кирилл Альвинович" ],
        "Виноградов Н.В." => [],
        "Волкац Д.С." => [ "Волкац, Дина Соломоновна" ],
        "Воронина М." => [],
        "Вяжлинский Д.М." => [ "Вяжлинский, Дмитрий Михайлович" ],
        "Гавриленко А.А." => [ "Гавриленко, Анатолий Александрович" ],
        "Гептнер В.Г." => [ "Гептнер, Владимир Георгиевич" ],
        "Гладков Н.А." => [],
        "Голиков А." => [],
        "Горшков О.С." => [ "Горшков, Осип Степанович" ],
        "Даценко В.И." => [ "Даценко, Василий Иванович" ],
        "Дембовский Я.К." => [ "Дембовский, Ян Казимирович" ],
        "Дементьев Г.П." => [ "Дементьев, Георгий Петрович" ],
        "Дробыш А." => [],
        "Дубов И.И." => [ "Дубов, Иван Иванович" ],
        "Дурова-Садовская А.В." => [ "Дурова-Садовская, Анна Владимировна" ],
        "Евстафьев В.М." => [ "Евстафьев, Виктор Михайлович" ],
        "Жадовский Н.К." => [ "Жадовский, Николай Константинович" ],
        "Жандармов А.П." => [ "Анжанов (Жандармов), Анатолий Петрович" ],
        "Железнякова О.У." => [],
        "Житков Б.М." => [ "Житков, Борис Михайлович" ],
        "Жуков П.И." => [],
        "Завадовский Б.М." => [ "Завадовский, Борис Михайлович" ],
        "Завадский А.М." => [ "Завадский, Александр Михайлович" ],
        "Захаров В." => [],
        "Зелинский Н.Д." => [ "Зелинский, Николай Дмитриевич" ],
        "Иваницкий И.П." => [ "Иваницкий, Иван Петрович" ],
        "Иванов Н.А." => [ "Иванов, Николай Афанасьевич" ],
        "Игнатьева В.Н." => [ "Игнатьева, Вера Николаевна" ],
        "Кириллова Н.В." => [],
        "Кирпичев С.П." => [ "Кирпичев Сергей Павлович" ],
        "Кожевников Г.А." => [ "Кожевников, Григорий Александрович" ],
        "Козлова Е.В." => [ "Козлова, Елизавета Владимировна" ],
        "Комаров А.Н." => [ "Комаров, Алексей Никанорович" ],
        "Кондаков Н.Н." => [ "Кондаков, Николай Николаевич" ],
        "Конёнкова М.И." => [ "Конёнкова, Маргарита Ивановна" ],
        "Константинов И.П." => [ "Константинов, Иван Петрович" ],
        "Конюс А.Г." => [ "Конюс, Андрей Георгиевич" ],
        "Коржинская О.М." => [ "Коржинская, Ольга Михайловна" ],
        "Котс А." => [ "Котс, Александр Федорович", {"name" => "Kohts (Coates), Alexander Erich", "lang" => "en"}, ],
        "Котс А.Р." => ["Котс, Александр Рудольфович"],
        "Котс А.Ф." => [ "Котс, Александр Федорович", {"name" => "Kohts (Coates), Alexander Erich", "lang" => "en"}, ],
        "Котс Е.А." => [ "Котс (Пупершлаг), Евгения Александровна" ],
        "Котс Р.А." => [ "Котс, Рудольф Александрович", {"name" => "Kohts, Rudolf Alfred", "lang" => "en"}, ],
        "Котс С.Р." => [ "Котс, Сергей Рудольфович" ],
        "Красовский Д.Б." => [ "Красовский, Дмитрий Борисович" ],
        "Крупская Н.К." => [ "Крупская, Надежда Константиновна", ],
        "Крушинский Л.В." => [ "Крушинский, Леонид Викторович" ],
        "Ладыгина-Котс Н.Н." => [ "Ладыгина-Котс, Надежда Николаевна", {"name" => "Ladygina-Kohts, Nadezhda Nikolaevna", "lang" => "en"}, ],
        "Левыкина Н.Ф." => [ "Левыкина, Наталья Федоровна" ],
        "Лейбенгруб П.С." => [],
        "Логинова Н.Я." => [],
        "Лоренц Ф.К." => [ "Лоренц, Фёдор Карлович" ],
        "Лушкин П." => [],
        "Мантейфель П.А." => [ "Мантейфель, Петр Александрович" ],
        "Малахова М.Ф." => [],
        "Мардис П.Е." => [],
        "Медведев Е." => [ "Медведев, Евгений" ],
        "Мензбир М.А." => [ "Мензбир, Михаил Александрович", {"name" => "Menzbier, Mikhail Aleksandrovich", "lang" => "en"}, ],
        "Минцлова А.Р." => [ "Минцлова, Анна Рудольфовна" ],
        "Михно П.С." => [ "Михно, Пётр Саввич" ],
        "Музалевская Н.В." => [ "Музалевская, Надежда Владимировна" ],
        "Муцетони В.М." => [ "Муцетони, Валентина Михайловна" ],
        "Неизвестный автор" => [ "Неизвестный автор", {"name" => "Unknown author", "lang" => "en"}, ],
        "Островский Л.В." => [ "Островский, Лев Владимирович" ],
        "Павловский Е.Н." => [ "Павловский, Евгений Никанорович" ],
        "Песков В.М." => [],
        "Петров Ф.Н." => [ "Петров, Фёдор Николаевич" ],
        "Петряев П.А." => [ "Петряев, Павел Александрович" ],
        "Пичугин А.Н." => [],
        "Плавильщиков Н.Н." => [ "Плавильщиков, Николай Николаевич" ],
        "Полосатова Е.В." => [],
        "Поляков Г.И." => [ "Поляков, Григорий Иванович" ],
        "Полякова Ю.Ф." => [],
        "Портенко Л.А." => [ "Портенко, Леонид Александрович" ],
        "Потапов М.М." => [],
        "Потёмкин В.П." => [ "Потёмкин, Владимир Петрович" ],
        "Псахис Б.С." => [],
        "Пупершлаг Е.А." => [ "Котс (Пупершлаг), Евгения Александровна" ],
        "Рашек В.Л." => [],
        "Рейнвальд Л.Л." => [],
        "Садовникова-Кольцова М.П." => [],
        "Сизова М.И." => [ "Сизова, Магдалина Ивановна" ],
        "Сироткин М.A." => [],
        "Слудский А.А." => [],
        "Смолин П.П." => [ "Смолин, Петр Петрович" ],
        "Соболь С.Л." => [],
        "Соколов И.И." => [],
        "Соляник А.Н." => [],
        "Сосновский И.П." => [ "Сосновский, Игорь Петрович" ],
        "Спангенберг Е.П." => [ "Спангенберг, Евгений Павлович" ],
        "Суворов И.П." => [],
        "Судиловская А.М." => [ "Судиловская, Ангелина Михайловна" ],
        "Сукачев В.Н." => [],
        "Сушкин П.П." => [ "Сушкин, Пётр Петрович" ],
        "Терентьев П.В." => [ "Терентьев, Павел Викторович" ],
        "Толстой С.С." => [ "Толстой, Сергей Сергеевич" ],
        "Туров С.С." => [ "Туров, Сергей Сергеевич" ],
        "Фабри К.Э." => [ "Фабри, Курт Эрнестович" ],
        "Федулов Ф.Е." => [ "Федулов, Филипп Евтихиевич" ],
        "Федулов Д.Я." => [ "Федулов, Дмитрий Яковлевич" ],
        "Федулова Т.Д." => [ "Федулова, Татьяна Дмитриевна" ],
        "Флёров К.К." => [ "Флёров, Константин Константинович" ],
        "Формозов А.Н." => [ "Формозов, Александр Николаевич" ],
        "Хануков А." => [],
        "Хахлов В.А." => [ "Хахлов, Виталий Андреевич" ],
        "Цингер В.Я." => [ "Цингер, Василий Яковлевич" ],
        "Чаплыгин С.А." => [ "Чаплыгин, Сергей Алексеевич" ],
        "Чибисов Н.Е." => [ "Чибисов, Никандр Евлампиевич" ],
        "Чибисова Н.Н." => [],
        "Шиллингер Ф.Ф." => [ "Шиллингер, Франц Францович" ],
        "Шперлинг М." => [],
        "Штернберг П.К." => [ "Штернберг, Павел Карлович" ],
        "Ashby E." => [ {"name" => "Ashby, Eric", "lang" => "en"} ],
        "Atanassov" => [ {"name" => "Atanassov", "lang" => "en"} ],
        "Augusta J." => [ {"name" => "Augusta, Josef", "lang" => "en"} ],
        "Barlow N." => [ {"name" => "Barlow, Emma Nora", "lang" => "en"}, ],
        "Bottcher E.A." => [ {"name" => "Bottcher, Ernst A.", "lang" => "en"} ],
        "Damon R.F." => [ {"name" => "Damon, Robert F.", "lang" => "en"} ],
        "Darwin K." => [ {"name" => "Darwin, Katherine", "lang" => "en"} ],
        "Darwin C." => [ {"name" => "Darwin, Charles", "lang" => "en"} ],
        "Edwards W.N." => [ {"name" => "Edwards, Wilfred Norman", "lang" => "en"}, ],
        "Eimer I.H." => [ {"name" => "Eimer, Ing. Helmut", "lang" => "en"} ],
        "Eimer M." => [ {"name" => "Eimer, Manfred", "lang" => "en"} ],
        "Fock G." => [ {"name" => "Fock, Gustav", "lang" => "en"} ],
        "Gentz K." => [ {"name" => "Gentz, Kurst", "lang" => "en"} ],
        "Hamilton J.G." => [ {"name" => "Hamilton, Joseph Gilbert", "lang" => "en"} ],
        "Huxley J.S." => [ {"name" => "Huxley, Julian Sorell", "lang" => "en"} ],
        "Johannsen" => [ {"name" => "Johannsen", "lang" => "en"} ],
        "Kleinschmidt O." => [ {"name" => "Kleinschmidt, Otto", "lang" => "en"} ],
        "Kohts Amelie" => [ {"name" => "Kohts, Amelie", "lang" => "en"} ],
        "Kohts Elisabeth" => [ {"name" => "Kohts, Elisabeth", "lang" => "en"} ],
        "Von Linden G.M." => [ {"name" => "Von Linden, Grafin Maria", "lang" => "en"} ],
        "Otakar Matousek" => [ {"name" => "Otakar, Matousek", "lang" => "en"} ],
        "De Vries H.M." => [ {"name" => "De Vries, Hugo Marie", "lang" => "en"} ],
        "De Vries R.W.P." => [ {"name" => "De Vries, Reinier Willem Petrus", "lang" => "en"} ],
        "Yerkes A.W." => [ {"name" => "Yerkes, Ada W.", "lang" => "en"} ],
        "Yerkes R.M." => [ {"name" => "Yerkes, Robert Mearns", "lang" => "en"} ],
        },
    
    'storage_groups' => {
        1 => {
            'name' => 'Novikova',
            'name_readable_ru' => 'опись Новиковой Н.А.',
            'name_readable_en' => 'inventory by Novikova N.A.',
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
            'classification_codes' => {
                '1' => 'Научные работы, исследовательские и научно-популярные труды и рабочие материалы к ним',
                '1.1' => 'Исследовательские и научно-популярные работы (статьи, очерки, речи, доклады, лекции)',
                '1.2' => 'Рабочие материалы по ГДМ (история музея, сотрудники, тексты экскурсий, материалы по экспозиции)',
                '1.3' => 'Материалы по новому зданию ГДМ (на Фрунзенской набережной). Описание залов и схемы распланировки экспонатов в проектируемом здании',
                '1.4' => 'Работы по музееведению',
                '1.5' => 'Рецензии и отзывы о работе других лиц, некрологи',
                '2' => 'Материалы служебной и общественной деятельности',
                '2.1' => 'Материалы, связанные с руководством и работой в ГДМ',
                '2.1A' => 'Документы по формированию коллекций музея (счета, договоры, уведомления, накладные и т.п.)',
                '2.2' => 'Материалы о работе в Зоосаде (21.03.1919-20.09.1923)',
                '2.3' => 'Материалы о работе в московских госпиталях (1941-1943)',
                '3' => 'Биографические материалы',
                '3.1' => 'Автобиографические и личные документы',
                '3.2' => 'Юбилейная и поздравительная корреспонденция',
                '3.3' => 'Материалы об А. Ф. Котс (отзывы, воспоминания, характеристики)',
                '4' => 'Переписка',
                '4.1' => 'Переписка с отечественными корреспондентами',
                '4.1A' => 'Переписка с частными корреспондентами',
                '4.1B' => 'Переписка с государственным учреждениями и частными предприятиями',
                '4.1C' => 'Почтовая корреспонденция, касающаяся получения нового здания для ГДМ',
                '4.2' => 'Переписка с зарубежными корреспондентами',
                '4.2A' => 'Переписка с частными корреспондентами',
                '4.2B' => 'Переписка с государственным учреждениями и частными предприятиями (фирмами, магазинами и т.д.)',
                '5' => 'Материалы других лиц (рукописи статей, отзывы, письма)',
                },
            'storage_items' => {
                19 => '"Война и школа" (Как методически связать арену боя с классной комнатой ?). Речь на Конференции педагогов Свердловского р-на г.Москвы 6 января 1945 года.',
                21 => '"Дарвинизм, зоология и школа в дни ВОВ". Лекция для преподавателей - биологов, дважды прочитанная на Конференции педагогов Москвы в январе 1944 года.',
                115 => 'Перечень научных трудов профессора А.Ф. Котс',
                148 => '"..О прошлом человека, о происхождении нас самих"',
                385 => '"К вопросу о структуре и тематике отдела природы в краеведческих музеях". Доклад в Институте МКР в июне 1944 года. Тезисы и резюме докладов о природоведческих музеях',
                473 => '"К биографии Н.А. Бобринского". /Страницы жизни/',
                574 => 'Заявление от охотника Е.Каверзина в адрес ГДМ',
                756 => 'Визитные карточки Александра Федоровича Котс и Надежды Николаевны Ладыгиной-Котс',
                897 => 'Артоболевский Владимир Михайлович, переписка',
                900 => 'Афанасьев Виталий Аристархович, переписка',
                901 => 'Рекомендательные письма',
                902 => 'Бадамшин Бурган Изъятулович, переписка',
                908 => 'Беляев Михаил Михайлович, переписка',
                910 => 'Бобринский Николай Алексеевич, переписка',
                912 => 'Варсанофьева Вера Александровна, переписка',
                914 => 'Ватагин Василий Алексеевич, переписка',
                915 => 'Вахромеев Кирилл Альвинович, переписка',
                921 => 'Волкац Дина Соломоновна, переписка',
                922 => 'Воронина М., переписка',
                925 => 'Гавриленко Анатолий Александрович, переписка',
                930 => 'Горшков Осип Степанович, переписка',
                933 => 'Даценко Василий Иванович, переписка',
                934 => 'Дементьев Георгий Петрович, переписка',
                938 => 'Дубов Иван Иванович, переписка',
                939 => 'Дурова-Садовская Анна Владимировна, переписка',
                940 => 'Евстафьев Виктор Михайлович, переписка',
                942 => 'Жадовский Николай Константинович, переписка',
                945 => 'Жуков П.И., переписка',
                947 => 'Завадовский Борис Михайлович, переписка',
                948 => 'Завадский Александр Михайлович, переписка',
                952 => 'Зелинский Николай Дмитриевич, переписка',
                954 => 'Иваницкий Иван Петрович, переписка',
                956 => 'Иванов Николай Афанасьевич, переписка',
                958 => 'Кирпичев Сергей Павлович, переписка',
                960 => 'Козлова Елизавета Владимировна, переписка',
                961 => 'Комаров Алексей Никанорович, переписка',
                962 => 'Кондаков Николай Николаевич, переписка',
                963 => 'Константинов Иван Петрович, переписка',
                964 => 'Коржинская Ольга Михайловна, переписка',
                968 => 'Котс А.Ф., переписка',
                969 => 'Котс Евгения Александровна, переписка',
                970 => 'Котс Рудольф Александрович, переписка',
                971 => 'Красовский Дмитрий Борисович, переписка',
                978 => 'Ладыгина-Котс Надежда Николаевна',
                980 => 'Лейбенгруб П.С., переписка',
                985 => 'Лушкин П., переписка',
                988 => 'Мантейфель Петр Александрович, переписка',
                992 => 'Медведев Евгений, переписка',
                993 => 'Мензбир Михаил Александрович, переписка',
                995 => 'Минцлова А.Р., переписка',
                996 => 'Михно Пётр Саввич, переписка',
                997 => 'Музалевская Надежда Владимировна, переписка',
                998 => 'Муцетони В.М., переписка',
                1004 => 'Островский Лев Владимирович, переписка',
                1006 => 'Павловский Евгений Никанорович, переписка',
                1010 => 'Петров Фёдор Николаевич, переписка',
                1011 => 'Петряев Павел Александрович, переписка',
                1012 => 'Пичугин А.Н., переписка',
                1017 => 'Поляков Григорий Иванович, переписка',
                1019 => 'Портенко Леонид Александрович, переписка',
                1020 => 'Потёмкин Владимир Петрович, переписка',
                1023 => 'Рашек В.Л., переписка',
                1028 => 'Сизова Магдалина Ивановна, переписка',
                1032 => 'Смолин Пётр Петрович, переписка',
                1034 => 'Соболь С.Л., переписка',
                1035 => 'Соколов И.И., переписка',
                1036 => 'Соляник А.Н., переписка',
                1037 => 'Переписка с московским зоопарком',
                1040 => 'Сукачев В.Н., переписка',
                1042 => 'Сушкин Пётр Петрович, переписка',
                1044 => 'Терентьев Павел Викторович, переписка',
                1047 => 'Толстой С.С., переписка',
                1048 => 'Туров Сергей Сергеевич, переписка',
                1051 => 'Федулов Дмитрий Яковлевич, переписка',
                1052 => 'Федулов Филипп Евтихиевич, переписка',
                1053 => 'Федулова Татьяна Дмитриевна, переписка',
                1054 => 'Флёров Константин Константинович, переписка',
                1055 => 'Формозов Александр Николаевич, переписка',
                1056 => 'Хахлов Виталий Андреевич, переписка',
                1058 => 'Чаплыгин Сергей Алексеевич, переписка',
                1060 => 'Чибисов Никандр Евлампиевич, переписка',
                1063 => 'Шиллингер Ф.Ф., переписка',
                1070 => 'Переписка, Северо-Кавказский Институт Краеведения',
                1075 => 'Переписка, Вадим Михайлович',
                1077 => 'Переписка, Лев Максимович',
                1087 => 'Переписка, неизвестный Сергей из Перми',
                1094 => 'Переписка, неизвестный',
                1104 => 'Переписка, Военный Комиссариат Фрунзенского района г.Москвы',
                1105 => 'Переписка, ВОКС',
                1110 => 'Переписка, ГПИ им. В.И. Ленина',
                1115 => 'Переписка, Зоологический музей АН СССР',
                1117 => 'Переписка, Институт Краеведческой и Музейной работы',
                1121 => 'Переписка, Комитет по делам Культпросвет-учреждений при Совете Министров СССР',
                1122 => 'Переписка, Меховое Бюро Комиссии Использования при ВСНХ',
                1124 => 'Переписка, Министерство Культуры РСФСР',
                1125 => 'Переписка, Министерство Лёгкой Промышленности СССР',
                1127 => 'Переписка, Министерство Просвещения РСФСР',
                1129 => 'Переписка, Биологический Факультет МГУ',
                1138 => 'Переписка, Музейный Отдел НКП',
                1139 => 'Переписка, Военный Отдел НКП',
                1142 => 'Переписка, Общество Культурной Связи СССР с Зарубежными странами',
                1146 => 'Переписка, Псковский музей',
                1151 => 'Переписка, Союзпушнина',
                1155 => 'Переписка, Главное управление по делам охотничьих хозяйств',
                1157 => 'Переписка, Устюжнский Музей Местного Края',
                1159 => 'Переписка, Центральный музей Бурят-Монгольской АССР',
                1162 => 'Переписка, Якутский Областной музей',
                1163 => 'Переписка, Архитектурно-планировочное управление г. Москвы',
                1164 => 'Переписка, Мосгорисполком',
                1169 => 'Переписка, Комитет по делам Культурно-просветительных учреждений при Совнаркоме РСФСР',
                1170 => 'Переписка, Комитет по делам строительства',
                1172 => 'Письма о необходимости помещения и строительстве нового здания для ценных коллекций ГДМ',
                1177 => 'Ashby Eric, переписка',
                1178 => 'Atanassov, переписка',
                1179 => 'Augusta Josef, переписка',
                1181 => 'Barlow Nora, переписка',
                1190 => 'Damon Robert F., переписка',
                1192 => 'Darwin Katherine, переписка',
                1193 => 'Darwin Charles, переписка',
                1194 => 'Дембовский Ян Казимирович, переписка',
                1195 => 'Eimer Ing. Helmut, переписка',
                1196 => 'Eimer Manfred, переписка',
                1201 => 'Hamilton Joseph Gilbert, переписка',
                1203 => 'Huxley Julian Sorell, переписка',
                1204 => 'Johannsen, переписка',
                1207 => 'Kleinschmidt Otto, переписка',
                1208 => 'Kohts Amelie, переписка',
                1209 => 'Kohts Elisabeth, переписка',
                1211 => 'Von Linden Grafin Maria, переписка',
                1214 => 'Otakar Matousek, переписка',
                1228 => 'De Vries Hugo Marie, переписка',
                1229 => 'De Vries Reinier Willem Petrus, переписка',
                1231 => 'Yerkes Ada W., переписка',
                1239 => 'Переписка, The American Museum of Natural History',
                1240 => 'Переписка, Bibliographisches Institut',
                1242 => 'Переписка, Biologische Versuchsanstalt der Akademie der Wissenschaften',
                1243 => 'Bottcher Ernst A., переписка',
                1244 => 'Переписка, British Museum (Natural History)',
                1246 => 'Переписка, Christoph Reisser\'s Sohne',
                1247 => 'Переписка, Christ\'s College, Cambridge',
                1248 => 'Переписка, Сolumbia University in the City of New York, Departament of Zoology',
                1250 => 'Переписка, Dultz & Co., Buchhandlung und Antiquariat fur Naturwissenschaften',
                1251 => 'Gentz Kurst, переписка',
                1253 => 'Fock Gustav, переписка',
                1255 => 'Переписка, V.Fric in Prag, Naturalien',
                1256 => 'Переписка, R.Friedlander & Sohn, Buchhandlung',
                1258 => 'Переписка, Haeckel-Museum u. Institut fur Geschichte der Zoologie',
                1260 => 'Переписка, Maison Emilie Deyrolle, Paris',
                1261 => 'Переписка, Edward Gerrard & Sons, Naturalists, Dealers & Agents',
                1262 => 'Переписка, K.F.Koehlers Antiquarium',
                1264 => 'Переписка, Konigl. Zoologisches Museum',
                1265 => 'Переписка, Dr. F.Krantz, Rheinisches Mineralien-Kontor',
                1266 => 'Переписка, Lake Erie College',
                1267 => 'Переписка, Librairie Larousse',
                1268 => 'Переписка, Linnaea Naturhistorisches Institut, Berlin',
                1269 => 'Переписка, The Linnean Society of London',
                1271 => 'Переписка, Kamera-Fabrik Goltz & Breutmann, Dresden',
                1274 => 'Переписка, Museum National d\'Histoire Naturelle',
                1275 => 'Переписка, Museum of Comparative Zoology at Harvard College',
                1278 => 'Переписка, Naturwissenschaftliches Fakultat der Universitat Tubingen',
                1279 => 'Переписка, Naturwissenschaftliches Museum, Coburg',
                1282 => 'Переписка, Oskar Fritsche, Präparator',
                1285 => 'Переписка, W.F.H.Rosenberg, Naturalist and Importer of Exotik Zoological Collection',
                1286 => 'Переписка, The Royal College of Surgeons of England',
                1287 => 'Переписка, The Royal Geographical Society',
                1288 => 'Переписка, The Royal Society, Burlington House, London',
                1289 => 'Переписка, Sander\'s Praparatorium',
                1290 => 'Переписка, F.Sartorius, Vereinigte Werkstatten fur Wissenschaftliche Instrumente',
                1291 => 'Переписка, Dr. Schluter & Dr. Mass, Naturwissenschaftliches Lehrmittel-Institut',
                1292 => 'Переписка, The Society for Cultural Relations Between the Peoples of the British Commonwealth and the USSR',
                1297 => 'Переписка, Tierpark Berlin',
                1298 => 'Переписка, Johannes Umlauff, Naturalienhandlung u. Lehrmittel',
                1302 => 'Переписка, Verlagsbuchhandlung Gebruder Borntraeger',
                1303 => 'Переписка, World Federation of Scientific Workers',
                1304 => 'Yerkes Robert Mearns, переписка',
                1305 => 'Переписка, Carl Zeiss, Filial-Abteilung der Optischen Werkstaette in Jena',
                1306 => 'Переписка, Zoological Society of London',
                1307 => 'Переписка, Zoological Survey of India',
                1308 => 'Переписка, Zoologicka Zahrada, Praha',
                1312 => 'Переписка, Zoologisches Museum der Humboldt - Universität zu Berlin, Prof. Dr. Erwin Stresemann',
                },
        },
        2 => {
            'name' => 'Kalacheva',
            'name_readable_ru' => 'опись Калачевой И.П.',
            'name_readable_en' => 'inventory by Kalacheva I.P.',
            'funds' => ['15845'],
            },
        },
    };

sub check_config {
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
                Carp::confess("Configuration error: fond [$fund_id] used more than once, please fix");
            }

            $data_desc_struct->{'storage_groups_by_fund_number'}->{$fund_id} = $st_gr_id;
        }
    }

    my $r = IPC::Cmd::run_forked("cd " . $data_desc_struct->{'docbook_source_base'} . " && git rev-parse --git-dir");
    Carp::confess("Configuration error: docbook_source_base must point to valid git repo, but: " . $r->{'merged'})
        unless $r->{'exit_code'} == 0;

    $r = IPC::Cmd::run_forked("cd " . trim($r->{'stdout'}, " \n") . " && cd .. && pwd");
    Carp::confess("Configuration error: something went wrong while determinig git top level directory: " . $r->{'merged'})
        unless $r->{'exit_code'} == 0;

    $runtime->{'docbook_source_git_dir'} = trim($r->{'stdout'}, " \n");
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

sub safe_string {
  my ($str, $default) = @_;

  $default = "" unless defined($default);

  if (defined($str)) {
    return $str;
  }
  else {
    return $default;
  }
}

sub trim {
    my ($string, $symbols) = @_;
  
    if (ref($string) eq 'SCALAR') {
        my $tstr = safe_string($$string);
    
        return 0 if $tstr eq ''; # nothing to trim, do not waste cpu cycles
    
        if ($symbols) {
            $tstr =~ s/^[${symbols}]+//so;
            $tstr =~ s/[${symbols}]+$//so;
        }
        else {
            $tstr =~ s/^\s+//so;
            $tstr =~ s/\s+$//so;
        }

        if ($tstr ne $$string) {
            $$string = $tstr;
            return 1;
        }
        else {
            return 0;
        }
    }
    else {
        $string = safe_string($string);

        return "" if $string eq ''; # nothing to trim, do not waste cpu cycles

        if ($symbols) {
            $string =~ s/^[${symbols}]+//so;
            $string =~ s/[${symbols}]+$//so;
        }
        else {
            $string =~ s/^\s+//so;
            $string =~ s/\s+$//so;
        }

        return $string;
    }
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

# subset of Yandex::Tools::read_dir
#
# by default returns array of short filenames
# in the given directory (without recursing)
#
sub read_dir {
    my ($dirname, $o) = @_;

    Carp::confess("Programmer error: dirname parameter must point to existing directory, got [" . safe_string($dirname) . "]")
        unless $dirname && -d $dirname;

    $o = {} unless $o;
    $o->{'output-format'} = 'arrayref' unless $o->{'output-format'};

    my $dir_handle;
    if (!opendir($dir_handle, $dirname)) {
        Carp::confess("Unable to open directory [" . $dirname . "]: $!");
    }
    
    my $array = [grep {$_ ne "."  && $_ ne ".."} readdir($dir_handle)];
    close($dir_handle);
    
    if ($o->{'output-format'} eq 'arrayref') {
        return $array;
    } elsif ($o->{'output-format'} eq 'hashref') {
        my $h = {};
        foreach my $i (@{$array}) {
            $h->{$i} = 1;
        }
        return $h;
    } else {
        Carp::confess("Unsupported output-format [$o->{'output-format'}]");
    }
}

sub read_scanned_docs {
    my ($opts) = @_;
    $opts = {} unless $opts;

    # cache
    return $runtime->{'read_scanned_docs'} if defined($runtime->{'read_scanned_docs'});

    $runtime->{'read_scanned_docs'} = {
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

    return $runtime->{'read_scanned_docs'}
        unless $data_desc_struct->{'external_archive_storage_base'};


    print "reading [$data_desc_struct->{'external_archive_storage_base'}]\n" if $opts->{'debug'};
    $runtime->{'read_scanned_docs'}->{'scanned_docs'}->{'array'} = read_dir($data_desc_struct->{'external_archive_storage_base'});
    
    my $cleaned_array = [];

    foreach my $item_dir (@{$runtime->{'read_scanned_docs'}->{'scanned_docs'}->{'array'}}) {
        my $item = $data_desc_struct->{'external_archive_storage_base'} . "/" . $item_dir;
        
        # scanned document is a directory
        next unless -d $item;

        push @{$cleaned_array}, $item_dir;

        $runtime->{'read_scanned_docs'}->{'files'}->{$item_dir} = {};

        my $ftimes = {};
        my $scan_dir;
        $scan_dir = sub {
            my ($dir) = @_;

            my $item_files = read_dir($dir);

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

                $runtime->{'read_scanned_docs'}->{'files'}->{$item_dir}->{$dir . "/" . $f} = 1;
            }
        };

        $scan_dir->($item);

        $runtime->{'read_scanned_docs'}->{'scanned_docs'}->{'hash'}->{$item_dir} = [];
        foreach my $mod_day (sort {$ftimes->{$a} <=> $ftimes->{$b}} keys %{$ftimes}) {
            push @{$runtime->{'read_scanned_docs'}->{'scanned_docs'}->{'hash'}->{$item_dir}}, $mod_day;
        }
    }

    $runtime->{'read_scanned_docs'}->{'scanned_docs'}->{'array'} = $cleaned_array;

#        print Data::Dumper::Dumper($runtime->{'read_scanned_docs'});

    return $runtime->{'read_scanned_docs'};
}

sub read_ocr_html_docs {
    # cache
    return $runtime->{'read_ocr_html_docs'} if defined($runtime->{'read_ocr_html_docs'});

    $runtime->{'read_ocr_html_docs'} = {
        'ocr_html_files' => {
            'array' => [],
            'hash' => {},
            },
        };

    return $runtime->{'read_ocr_html_docs'}
        unless $data_desc_struct->{'docbook_dspace_out_base'};

    $runtime->{'read_ocr_html_docs'}->{'ocr_html_files'}->{'files_array'} = read_dir($data_desc_struct->{'docbook_dspace_out_base'});
    $runtime->{'read_ocr_html_docs'}->{'ocr_html_files'}->{'array'} = [];

    foreach my $el (@{$runtime->{'read_ocr_html_docs'}->{'ocr_html_files'}->{'files_array'}}) {
        my $item = $data_desc_struct->{'docbook_dspace_out_base'} . "/" . $el;

        next unless -f $item;
        next unless $el =~ /^(.+)\.html$/;

        $runtime->{'read_ocr_html_docs'}->{'ocr_html_files'}->{'hash'}->{$1} = $item;
        push @{$runtime->{'read_ocr_html_docs'}->{'ocr_html_files'}->{'array'}}, $1;
    }

    return $runtime->{'read_ocr_html_docs'};
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
    # cache
    return $runtime->{'read_docbook_sources'} if defined($runtime->{'read_docbook_sources'});

    $runtime->{'read_docbook_sources'} = {
        'docbook_files' => {
            'array' => [],
            'hash' => {},
            },
        };

    return $runtime->{'read_ocr_html_docs'}
        unless $data_desc_struct->{'docbook_source_base'};

    $runtime->{'read_docbook_sources'}->{'docbook_files'}->{'array'} = read_dir($data_desc_struct->{'docbook_source_base'} . "/docbook");

    foreach my $el (@{$runtime->{'read_docbook_sources'}->{'docbook_files'}->{'array'}}) {
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

        $runtime->{'read_docbook_sources'}->{'docbook_files'}->{'hash'}->{$docbook_short_name} = $docbook_creation_date;
    }

    return $runtime->{'read_docbook_sources'};
}

sub tsv_read_and_validate {
    my ($input_file, $o) = @_;

    # cache
    if (defined($runtime->{'csv_struct'})) {
        return $runtime->{'csv_struct'};
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
                        safe_string($opts->{'prefix'}) . "]");
                }

                foreach my $resource_name (@{$possible_resource_names}) {
                    next unless defined($resource_name) && $resource_name ne "";
                
                    # check that document exists on the disk
                    if (scalar(@{$resource_struct->{'array'}}) && !$resource_struct->{'hash'}->{$resource_name}) {
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
                'dc.date.created' => "",
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
                'sdm-archive-workflow.date.digitized' => '',
                'sdm-archive-workflow.date.cataloged' => $today_yyyy_mm_dd,
                'sdm-archive-workflow.date.textExtracted' => '',
                'sdm-archive-workflow.misc.classification-code' => '',
                'sdm-archive-workflow.misc.classification-group' => '',
                'sdm-archive-workflow.misc.completeness' => '',
                'sdm-archive-workflow.misc.authenticity' => '',
#                'sdm-archive-workflow.misc.archive' => '',
            };

            # appends unique value for metadata field (all the metadata fields
            # are allowed to contain more than value)
            #
            # returns appended value (if input $metadata_value was stored)
            # or undef (if supplied value has already existed and was not
            # appended therefore)
            #
            # does some finegrained cleanup of metadata field values
            # (depending on the name of populated metadata field)
            my $push_metadata_value = sub {
                my ($metadata_name, $metadata_value) = @_;

                $tsv_struct->{$metadata_name} = "" unless defined($tsv_struct->{$metadata_name});
                
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

                $doc_type = $push_metadata_value->('sdm-archive-workflow.misc.document-type', $doc_type);
                $doc_desc = $push_metadata_value->('sdm-archive-workflow.misc.notes', $doc_desc);

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
                    $push_metadata_value->('sdm-archive-workflow.misc.completeness', $item->{'by_field_name'}->{'doc_property_full'});
                $item->{'by_field_name'}->{'doc_property_genuine'} = 
                    $push_metadata_value->('sdm-archive-workflow.misc.authenticity', $item->{'by_field_name'}->{'doc_property_genuine'});
                $item->{'by_field_name'}->{'archive_date'} =
                    $push_metadata_value->('sdm-archive-workflow.misc.archive-date', $item->{'by_field_name'}->{'archive_date'});

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
                                $push_metadata_value->('sdm-archive-workflow.misc.classification-group',
                                    $data_desc_struct->{'storage_groups'}->{$st_gr_id}->{'classification_codes'}->{$cc});
                                $push_metadata_value->('sdm-archive-workflow.misc.classification-code',
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
                                    $push_metadata_value->('sdm-archive-workflow.misc.classification-group',
                                        $data_desc_struct->{'storage_groups'}->{$st_gr_id}->{'classification_codes'}->{$cc});
                                    $push_metadata_value->('sdm-archive-workflow.misc.classification-code',
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
                    $push_metadata_value->('sdm-archive-workflow.date.digitized', $d_day);
                }
            }
            foreach my $d (keys %{$storage_struct->{'docbook_files_dates_h'}}) {
                $push_metadata_value->('sdm-archive-workflow.date.textExtracted', $storage_struct->{'docbook_files_dates_h'}->{$d});
            }

            $storage_struct->{'tsv_struct'} = $tsv_struct;
            $storage_struct->{'storage-group-id'} = $st_gr_id;
            $storage_struct->{'storage-number'} = $storage_number;
        }
    }

    # check scanned directories which are associated with several DSpace (storage) items
    foreach my $dir (keys %{$doc_struct->{'storage_items_by_scanned_dir'}}) {
        if (scalar(@{$doc_struct->{'storage_items_by_scanned_dir'}->{$dir}}) > 1) {
            if (grep {$_ eq $dir} @{$data_desc_struct->{'known_scanned_documents_included_into_several_storage_items'}}) {
                next;
            }

            Carp::confess("Scanned directory [$dir] matches several storage items: [" .
                join(",", map {$_->{'storage-group-id'} . "/" . $_->{'storage-number'}}
                    @{$doc_struct->{'storage_items_by_scanned_dir'}->{$dir}}) .
                "]");
        }
    }

    # check that all the scanned dirs were matched with some storage item,
    # except for some special documents
    foreach my $sd (@{$scanned_dirs->{'scanned_docs'}->{'array'}}) {
        if (grep {$_ eq $sd} @{$data_desc_struct->{'scanned_documents_without_id'}}) {
            next;
        }

        if (!defined($doc_struct->{'storage_items_by_scanned_dir'}->{$sd})) {
            Carp:confess("Scanned directory [$sd] didn't match any storage item");
        }
    }

    # check that one html file matches not more than 1 storage item
    foreach my $html (keys %{$doc_struct->{'storage_items_by_ocr_html'}}) {
        if (scalar(@{$doc_struct->{'storage_items_by_ocr_html'}->{$html}}) > 1) {
            Carp::confess("HTML file [$html] matches several storage items: [" .
                join(",", map {$_->{'storage-group-id'} . "/" . $_->{'storage-number'}}
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

    $runtime->{'csv_struct'} = $doc_struct;
    return $runtime->{'csv_struct'};
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

sub read_dspace_collection {
    my ($dir) = @_;

    my $dspace_exported_colletion = read_dir($dir);
    my $invalid_directories = [grep {$_ !~ /^\d+$/ || ! -d $dir . "/" . $_} @{$dspace_exported_colletion}];
    Carp::confess("--dspace-exported-collection should point to the directory containing DSpace collection in Simple Archive Format")
        if scalar(@{$dspace_exported_colletion}) == 0;
    Carp::confess("Unexpected items in DSpace export directory [$dir]: " . join(",", @{$invalid_directories}))
        if scalar(@{$invalid_directories});

    my $dspace_items = {};

    DSPACE_ITEM: foreach my $seq (sort {$a <=> $b} @{$dspace_exported_colletion}) {
        my $item_path = $o->{'dspace-exported-collection'} . "/" . $seq;
        my $item_files = read_dir($item_path, {'output-format' => 'hashref'});
        
        foreach my $f (qw/dublin_core.xml contents/) {
            Carp::confess("Invalid DSpace Simple Archive Format layout in [$item_path], $f doesn't exist")
                unless defined($item_files->{$f});
        }

        my $item_dc_xml = XML::Simple::XMLin($item_path . "/dublin_core.xml");
        Carp::confess("Unknown dublin_core.xml layout")
            unless $item_dc_xml->{'schema'} &&
                $item_dc_xml->{'schema'} eq 'dc' &&
                $item_dc_xml->{'dcvalue'} &&
                ref($item_dc_xml->{'dcvalue'}) eq 'ARRAY';
        
        my $item_struct;
        DCVALUES: foreach my $dcvalue (@{$item_dc_xml->{'dcvalue'}}) {
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
                        'dublin_core.xml' => $item_dc_xml,
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
        $item_struct->{'handle'} = trim(read_file_scalar($item_path . "/handle"), " \n");
    }

    return $dspace_items;
}

sub init_logging {
    my $log_file = "/var/log/dspace-sdm.log";
    Carp::confess("Unable to write to log file [$log_file], check permissions")
        unless -w $log_file;

    Log::Log4perl->init_once(\(qq {
        log4perl.rootLogger = DEBUG, app_screen, app_log_all

        log4perl.appender.app_screen = Log::Log4perl::Appender::Screen
        log4perl.appender.app_screen.stderr = 0
        log4perl.appender.app_screen.layout = Log::Log4perl::Layout::PatternLayout
        log4perl.appender.app_screen.layout.ConversionPattern = %d\t%P\t%X{activity}\t%m%n

        # http://search.cpan.org/~mschilli/Log-Log4perl/lib/Log/Log4perl/Layout/PatternLayout.pm
        # 
        # date                    pid     priority MDC->{'activity'} MDC->{'filename'} message            new-line
        # %d                      %P      %p       %X{activity}      %X{filename}      %m                 %n
        # 

        log4perl.appender.app_log_all = Log::Log4perl::Appender::File
        log4perl.appender.app_log_all.filename = $log_file
        log4perl.appender.app_log_all.layout = Log::Log4perl::Layout::PatternLayout
        log4perl.appender.app_log_all.layout.ConversionPattern = %d\t%P\t%X{activity}\t%m%n
        }
    ));
    Log::Log4perl::MDC->put("activity", File::Basename::basename($0));
}

sub do_log {
    my ($msg) = @_;
    my $logger = Log::Log4perl::get_logger();
    $logger->debug($msg);
}

sub prepare_docbook_makefile {
    my ($full_docbook_path) = @_;

    my ($filename, $dirs) = File::Basename::fileparse($full_docbook_path);
    
    my $entity_name = $filename;
    $entity_name =~ s/\..+$//g;
    
    my $entities = {
        $entity_name => {'SYSTEM' => $full_docbook_path},
        };

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

    my $tmp_docbook_name = "/tmp/$entity_name.docbook";
    write_file_scalar($tmp_docbook_name, $dspace_html_docbook_template);

    return $tmp_docbook_name;
}


init_logging();
check_config();

if ($o->{'bash-completion'}) {
    print join(" ", map {$_ =~ s/=.+$//; "--" . $_} grep {$_ ne 'bash-completion'} @{$o_names}) . "\n";
} elsif ($o->{'dump-config'}) {
    print Data::Dumper::Dumper($data_desc_struct);
    print Data::Dumper::Dumper($runtime);
} elsif ($o->{'data-split-by-tab'}) {
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
} elsif ($o->{'data-split-by-comma'}) {
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
} elsif ($o->{'descriptor-dump'}) {
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
} elsif ($o->{'dump-csv-item'}) {
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
} elsif ($o->{'list-storage-items'}) {
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
} elsif ($o->{'dump-tsv-struct'}) {
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
} elsif ($o->{'initial-import'}) {
    Carp::confess("Need --external-tsv")
        unless $o->{'external-tsv'};

    my $target_collection_handle = $o->{'target-collection-handle'} || "123456789/2";

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
} elsif ($o->{'dump-scanned-docs'}) {
    my $resources = read_scanned_docs({'debug' => $o->{'debug'}});
    print Data::Dumper::Dumper($resources);
} elsif ($o->{'dump-ocr-html-docs'}) {
    my $resources = read_ocr_html_docs();
    print Data::Dumper::Dumper($resources);
} elsif ($o->{'dump-docbook-sources'}) {
    my $resources = read_docbook_sources();
    print Data::Dumper::Dumper($resources);
} elsif ($o->{'dump-dspace-exported-collection'}) {
    Carp::confess("--dspace-exported-collection should point to the directory, got [" . safe_string($o->{'dspace-exported-collection'}) . "]")
        unless $o->{'dspace-exported-collection'} && -d $o->{'dspace-exported-collection'};

    my $dspace_collection = read_dspace_collection($o->{'dspace-exported-collection'});
    print Data::Dumper::Dumper($dspace_collection);
} elsif ($o->{'dump-dspace-exported-item'}) {
    Carp::confess("--dspace-exported-collection should point to the directory, got [" . safe_string($o->{'dspace-exported-collection'}) . "]")
        unless $o->{'dspace-exported-collection'} && -d $o->{'dspace-exported-collection'};

    my ($st_gr_id, $st_it_id) = split(" ", safe_string($o->{'dump-dspace-exported-item'}));
    Carp::confess("Need storage_group and storage_number (try --dump-dspace-exported-item '1 1')")
        unless $st_gr_id && $st_it_id;

    my $dspace_collection = read_dspace_collection($o->{'dspace-exported-collection'});
    Carp::confess("Unable to find item in DSpace export")
        unless defined($dspace_collection->{$st_gr_id}) && defined($dspace_collection->{$st_gr_id}->{$st_it_id});

    print Data::Dumper::Dumper($dspace_collection->{$st_gr_id}->{$st_it_id});
} elsif ($o->{'import-bitstream'}) {
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

    my $r_struct = read_scanned_docs();

    foreach my $html_file (@{$st_item->{'ocr_html_document_directories'}}) {
        my $f = $st_item->{'ocr_html_document_directories_h'}->{$html_file};

        my $fname = $f;
        $fname =~ s/.+\///g;

        my $r = symlink($f, $dspace_collection_item->{'item-path'} . "/" . $fname);
        if (!$r) {
            Carp::confess("Error creating symlink from [$f] to [$dspace_collection_item->{'item-path'}/$fname]:" . $!);
        }
        
        $dspace_collection_item->{'contents'} .= $fname . "\n";
        write_file_scalar($dspace_collection_item->{'item-path'} . "/contents", $dspace_collection_item->{'contents'});
    }
    
    foreach my $scan_dir (@{$st_item->{'scanned_document_directories'}}) {
        next unless defined($r_struct->{'files'}->{$scan_dir});

        foreach my $f (sort keys %{$r_struct->{'files'}->{$scan_dir}}) {
            my $fname = $f;
            $fname =~ s/.+\///g;

            my $r = symlink($f, $dspace_collection_item->{'item-path'} . "/" . $fname);
            if (!$r) {
                Carp::confess("Error creating symlink from [$f] to [$dspace_collection_item->{'item-path'}/$fname]:" . $!);
            }

            $dspace_collection_item->{'contents'} .= $fname . "\n";
        }
        write_file_scalar($dspace_collection_item->{'item-path'} . "/contents", $dspace_collection_item->{'contents'});
    }

    print "prepared DSpace item [$dspace_collection_item->{'item-path'}]\n";

    # print Data::Dumper::Dumper($dspace_collection_item);
    # print Data::Dumper::Dumper($st_item);
} elsif ($o->{'import-bitstreams'}) {
    Carp::confess("Need --external-tsv")
        unless $o->{'external-tsv'};
    Carp::confess("--dspace-exported-collection should point to the directory, got [" . safe_string($o->{'dspace-exported-collection'}) . "]")
        unless $o->{'dspace-exported-collection'} && -d $o->{'dspace-exported-collection'};
    if ($o->{'limit'}) {
        if ($o->{'limit'} !~ /^\d+$/ || $o->{'limit'} == 0) {
            Carp::confess("--limit N requires N to be positive integer");
        }
    }

    my $in_doc_struct = tsv_read_and_validate($o->{'external-tsv'}, $o);
    my $dspace_collection = read_dspace_collection($o->{'dspace-exported-collection'});
    my $r_struct = read_scanned_docs();

    my $updated_items = 0;

    DSPACE_COLLECTION: foreach my $st_gr_id (sort {$a <=> $b} keys %{$dspace_collection}) {

        Carp::confess("Can't find storage group [$st_gr_id] in incoming data, something is very wrong")
            unless defined($in_doc_struct->{'by_storage'}->{$st_gr_id});
        
        DSPACE_ITEM: foreach my $st_it_id (sort {$a <=> $b} keys %{$dspace_collection->{$st_gr_id}}) {

            my $dspace_collection_item = $dspace_collection->{$st_gr_id}->{$st_it_id};

            # if there are bitstreams in the item, skip it
            if ($dspace_collection_item->{'contents'}) {
                print "skipping [$st_gr_id/$st_it_id]\n";
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
        
            my $updated_item = 0;

            foreach my $html_file (@{$st_item->{'ocr_html_document_directories'}}) {
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
            
            foreach my $scan_dir (@{$st_item->{'scanned_document_directories'}}) {
                
                # this shouldn't happen in production as external_archive_storage_base
                # shouldn't change when this script is run; during tests though
                # this happened (because upload of archive to the test server
                # took about several weeks because of the slow network)
                next unless defined($r_struct->{'files'}->{$scan_dir});

                if ($o->{'dry-run'}) {
                    print "would try to update [$st_gr_id/$st_it_id]\n";
                    next DSPACE_ITEM;
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
                $updated_items = $updated_items + 1;
                do_log("added [" . $updated_item . "] bitstreams to the item [$st_gr_id/$st_it_id], DSpace Archive [$dspace_collection_item->{'item-path'} $dspace_collection_item->{'handle'}]");

                if ($o->{'limit'} && $updated_items == $o->{'limit'}) {
                    last DSPACE_COLLECTION;
                }
            }
        }
    }
} elsif ($o->{'build-docbook-for-dspace'}) {
    Carp::confess("Need --docbook-filename")
        unless $o->{'docbook-filename'};
    
    my $full_docbook_path = $data_desc_struct->{'docbook_source_base'} . "/docbook/" . $o->{'docbook-filename'};
    Carp::confess("--docbook-filename point to nonexistent file (resolved to $full_docbook_path)")
        unless -e $full_docbook_path;

    my $tmp_docbook_name = prepare_docbook_makefile($full_docbook_path);

    if ($o->{'no-xsltproc'}) {
        print "prepared docbook file [$tmp_docbook_name]\n";
        exit 0;
    }

    my $cmd = 'xsltproc --xinclude ' .
        '--stringparam base.dir ' . $data_desc_struct->{'docbook_dspace_out_base'} . "/ " .
        '--stringparam use.id.as.filename 1 ' .
        '--stringparam root.filename "" ' .
        $data_desc_struct->{'docbook_source_base'} . '/build/docbook-html-dspace.xsl ' .
        $tmp_docbook_name;
    my $r = IPC::Cmd::run_forked($cmd);
    Carp::confess("Error generating DSpace html file, cmd [$cmd]: " . Data::Dumper::Dumper($r))
        if $r->{'exit_code'} ne 0;

    unlink($tmp_docbook_name);

    if ($r->{'merged'} =~ /Writing\s+?(.+?)\sfor/s) {
        print "built: " . $1 . "\n";
    } else {
        Carp::confess("Unable to extract filename written by DocBook (protocol changed?) from: " . $r->{'merged'});
    }
} elsif ($o->{'validate-tsv'}) {
    Carp::confess("Need --external-tsv")
        unless $o->{'external-tsv'};

    my $in_doc_struct = tsv_read_and_validate($o->{'external-tsv'}, $o);
    print "$o->{'external-tsv'} seems to be ok\n";
} else {
    Carp::confess("Need command line parameter, one of: " . join("\n", "", sort map {"--" . $_} @{$o_names}) . "\n");
}
