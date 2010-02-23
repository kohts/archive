#!/usr/bin/perl -w

use strict;
use utf8;
use Encode;
use Getopt::Long;

if (!$ARGV[0]) {
  die "usage: $0 filename [rus|eng] [table_pfx] [figure|example|formalpara]\n";
}

my $language = $ARGV[1] ? $ARGV[1] : "rus";
my $table_pfx = $ARGV[2] ? $ARGV[2] : "table";
my $tag = $ARGV[3] ? $ARGV[3] : "example";

my $total_photos = 0;
my $c_counter = 0;
my $c;

my $no_page_break;
my $r = GetOptions("no-page-break" => \$no_page_break);

sub dump_c {
  my ($c) = @_;

  if ($tag ne "formalpara") {
    if ($c_counter ne 0 && !defined($no_page_break)) {
      print "<?page-break?>\n";
    }

    if ($c_counter eq 0 ||
      $c_counter % 10 eq 0) {

      my $p = $c_counter / 10;
    
      my $pfx = "";
      if ($language ne "rus") {
        $pfx = $language . "_";
      }

      my $max_photo = $total_photos;
      if ($p*10 + 10 < $max_photo) {
        $max_photo = $p*10 + 10;
      }
    
      print "<sect1 id='${pfx}${table_pfx}_" . $p . "'><title>" . ($p * 10 + 1) . " &mdash; " . $max_photo . "</title>\n";
    }
  }

  $c_counter++;
  
  my $higher_res_label = "в большем разрешении";
  if ($language eq "eng") {
    $higher_res_label = "higher resolution";
  }
  
  my $t = $table_pfx . $c_counter;

  my $t_id = $t;
  if ($language ne "rus") {
    $t_id = $language . "_" . $t_id;
  }

  if ($tag ne "formalpara") {

    my $textobject;
    my $nrows = scalar (@{$c->{'para'}});
    
    if ($nrows < 4) {
      $textobject = '<para role=\'figure\'>' . join("<?br?>\n", @{$c->{'para'}}) . "<?br?>\n" . '</para>';
    }
    else {
      $textobject = "
<informaltable frame='none'>
<tgroup cols='2' align='left' valign='top' colsep='0' rowsep='0'>
<colspec colname='c1'/>
<colspec colname='c2'/>
<tbody>
";

      $textobject .= "<row><entry><para role='figure'>\n";
      for (my $k=1; $k <= int($nrows / 2 + .5) ; $k++) {
        $textobject .= ${$c->{'para'}}[$k - 1] . "<?br?>\n";
      }
      $textobject .= "</para></entry>\n";

      $textobject .= "<entry><para role='figure'>\n";
      for (my $k = int($nrows / 2 + .5) + 1 ; $k <= $nrows ; $k++) {
        $textobject .= ${$c->{'para'}}[$k - 1] . "<?br?>\n";
      }
      $textobject .= "</para></entry></row>\n";

      $textobject .= "</tbody>
</tgroup>
</informaltable>
";

#print $textobject . "\n";
#exit;

    }

    print '<' . $tag . ' id="' . $t_id . '">
  <title>' . $c->{'title'} . '</title>
  <mediaobject>
    <textobject role="html"><ulink role="html" url="images/hires/' . $t . '.jpg">
      <imageobject><imagedata fileref="images/html/' . $t . '.jpg" /></imageobject>
    </ulink></textobject>
    <imageobject role="fo"><imagedata fileref="images/pdf/' . $t . '.jpg" /></imageobject>
  </mediaobject>
  <mediaobject><textobject>' . $textobject . '</textobject></mediaobject>
</' . $tag . '>

';

    if ($c_counter ne 0 && $c_counter % 10 eq 0) {
      print "</sect1>\n\n";
    }
  }
  else {
    print '<' . $tag . ' id="' . $t_id . '">
  <title>Table <quote>' . $c->{'title'} . '</quote></title>
  <xref linkend="' . $t . '" /><?br?>
' . join("<?br?>\n", @{$c->{'para'}}) . "<?br?>\n"  .
'</' . $tag . '>

';

  }
}

sub preprocess {
  my ($s) = @_;

  my $v;

  while ($s =~ /\G(.*?)((\d+?)\.(\d+?)\.(\d+?))([^\d].*)/sgi) {
    $v .= $1;
    if ($2) {
      $v .= "<cihc_age y=\"$3\" m=\"$4\" d=\"$5\" />";
    }
    $s = $6;
  }
  $v .= $s;

  return $v;
}

my $f;

my $in_photo_block;
open($f, $ARGV[0]);
while (<$f>) {
  my $l = $_;

  $l =~ s/[\r\n]//g;
  Encode::_utf8_on($l);

  if ($l =~ /[\w]+/) {
    if (!$in_photo_block) {
      $total_photos = $total_photos + 1;
    }
    $in_photo_block = 1;
  }
  else {
    $in_photo_block = 0;
  }
}
close($f);

open($f, $ARGV[0]);
while (<$f>) {
  my $l = $_;

  $l =~ s/[\r\n]//g;
  Encode::_utf8_on($l);

  if ($l =~ /[\w]+/) {
    if (!$c) {
      $c->{'title'} = $l;
      $c->{'para'} = [];
      next;
    }

    push(@{$c->{'para'}}, preprocess($l));
  }
  else {
    if ($c) {
      dump_c($c);
      $c = undef;
    }
  }
}
close($f);

if ($c) {
  dump_c($c);
}

if ($tag ne "formalpara" && $c_counter % 10 ne 0) {
  print "</sect1>\n";
}
