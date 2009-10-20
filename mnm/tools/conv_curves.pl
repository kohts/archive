#!/usr/bin/perl -w

use strict;
use utf8;

binmode STDOUT, ':encoding(UTF-8)';

if (!$ARGV[0]) {
  die "usage: $0 filename\n";
}

sub safe {
  my ($l) = @_;
  if (defined($l)) {
    return $l;
  }
  else {
    return "";
  }
}

my $d = {
  'order' => [],
  };
my $cur_sid = undef;

my $f;
open($f, $ARGV[0]);
binmode $f, ':encoding(UTF-8)';
while (<$f>) {
  my $l = $_;
  
  if ($l =~ /equation id=\"(.+?)\"/) {
    $cur_sid = $1;
    if (!$cur_sid) {
      die "invalid line: $l";
    }
    
    $d->{$cur_sid} = {};
    push(@{$d->{'order'}}, $cur_sid);
    next;
  }
  if ($l =~ /\<\/equation\>/) {
    $cur_sid = undef;
    next;
  }
  next unless $cur_sid;

  if ($l =~ /\<title\>(.+?)\<\/title\>/) {
    $d->{$cur_sid}->{'title'} = $1;
    next;
  }
  if ($l =~ /<mediaobject><textobject><para>/) {
    $d->{$cur_sid}->{'in_para'} = 1;
    $d->{$cur_sid}->{'para'} = '';
    next;
  }
  if ($l =~ /<\/para><\/textobject><\/mediaobject>/) {
    $d->{$cur_sid}->{'in_para'} = 0;
    next;
  }
  
  if ($d->{$cur_sid}->{'in_para'}) {
    $d->{$cur_sid}->{'para'} .= $l;
  }  
}
close($f);

foreach my $i (@{$d->{'order'}}) {
  my $r_id = $i;
  $r_id =~ s/^eng_//;
  
  print
'
<formalpara id="' . $i . '">
  <title>' . $d->{$i}->{'title'} . '</title>
  <xref linkend="' . $r_id . '" /><?br?>
' . safe($d->{$i}->{'para'}) . '
</formalpara>
';

    
    
}

__END__
<formalpara id="eng_photo1">
  <title>Table <quote>The Macaque <quote>Dasy</quote> at quiet.</quote></title>
  <xref linkend="photo1" /><?br?>
 <?br?>
</formalpara>
