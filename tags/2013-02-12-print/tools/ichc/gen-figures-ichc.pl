#!/usr/bin/perl -w

use strict;
use utf8;
use Encode;

if (!$ARGV[0]) {
  die "usage: $0 filename [rus|eng] [table_pfx] [figure|example|formalpara]\n";
}

my $language = $ARGV[1] ? $ARGV[1] : "rus";
my $table_pfx = $ARGV[2] ? $ARGV[2] : "table";
my $tag = $ARGV[3] ? $ARGV[3] : "example";

my $c_counter = 0;
my $c;

sub dump_c {
  my ($c) = @_;

  if ($tag ne "formalpara") {
    if ($c_counter ne 0) {
      print "<?page-break?>\n";
    }

    if ($c_counter eq 0 ||
      $c_counter % 10 eq 0) {

      my $p = $c_counter / 10;
    
      my $pfx = "";
      if ($language ne "rus") {
        $pfx = $language . "_";
      }
    
      print "<sect1 id='${pfx}photoplates_" . $p . "'><title>" . ($p * 10 + 1) . " &mdash; " . ($p*10 + 10) . "</title>\n";
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
open($f, $ARGV[0]);
while (<$f>) {
  my $l = $_;

  $l =~ s/[\r\n]//g;
  Encode::_utf8_on($l);

  if ($l =~ /[\w]+/) {
    if (!$c) {
      $c->{'title'} = $l;
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
