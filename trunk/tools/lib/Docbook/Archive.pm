#!/usr/bin/perl

package Docbook::Archive;
use Yandex::Tools;

sub get_document_directory {
  my ($doc_name) = @_;
  return "$ENV{'ARCHIVE_HOME'}/books/$doc_name";
}

sub is_valid_document {
  my ($doc_name) = @_;
  return 0 unless $doc_name;
  my $doc_dir = get_document_directory($doc_name);
  return (-d $doc_dir);
}

sub get_document_docbook_files {
  my ($doc_name) = @_;

  my $doc_dir = get_document_directory($doc_name);
  die "Invalid document directory: [$doc_dir]" unless -d "$doc_dir/docbook";

  my $files = Yandex::Tools::read_dir("$doc_dir/docbook", {'output_type' => 'hashref'});

  return $files;
}


1;
