package IOW::File;

use strict;
use warnings;

# excerpt from Yandex::Tools
#
sub read_file_scalar {
    my ($filename) = @_;

    my $filecontent;
    unless (open F, $filename) {
        die("Couldn't open $filename for reading: $!");
    }
    { local $/ = undef; $filecontent = <F>; }
    close F;

    return $filecontent;
}

# read file, each line is an array element
#
sub read_file_array {
    my ($filename, $opts) = @_;
    $opts = {} unless $opts;

    my $arr = [];
    my $t = undef;
  
    if (-e $filename || $opts->{'mandatory'}) {
        $t = read_file_scalar($filename);
        @{$arr} = split(/\n/so, $t);
    }

    return $arr;
}

sub read_dir {
    my ($dirname, $opts) = @_;

    $opts = {} unless $opts;
    $opts->{'output_type'} = 'arrayref'
        unless $opts->{'output_type'};

    my $dummy;
    if (!opendir($dummy, $dirname)) {
        if ($opts->{'non_fatal'}) {
            return 0;
        }
        else {
            die("ERROR: unable to open directory [$dirname]");
        }
    }

    my @all_entries = readdir($dummy);
    close($dummy);

    my $entries;
    if ($opts->{'output_type'} eq 'arrayref') {
        $entries = [];
    }

    foreach my $e (sort @all_entries) {
      next if $e eq '.' || $e eq '..';

      my $absolute_name = $dirname . "/" . $e;

      if ($opts->{'output_type'} eq 'arrayref') {
          # skipping non-directories if requested
          # effectively means "get only files";
          if ($opts->{'only-directories'}) {
              next if -l $absolute_name || ! -d $absolute_name;
          }
          
          # symlinks are also files
          if ($opts->{'only-files'}) {
              next if -d $absolute_name && ! -l $absolute_name;
          }

          # simple output, feasible only
          # for non-recursive directory reads
          push(@{$entries}, $e);
        }
    }

    return $entries;
}

sub write_file_scalar {
    my ($filename, $value, $opts) = @_;

    $opts = {} unless $opts;
    my $fh = safe_open($filename, "overwrite", {'timeout' => $opts->{'timeout'} || 2});
    return 0 unless $fh;

    $value = "" unless defined($value);

    print $fh $value;
    safe_close($fh);
}

sub append_file_scalar {
    my ($filename, $value, $opts) = @_;

    $opts = {} unless $opts;
    my $fh = safe_open($filename, "append", {'timeout' => $opts->{'timeout'} || 2});
    return 0 unless $fh;

    $value = "" unless defined($value);

    print $fh $value;
    safe_close($fh);
}

sub safe_open {
    my ($filename, $mode, $opts) = @_;

    $opts = {} unless $opts;
    $opts->{'timeout'} = 30 unless defined($opts->{'timeout'});

    $mode = "open" unless $mode;

    if ($mode eq "overwrite" || $mode eq ">") {
        $mode = ">";
    }
    elsif ($mode eq "append" || $mode eq ">>") {
        $mode = ">>";
    }
    else {
        $mode = "";
    }

    my $fh;
    my $i=0;
    while (! open($fh, "${mode}${filename}")) {
        $i = $i + 1;
        if ($i > $opts->{'timeout'}) {
            print STDERR "Unable to open $filename\n" if ! $opts->{'silent'};
            return 0;
        }

        print STDERR "still trying to open $filename\n" if ! $opts->{'silent'};
        sleep 1;
    }

    # http://perldoc.perl.org/functions/flock.html
    #
    # LOCK_SH, LOCK_EX, LOCK_UN, LOCK_NB <=> 1, 2, 8, 4
    #
    # If LOCK_NB is bitwise-or'ed with LOCK_SH or LOCK_EX
    # then flock will return immediately

    while (! flock($fh, 2 | 4)) {
        $i = $i + 1;
        if ($i > $opts->{'timeout'}) {
          print STDERR "Unable to lock $filename: $!\n" if ! $opts->{'silent'};
          return 0;
        }

        print STDERR "still trying to lock $filename: $!\n" if ! $opts->{'silent'};
        sleep 1;
    }

    my $fh1;
    if (!open($fh1, "${mode}${filename}")) {
        $i = $i + 1;
        if ($i > $opts->{'timeout'}) {
            print STDERR "Unable to open and lock $filename\n" if ! $opts->{'silent'};
            return 0;
        }

        print STDERR "Locked $filename, but it's gone. Retrying...\n" if ! $opts->{'silent'};
        $opts->{'timeout'} = $opts->{'timeout'} - 1;
        return safe_open($filename, $mode, $opts);
    }
    else {
        close($fh1);
        return $fh;
    }
}

sub safe_close {
    my ($fh) = @_;
    return flock($fh, 8) && close($fh);
}


1;
