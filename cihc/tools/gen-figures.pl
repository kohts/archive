#!/usr/bin/perl -w

use strict;
use utf8;
use Encode;

if (!$ARGV[0]) {
  die "usage: $0 filename\n";
}

my $c_counter = 0;
my $c;

sub dump_c {
  my ($c) = @_;

  $c_counter++;
 
  my $t = "table" . $c_counter;

print '<example id="' . $t . '">
  <title>' . $c->{'title'} . '</title>
  <mediaobject>
    <imageobject role="html"><imagedata fileref="images/html/' . $t . '.jpg" /></imageobject>
    <imageobject role="fo"><imagedata fileref="images/pdf/' . $t . '.jpg" /></imageobject>
  </mediaobject>
  <mediaobject>
    <textobject role="html">
      <ulink role="html" url="images/hires/' . $t . '.jpg">в большем разрешении</ulink>
    </textobject>
  <textobject role="fo"></textobject>
  </mediaobject>
  <mediaobject><textobject><para>
' . join("<?br?>\n", @{$c->{'para'}}) . "<?br?>\n"  .
'  </para></textobject></mediaobject>
</example>

';

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

    push(@{$c->{'para'}}, $l);
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
