package IOW::Getopt2;

use strict;
use warnings;

use IOW::Basic;
use Data::Dumper;
use Getopt::Long;

use base 'Exporter';
our @EXPORT = qw(
    get_options
);

sub get_options {
    # two ways of usage: one parameter or hash parameters
    my %params = (scalar @_ == 1 and ref($_[0]) eq 'ARRAY') ? (opts => $_[0]) : hash_params(@_);

    # common options values storage instead of variables
    my $values;
    if (exists $params{var}) {
        $values = $params{var};
        die("Incorrect 'var' parameter value: ", Dumper($values)) if (ref($values) ne 'HASH');
    }

    # options to get
    my @opts = @{ $params{opts} // [] };
    my %opts;
    my %names;

    # check options and prepare hash to pass to GetOptions()
    for my $option (@opts) {
        die('Incorrect command line option specification: ', Dumper($option)) unless (
            ref($option) eq 'HASH'
                and
            ref($option->{name} // {}) eq ''
                and
            $values ? (not exists $option->{var}) : ref($option->{var})
                and
            ref($option->{desc} // {}) eq ''
        );

        # substitute with a copy
        $option = { %$option };

        my @option_names = split(/\|/, $option->{name});
        for my $name (@option_names) {
            die("'$name' option name/alias met more than once") if (exists $names{$name});
            $names{$name} = 1;
        }
        my $main_name = $option->{main_name} = $option_names[0];

        $opts{ $option->{name} . ($option->{arg} // '') } = $option->{var};

        unless (defined $option->{default}) {
            my $var = $values ? $values->{$main_name} : $option->{var};
            $var = $$var if (ref($var) eq 'SCALAR');
            $option->{default} = $var unless (ref($var));
        }
        $option->{default} =~ s/^(.*\s.*|)$/"$1"/ if (defined $option->{default});
    }

    # add help option
    my @help = grep { not exists $names{$_} } qw(help ?);
    my $help = 0;
    if (join('', @help) !~ /^\??$/) {
        my $name = join('|', @help);
        $opts{$name} = \$help;
        $values->{ $help[0] } = \$help if ($values);
        unshift(@opts, {
            name => $name,
            var => \$help,
            desc => 'display this help and exit',
        });
    }

    # get options from command line
    my $argv = [@ARGV];
    Getopt::Long::GetOptionsFromArray($argv, ($values ? ($values, keys %opts) : %opts))
        or print_help(opts => \@opts);

    # print help if requested
    print_help(opts => \@opts) if ($help);
    delete $values->{ $help[0] } if ($values and @help);
}

sub print_help {
    my %params = hash_params(@_);

    my @opts;
    my $max_name_len = 0;

    for my $option (@{ $params{opts} }) {
        my @names;
        for my $name (split(/\|/, $option->{name})) {
            for my $prefix ('', (defined $option->{arg} and $option->{arg} =~ /^!$/) ? 'no-' : ()) {
                push(@names, (length($name) > 1 ? '--' : '-') . $prefix . $name);
            }
        }
        my $name = join(', ', @names);

        $name .= " (=$option->{default})" if (defined $option->{default});

        push(@opts, { name => $name, desc => $option->{desc} });
        $max_name_len = length($name) if ($max_name_len < length($name));
    }

    print("$params{message}\n") if ($params{message});

    print("\nOptions:\n");
    printf("  %-${max_name_len}s  %s\n", @$_{ qw(name desc) }) for (@opts);

    exit($params{exit_code} // 1) unless ($params{no_exit});
}

1;
