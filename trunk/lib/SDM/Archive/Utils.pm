package SDM::Archive::Utils;

use strict;
use warnings;

our $month_abbr = [qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)];

sub is_unixtime {
  my ($t) = @_;

  return undef unless defined ($t);

  return ($t =~ /^[\d]+$/o);
}

=item get_time()

 Given unix timestamp returns time hashref with meaningful keys.

 Example:

$VAR1 = {
          'wday' => 3,
          'month_word' => 'Aug',
          'hour' => 8,
          'month' => 8,
          'min' => 49,
          'isdst' => 0,
          'sec' => 48,
          'yday' => 241,
          'mday' => 29,
          'year' => 2012
        };

=cut

sub get_time {
    my ($now) = @_;

    $now = time() unless defined($now);
    Carp::confess("Programmer error: invalid unix time [" . Pontis::Utils::safe_string($now) . "]")
        unless SDM::Archive::Utils::is_unixtime($now);

    my @now = gmtime($now);

    my $r = {
        'sec' => $now[0],
        'sec_padded' => sprintf("%02d", $now[0]),
        'min' => $now[1],
        'min_padded' => sprintf("%02d", $now[1]),
        'hour' => $now[2],
        'hour_padded' => sprintf("%02d", $now[2]),
        'mday' => $now[3],
        'mday_padded' => sprintf("%02d", $now[3]),
        'month' => $now[4] + 1,
        'month_padded' => sprintf("%02d", $now[4] + 1),
        'month_word' => $month_abbr->[$now[4]],
        'year' => $now[5],
        'wday' => $now[6],
        'yday' => $now[7],
        'isdst' => $now[8],
        'orig_unixtime' => $now,
        };

    $r->{'year'} =  $r->{'year'} + 1900;

    return $r;
}

sub is_integer {
    my ($text, $opts) = @_;

    return undef unless defined($text);

    $text =~ s/\.0+$//;

    if ($opts && $opts->{'positive-only'}) {
        return $text =~ /^\d+$/;
    }
    else {
        return $text =~ /^\-?\d+$/;
    }
}

sub is_datetime {
    my ($in) = @_;

    if ($in && $in =~ /(\d\d\d\d)[\-\/ \:](\d\d)[\-\/\ \:](\d\d)[\-\/\ \:](\d\d)[\-\/\ \:](\d\d)[\-\/\ \:](\d\d)/) {
        return 1;
    } else {
        return 0;
    }
}

sub datetime_to_unixtime {
    my ($date) = @_;

    Carp::confess("Programmer error: expected YYYY-MM-DD-HH-MM-SS")
        unless is_datetime($date);

    $date =~ /^(\d\d\d\d)[\-\/\ \:](\d\d)[\-\/\ \:](\d\d)[\-\/\ \:](\d\d)[\-\/\ \:](\d\d)[\-\/\ \:](\d\d)$/;
    my ($year, $month, $day, $hour, $minute, $second) = ($1, $2, $3, $4, $5, $6);

    my $unixtime = Time::Local::timegm($second, $minute, $hour, $day, $month - 1, $year);

    return $unixtime;
}

1;
