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

binmode STDOUT, ':encoding(UTF-8)';
my $o = {};
Getopt::Long::GetOptionsFromArray(\@ARGV, $o,
    'input-file=s',
    'output-dir=s',
    'sync',
    'dry-run',
    );

Carp::confess("Need --input-file")
    unless $o->{'input-file'};
Carp::confess("Need --output-dir")
    unless $o->{'output-dir'};
Carp::confess("Output directory [$o->{'output-dir'}] must not exist")
    if -d $o->{'output-dir'};

my $list = [];

my $fh;
open($fh, "<" . $o->{'input-file'}) || Carp::confess("Can't open [$o->{'input-file'}] for reading");
binmode $fh, ':encoding(UTF-8)';
while (my $l = <$fh>) {
    push @{$list}, $l;
}
close($fh);

my $line_def = [qw/
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
my $description_labels = {
    'doc_property_full' => 'Полнота: ',
    'doc_property_genuine' => 'Подлинность: ',
    'doc_type' => 'Способ воспроизведения: ',
    'doc_desc' => 'Примечания: ',
    };

my $id = 0;

foreach my $line (@{$list}) {
    my $line_array = [split("\t", $line, -1)];
    my $line_struct = {};
    my $i = 0;
    foreach my $fvalue (@{$line_array}) {
        $line_struct->{$line_def->[$i]} = $fvalue;
        $i++;
    }

    # skip title
    next if $line_struct->{'date_of_status'} eq 'date of status';

    $id++;

    my $dc_filepath = $o->{'output-dir'} . "/" . sprintf("%05d", $id);
    File::Path::make_path($dc_filepath);
    my $fh1;
    open($fh1, ">" . $dc_filepath . "/dublin_core.xml") ||
        Carp::confess("unable to write to [" . $dc_filepath . "/dublin_core.xml" . "]");
    binmode $fh1, ':encoding(UTF-8)';
    
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

    my $descriptions = [];
    foreach my $f (qw/doc_property_full doc_property_genuine doc_type doc_desc/) {
        if ($line_struct->{$f} && $line_struct->{$f} !~ /^\s*$/) {
            push @{$descriptions}, '
  <dcvalue element="description" qualifier="none" language="rus">' . $description_labels->{$f} . $line_struct->{$f} . '</dcvalue>';
        }
    }

    print $fh1 '<?xml version="1.0" encoding="utf-8" standalone="no"?>
<dublin_core schema="dc">
  <dcvalue element="contributor" qualifier="author" language="rus">Котс, Александр Федорович</dcvalue>
  <dcvalue element="contributor" qualifier="author" language="eng">Kohts (Coates), Alexander Erich</dcvalue>
  <dcvalue element="creator" qualifier="none" language="rus">Котс, Александр Федорович</dcvalue>
  <dcvalue element="creator" qualifier="none" language="eng">Kohts (Coates), Alexander Erich</dcvalue>
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
    
    close($fh1);
}
