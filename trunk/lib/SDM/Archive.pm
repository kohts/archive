package SDM::Archive;

use strict;
use warnings;

use utf8;
use Encode;

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
use DBI;
use File::Basename;
use File::Path;
use FindBin;
use Getopt::Long;
use IPC::Cmd;
use IOW::File;
use JSON;
use Log::Log4perl;
use LWP::UserAgent;
use POSIX;
use Storable;
use Text::CSV;
use Time::HiRes;
use XML::Simple;
use Yandex::Tools;

use SDM::Archive::DB;
use SDM::Archive::Utils;
use SDM::Archive::DSpace;

use Exporter 'import';
our @EXPORT = qw(
  trim
  safe_string
  );

# unbuffered output
$| = 1;

binmode(STDIN, ':encoding(UTF-8)');
binmode(STDOUT, ':encoding(UTF-8)');

our $runtime = {
    'dspace_rest' => {},
    };

our $authors_canonical = {
    "Анков К.Г." => [],
    "Анциферова" => [],
    "Анжанов А." => [ "Жандармов А.П." ],
    "Анучин Д.Н." => [ "Анучин, Дмитрий Николаевич", {"name" => "Anuchin, Dmitry", "lang" => "en"}, ],
    "Артоболевский В.М." => [ "Артоболевский, Владимир Михайлович", ],
    "Афанасьев В.А." => [ "Афанасьев, Виталий Аристархович" ],
    "Бадамшин Б.И." => [ "Бадамшин, Бурган Изъятулович" ],
    "Белоголовый Ю.А." => [ "Белоголовый, Юрий Аполлонович" ],
    "Беляев М.М." => [ "Беляев, Михаил Михайлович", ],
    "Белышев В.А." => [],
    "Берг А.Н." => [],
    "Берестнев В.Ф." => [],
    "Бернштейн" => [],
    "Биашвили В.Я." => [],
    "Бобринский Н.А." => [ "Бобринский, Николай Алексеевич" ],
    "Богоявленский Н." => [],
    "Букин В.Р." => [],
    "Бунак В.В." => [],
    "Бунчур А.," => [],
    "Бутурлин С.А." => [],
    "Бутягин А.С." => [ "Бутягин, Алексей Сергеевич" ],
    "Бычкова Е." => [],
    "Вагнер В.А." => [ "Вагнер, Владимир Александрович", {"name" => "Wagner, Vladimir", "lang" => "en"}, ],
    "Васильев Е.Н." => [],
    "Васильков И." => [],
    "Варсанофьева В.А." => [ "Варсанофьева, Вера Александровна" ],
    "Ватагин В.А." => [ "Ватагин, Василий Алексеевич", {"name" => "Vatagin, Vasily", "lang" => "en"}, ],
    "Вахромеев К.А." => [ "Вахромеев, Кирилл Альвинович" ],
    "Виноградов Н.В." => [],
    "Волкац Д.С." => [ "Волкац, Дина Соломоновна" ],
    "Воронина М." => [],
    "Войтонис Н.Ю." => [ "Войтонис, Николай Юрьевич" ],
    "Вяжлинский Д.М." => [ "Вяжлинский, Дмитрий Михайлович" ],
    "Гавриленко А.А." => [ "Гавриленко, Анатолий Александрович" ],
    "Гамаева З.М." => [],
    "Гептнер В.Г." => [ "Гептнер, Владимир Георгиевич" ],
    "Гердт М." => [ "Гердт М.А." ],
    "Гердт М.А." => [],
    "Герман А.Л." => [],
    "Гладков Н.А." => [],
    "Голиков А." => [],
    "Горшков О.С." => [ "Горшков, Осип Степанович" ],
    "Даценко В.И." => [ "Даценко, Василий Иванович" ],
    "Дембовский Я.К." => [ "Дембовский, Ян Казимирович" ],
    "Дементьев Г.П." => [ "Дементьев, Георгий Петрович" ],
    "Дороватовский Н.С." => [ "Дороватовский, Николай Сергеевич" ],
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
    "Иванцов Н." => [],
    "Игнатьева В.Н." => [ "Игнатьева, Вера Николаевна" ],
    "Каден С." => [],
    "Кац А.И." => [],
    "Кашкаров Д.Н." => [ "Кашкаров, Даниил Николаевич" ],
    "Кесаева Ю.Ф." => [ "Кесаева, Юлия Ф." ],
    "Кириллова Н.В." => [],
    "Кирпичев С.П." => [ "Кирпичев Сергей Павлович" ],
    "Коган А." => [],
    "Кожевников Г." => [ "Кожевников Г.А." ],
    "Кожевников Г.А." => [ "Кожевников, Григорий Александрович" ],
    "Козлова Е.В." => [ "Козлова, Елизавета Владимировна" ],
    "Колбановский В." => [],
    "Комаров А.Н." => [ "Комаров, Алексей Никанорович" ],
    "Кондаков Н.Н." => [ "Кондаков, Николай Николаевич" ],
    "Конёнкова М.И." => [ "Конёнкова, Маргарита Ивановна" ],
    "Константинов И.П." => [ "Константинов, Иван Петрович" ],
    "Конюс А.Г." => [ "Конюс, Андрей Георгиевич" ],
    "Коржинская О.М." => [ "Коржинская, Ольга Михайловна" ],
    "Корнилов К." => [ "Корнилов К. Н." ],
    "Корнилов К. Н." => [ "Корнилов, Константин Николаевич" ],
    "Корольков П.В." => [],
    "Котс А." => [ "Котс, Александр Федорович", {"name" => "Kohts (Coates), Alexander Erich", "lang" => "en"}, ],
    "Котс А.Р." => ["Котс, Александр Рудольфович"],
    "Котс А.Ф." => [ "Котс, Александр Федорович", {"name" => "Kohts (Coates), Alexander Erich", "lang" => "en"}, ],
    "Котс Е.А." => [ "Котс (Пупершлаг), Евгения Александровна" ],
    "Котс Р.А." => [ "Котс, Рудольф Александрович", {"name" => "Kohts, Rudolf Alfred", "lang" => "en"}, ],
    "Котс С.Р." => [ "Котс, Сергей Рудольфович" ],
    "Кочеткова В.И." => [],
    "Красовский Д.Б." => [ "Красовский, Дмитрий Борисович" ],
    "Криштофович Е." => [],
    "Крупская Н.К." => [ "Крупская, Надежда Константиновна", ],
    "Кряжин И." => [],
    "Крушинский Л.В." => [ "Крушинский, Леонид Викторович" ],
    "Кукушкина В.А." => [],
    "Лабас Ю.А." => [ "Лабас, Юрий Александрович" ],
    "Ладыгина-Котс Н.Н." => [ "Ладыгина-Котс, Надежда Николаевна", {"name" => "Ladygina-Kohts, Nadezhda Nikolaevna", "lang" => "en"}, ],
    "Левыкина Н.Ф." => [ "Левыкина, Наталья Федоровна" ],
    "Лейбенгруб П.С." => [],
    "Логинова Н.Я." => [],
    "Лоренц Ф.К." => [ "Лоренц, Фёдор Карлович", {"name" => "Lorenz, Theodore K", "lang" => "en"}, ],
    "Лурия А.Р." => [ "Лурия, Александр Романович", {"name" => "Luria, Alexander", "lang" => "en"}, ],
    "Лушкин П." => [],
    "Мантейфель П.А." => [ "Мантейфель, Петр Александрович" ],
    "Максимова" => [],
    "Малахова М.Ф." => [],
    "Мардис П.Е." => [],
    "Маркова А.Я." => [],
    "Медведев Е." => [ "Медведев, Евгений" ],
    "Мензбир М.А." => [ "Мензбир, Михаил Александрович", {"name" => "Menzbier, Mikhail Aleksandrovich", "lang" => "en"}, ],
    "Минцлова А.Р." => [ "Минцлова, Анна Рудольфовна" ],
    "Михно П.С." => [ "Михно, Пётр Саввич" ],
    "Музалевская Н.В." => [ "Музалевская, Надежда Владимировна" ],
    "Мухина В.С." => [],
    "Муцетони В.М." => [ "Муцетони, Валентина Михайловна" ],
    "Неизвестный автор" => [ "Неизвестный автор", {"name" => "Unknown author", "lang" => "en"}, ],
    "Нестурх М.Ф." => [ "Нестурх, Михаил Фёдорович", {"name" => "Nesturch, Michail Fjodorowitsch", "lang" => "de"}, ],
    "Нечаев А." => [],
    "Нюберг Н.Д." => [ "Нюберг, Николай Дмитриевич" ],
    "Новоселова С.Л." => [ "Новосёлова, Светлана Леонидовна" ],
    "Огнев И.Ф." => [ "Огнёв, Иван Флорович" ],
    "Опарин А.И." => [ "Опарин, Александр Иванович", {"name" => "Oparin, Alexander Ivanovich", "lang" => "en"}, ],
    "Осипов Т." => [],
    "Островитянов К.В." => [ "Островитянов, Константин Васильевич", {"name" => "Ostrovityanov, Konstantin", "lang" => "en"}, ],
    "Островский Л.В." => [ "Островский, Лев Владимирович" ],
    "Павловский Е.Н." => [ "Павловский, Евгений Никанорович" ],
    "Песков В.М." => [],
    "Петров Ф.Н." => [ "Петров, Фёдор Николаевич" ],
    "Петров С." => [],
    "Петрункевич А." => [],
    "Петряев П.А." => [ "Петряев, Павел Александрович" ],
    "Пичугин А.Н." => [],
    "Павлов И.П." => [ "Павлов, Иван Петрович", {"name" => "Pavlov, Ivan", "lang" => "en"}, ],
    "Плавильщиков Н.Н." => [ "Плавильщиков, Николай Николаевич" ],
    "Платонов Г.В." => [ "Платонов, Георгий Васильевич" ],
    "Полосатова Е.В." => [],
    "Поляков Г.И." => [ "Поляков, Григорий Иванович" ],
    "Полякова Ю.Ф." => [],
    "Портенко Л.А." => [ "Портенко, Леонид Александрович" ],
    "Потапов М.М." => [],
    "Потёмкин В.П." => [ "Потёмкин, Владимир Петрович" ],
    "Промтов А.Н." => [ "Промптов, Александр Николаевич" ],
    "Псахис Б.С." => [],
    "Пупершлаг Е.А." => [ "Котс (Пупершлаг), Евгения Александровна" ],
    "Рашек В.Л." => [],
    "Рейнвальд Л.Л." => [],
    "Рогинский Г.З." => [],
    "Рогинский Я.Я." => [ "Рогинский, Яков Яковлевич" ],
    "Россолимо" => [ "Россолимо, Григорий Иванович", {"name" => "Rossolimo, Grigory Ivanovich", "lang" => "en"}, ],
    "Рубинштейн С.Л." => [ "Рубинштейн, Сергей Леонидович", {"name" => "Rubinstein, Sergei", "lang" => "en"}, ],
    "Садовникова-Кольцова М.П." => [],
    "Северцов А.Н." => [ "Северцов, Алексей Николаевич" ],
    "Сизова М.И." => [ "Сизова, Магдалина Ивановна" ],
    "Симонов К." => [],
    "Сироткин М.A." => [],
    "Слудский А.А." => [],
    "Смолин П.П." => [ "Смолин, Петр Петрович" ],
    "Соболь С.Л." => [],
    "Соколов И.И." => [],
    "Соляник А.Н." => [],
    "Сосновский И.П." => [ "Сосновский, Игорь Петрович" ],
    "Спангенберг Е.П." => [ "Спангенберг, Евгений Павлович" ],
    "Сперантова В." => [],
    "Студитский А.Н." => [ "Студитский, Александр Николаевич" ],
    "Суворов И.П." => [],
    "Судиловская А.М." => [ "Судиловская, Ангелина Михайловна" ],
    "Сукачев В.Н." => [],
    "Сушкин П.П." => [ "Сушкин, Пётр Петрович" ],
    "Терентьев П.В." => [ "Терентьев, Павел Викторович" ],
    "Тих Н.С." => [],
    "Тобхауз Л.Г." => [],
    "Толстой С.С." => [ "Толстой, Сергей Сергеевич" ],
    "Трофимов В.В." => [],
    "Туров С.С." => [ "Туров, Сергей Сергеевич" ],
    "Узнадзе Д.Н." => [ "Узнадзе, Дмитрий Николаевич", {"name" => "Uznadze, Dimitri", "lang" => "en"} ],
    "Фабри К.Э." => [ "Фабри, Курт Эрнестович" ],
    "Федулов Ф.Е." => [ "Федулов, Филипп Евтихиевич" ],
    "Федулов Д.Я." => [ "Федулов, Дмитрий Яковлевич" ],
    "Федулова Т.Д." => [ "Федулова, Татьяна Дмитриевна" ],
    "Флеров К.К." => [ "Флёров К.К." ],
    "Флёров К.К." => [ "Флёров, Константин Константинович" ],
    "Формозов А.Н." => [ "Формозов, Александр Николаевич" ],
    "Хануков А." => [],
    "Хахлов В.А." => [ "Хахлов, Виталий Андреевич" ],
    "Цветкова Е.А." => [],
    "Цингер В.Я." => [ "Цингер, Василий Яковлевич" ],
    "Чаплыгин С.А." => [ "Чаплыгин, Сергей Алексеевич" ],
    "Челпанов Г.И." => [ "Челпанов, Георгий Иванович", {"name" => "Chelpanov, Georgy", "lang" => "en"} ],
    "Чернышев С." => [],
    "Чибисов Н.Е." => [ "Чибисов, Никандр Евлампиевич" ],
    "Чибисова Н.Н." => [],
    "Шиллингер Ф.Ф." => [ "Шиллингер, Франц Францович" ],
    "Шнейдеров В." => [],
    "Шорохова Е.В." => [ "Шорохова, Екатерина Васильевна" ],
    "Шперлинг М." => [],
    "Штернберг П.К." => [ "Штернберг, Павел Карлович" ],
    "Altmann S.A." => [ {"name" => "Altmann, S.A.", "lang" => "en"} ],
    "Ashby E." => [ {"name" => "Ashby, Eric", "lang" => "en"} ],
    "Atanassov" => [ {"name" => "Atanassov", "lang" => "en"} ],
    "Augusta J." => [ {"name" => "Augusta, Josef", "lang" => "en"} ],
    "Barlow N." => [ {"name" => "Barlow, Emma Nora", "lang" => "en"}, ],
    "Bottcher E.A." => [ {"name" => "Bottcher, Ernst A.", "lang" => "en"} ],
    "Bonaventure N." => [ {"name" => "Bonaventure, N.", "lang" => "en"} ],
    "Damon R.F." => [ {"name" => "Damon, Robert F.", "lang" => "en"} ],
    "Dart R." => [ {"name" => "Dart, R.", "lang" => "en"} ],
    "Darwin K." => [ {"name" => "Darwin, Katherine", "lang" => "en"} ],
    "Darwin C." => [ {"name" => "Darwin, Charles", "lang" => "en"} ],
    "Edwards W.N." => [ {"name" => "Edwards, Wilfred Norman", "lang" => "en"}, ],
    "Eimer I.H." => [ {"name" => "Eimer, Ing. Helmut", "lang" => "en"} ],
    "Eimer M." => [ {"name" => "Eimer, Manfred", "lang" => "en"} ],
    "Fock G." => [ {"name" => "Fock, Gustav", "lang" => "en"} ],
    "Gentz K." => [ {"name" => "Gentz, Kurst", "lang" => "en"} ],
    "Gesell A." => [ {"name" => "Gesell, Arnold Lucius", "lang" => "en"} ],
    "Hamilton J.G." => [ {"name" => "Hamilton, Joseph Gilbert", "lang" => "en"} ],
    "Herts M." => [ {"name" => "Herts, M.", "lang" => "en"} ],
    "Hollis J.H." => [ {"name" => "Hollis, J.H.", "lang" => "en"} ],
    "Huxley J.S." => [ {"name" => "Huxley, Julian Sorell", "lang" => "en"} ],
    "Imanishi K." => [ {"name" => "Imanishi, K.", "lang" => "en"} ],
    "Johannsen" => [ {"name" => "Johannsen", "lang" => "en"} ],
    "Kleinschmidt O." => [ {"name" => "Kleinschmidt, Otto", "lang" => "en"} ],
    "Koehler O." => [ {"name" => "Koehler, Otto", "lang" => "de"} ],
    "Kohts Amelie" => [ {"name" => "Kohts, Amelie", "lang" => "en"} ],
    "Kohts Elisabeth" => [ {"name" => "Kohts, Elisabeth", "lang" => "en"} ],
    "Kortland A." => [ {"name" => "Kortland, A.", "lang" => "en"} ],
    "Von Linden G.M." => [ {"name" => "Von Linden, Grafin Maria", "lang" => "en"} ],
    "Lipmann O." => [ {"name" => "Lipmann, O.", "lang" => "en"} ],
    "Meyerson I." => [ {"name" => "Meyerson, I.", "lang" => "en"} ],
    "Otakar Matousek" => [ {"name" => "Otakar, Matousek", "lang" => "en"} ],
    "Peate L." => [ {"name" => "Peate, L.", "lang" => "en"} ],
    "Portielje A.F." => [ {"name" => "Portielje, Anton Frederik Johan", "lang" => "en"} ],
    "Guillaume P." => [ {"name" => "Guillaume, P.", "lang" => "en"} ],
    "Quillaume R." => [ {"name" => "Quillaume, R.", "lang" => "en"} ],
    "Revesz" => [ {"name" => "Revesz", "lang" => "en"} ],
    "Stern W." => [ {"name" => "Stern, W.", "lang" => "en"} ],
    "Viand G." => [ {"name" => "Viand, G.", "lang" => "en"} ],
    "De Vries H.M." => [ {"name" => "De Vries, Hugo Marie", "lang" => "en"} ],
    "De Vries R.W.P." => [ {"name" => "De Vries, Reinier Willem Petrus", "lang" => "en"} ],
    "Weinztein B." => [ {"name" => "Weinztein, B.", "lang" => "en"} ],
    "Yerkes A.W." => [ {"name" => "Yerkes, Ada W.", "lang" => "en"} ],
    "Yerkes R." => [ "Yerkes R.M." ],
    "Yerkes R.M." => [ {"name" => "Yerkes, Robert Mearns", "lang" => "en"} ],
    "Zangwill O.Z." => [ {"name" => "Zangwill, Oliver", "lang" => "en"} ],
    };

our $data_desc_struct = {
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

    'external_archive_storage_base' => '/gone/root2/raw-afk',
    'external_archive_storage_timezone' => 'Europe/Moscow',

    'docbook_fonts_base' => '/var/www/html/FONTS',
    'docbook_source_base' => '/home/petya/github/kohts/archive/trunk/books/afk-works',
    'docbook_dspace_html_out_base' => '/var/www/html/OUT/afk-works/html-dspace',
    'docbook_dspace_pdf_out_base' => '/var/www/html/OUT/afk-works/pdf-dspace',

    'dspace_rest_url' => '',
    'dspace_upload_user_email' => '',
    'dspace_upload_user_pass' => '',

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
                '5.1' => 'Материалы отечественных корреспондентов',
                '5.2' => 'Материалы зарубежных корреспондентов',
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

sub extract_authors {
    my ($text, $opts) = @_;

    my $doc_authors = [];
    
    if ($opts->{'archive'} eq 'afk') {
        $text =~ s/Автор: Ладыгина. Котс/Автор: Ладыгина-Котс/;
        $text =~ s/Автор: Ладыгина - Котс/Автор: Ладыгина-Котс/;

        while ($text && $text =~ /^\s*Автор:\s([Нн]еизвестный\sавтор|Ладыгина\s*?\-\s*?Котс\s?Н.\s?Н.|[^\s]+?\s+?([^\s]?\.?\s?[^\s]?\.?|))(\s|,)(.+)$/) {
            my $author = $1;
            $text = $4;

            my $doc_authors1 = SDM::Archive::find_author($author, $opts);
            if (ref($doc_authors1) eq 'HASH' && $doc_authors1->{'err'}) {
                Carp::carp($doc_authors1->{'err'});
            }
            else {
                push @{$doc_authors}, @{$doc_authors1};
            }
        }

        $text = trim($text);
        if ($text && $text =~ /^и др\.(.+)/) {
            $text = $1;
        }
    }
    elsif ($opts->{'archive'} eq 'nn') {
        while ($text && $text =~ /^\s*(?<author>[^,]+)(,|$)(?<rest>.+$)?/) {
            my $author = $+{'author'};
            $text = $+{'rest'};

            my $doc_authors1 = SDM::Archive::find_author($author, $opts);
            if (ref($doc_authors1) eq 'HASH' && $doc_authors1->{'err'}) {
                Carp::carp($doc_authors1->{'err'});
            }
            else {
                push @{$doc_authors}, @{$doc_authors1};
            }
        }
    }
    else {
        Carp::confess("need archive type");
    }

    if (!scalar(@{$doc_authors}) && defined($opts->{'default_author'})) {
        push @{$doc_authors}, $opts->{'default_author'};
    }

    return {
        'extracted_struct' => $doc_authors,
        'trimmed_input' => $text,
        };
}

sub find_author {
    my ($author, $opts) = @_;

    my $doc_authors = [];

    my $push_found_author = sub {
        my ($author_canonical) = @_;

        Carp::confess("Invalid canonical author name [$author_canonical]")
            unless defined($SDM::Archive::authors_canonical->{$author_canonical});

        if (scalar (@{$SDM::Archive::authors_canonical->{$author_canonical}}) == 0) {
            push @{$doc_authors}, {"name" => $author_canonical, "lang" => "ru"};

            if (length($author) > length($author_canonical)) {
                Carp::confess("Please include [$author] into [$author_canonical]");
            }
        } else {
            foreach my $a_struct (@{$SDM::Archive::authors_canonical->{$author_canonical}}) {
                if (ref($a_struct) eq '') {
                    if (defined($SDM::Archive::authors_canonical->{$a_struct}) &&
                        $a_struct ne $author_canonical) {
  
                        my $doc_authors1 = SDM::Archive::find_author($a_struct, $opts);
                        push @{$doc_authors}, @{$doc_authors1};
                    }
                    else {
                        push @{$doc_authors}, {"name" => $a_struct, "lang" => "ru"};
                    }

                    if (length($author) > length($a_struct)) {
                        Carp::confess("Please include [$author] into [$author_canonical]");
                    }
                } else {
                    push @{$doc_authors}, $a_struct;
                }
            }
        }
    };
   
    if (defined($SDM::Archive::authors_canonical->{$author})) {
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
              
            foreach my $author_struct (@{$SDM::Archive::authors_canonical->{$author_short}}) {
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
        if ($opts->{'do_not_die'}) {
            return {"err" => "Unable to find canonical author for [$author]"};
        }
        else {
            Carp::confess("Unable to find canonical author for [$author]");
        }
    }

    return $doc_authors;
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

sub init_logging {
    my $log_file = "/var/log/dspace-sdm.log";
    Carp::confess("Unable to write to log file [$log_file] (try: touch $log_file, chmod a+w $log_file)")
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
        
        log4perl.appender.app_log_all.utf8 = 1
        }
    ));
    Log::Log4perl::MDC->put("activity", File::Basename::basename($0));
}

sub do_log {
    my ($msg) = @_;
    my $logger = Log::Log4perl::get_logger();
    $logger->debug($msg);
}

sub prepare_config {
    my $current_user = [getpwuid($>)];
    
    my $previously_defined = {};
    POSSIBLE_CFG_PATH: foreach my $cfg_path ($current_user->[7] . "/.aconsole.pl", "/etc/aconsole-config.pl") {
        next POSSIBLE_CFG_PATH
            unless -e $cfg_path;

        my $return = do "$cfg_path";

        if (!$return) {
            Carp::confess("Unable to parse [$cfg_path]: $@") if $@;
            Carp::confess("Unable to do [$cfg_path]: $!") unless defined($return);
#            Carp::confess("Unable to run [$IOW::Test::user_config_path]") unless $return;
        }
        Carp::confess("Expected hashref output from [$cfg_path], got: " . Data::Dumper::Dumper($return))
            unless ref($return) eq 'HASH';

        foreach my $k (keys %{$return}) {
            if (defined($data_desc_struct->{$k}) && !defined($previously_defined->{$k})) {
                $data_desc_struct->{$k} = $return->{$k};
                $previously_defined->{$k} = 1;
            }
        }
    }

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

    # try to switch docbook_source_base to the place where the script runs from
    # (hoping that it might be running from the cloned git repo)
    #
    if (! -d $data_desc_struct->{'docbook_source_base'}) {
        $data_desc_struct->{'docbook_source_base'} = $FindBin::Bin . "/../books/afk-works";
    }
    
    my $r = IPC::Cmd::run_forked("cd " . $data_desc_struct->{'docbook_source_base'} . " && git rev-parse --git-dir");
    Carp::confess("Configuration error: docbook_source_base must point to valid git repo (" .
        "try running 'git clone https://github.com/kohts/archive.git'); error: " . $r->{'merged'})
        unless $r->{'exit_code'} == 0;

    $r = IPC::Cmd::run_forked("cd " . trim($r->{'stdout'}, " \n") . " && cd .. && pwd");
    Carp::confess("Configuration error: something went wrong while determinig git top level directory: " . $r->{'merged'})
        unless $r->{'exit_code'} == 0;

    $runtime->{'docbook_source_git_dir'} = trim($r->{'stdout'}, " \n");
}

sub match_classification_group_by_code {
	my ($itcc) = @_;

	$itcc =~ s/[\.,\(\)\s\*]//g;

	# replace russian with latin (just in case)
	$itcc =~ s/А/A/g;
	$itcc =~ s/В/B/g;
	$itcc =~ s/С/C/g;

	my $found_cc_group;
	foreach my $cc (keys %{$data_desc_struct->{'storage_groups'}->{'1'}->{'classification_codes'}}) {
		my $tmp_cc = $cc;
		$tmp_cc =~ s/[\.,\(\)]//g;
                            
		if ($tmp_cc eq $itcc) {
			return $cc;
		}
	}

	return undef;
}

init_logging();


1;
