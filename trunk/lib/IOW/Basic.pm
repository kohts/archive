package IOW::Basic;

use strict;
use warnings;
use Carp;

use Data::Dumper;

use base 'Exporter';
our @EXPORT = qw(
    hash_params
    detect_params
    check_params
    deep_copy
);

# check passed parameters to convert them to hash
sub hash_params {
    my @params = @_;

    # there should be even number of parameters
    die('Invalid parameters passed: ', Dumper(\@params)) if (scalar @params % 2);

    # odd parameters should be scalars
    for my $i (grep { $_ % 2 == 0 } 0 .. $#params) {
        die('Invalid parameters passed: ', Dumper(\@params)) if (ref($params[$i]));
    }

    return @params;
}

sub detect_params {
    my ($params, @expected) = @_;

    return hash_params(@$params) if (scalar @$params != scalar @expected);
    return map { $expected[$_] => $params->[$_] } 0 .. $#expected;
}

sub check_params {
    my %params = hash_params(@_);

    my $ok = 1;
    my @mandatory = @{ $params{mandatory} // [] };
    for my $param (@mandatory) {
        unless (exists $params{params}{$param}) {
            carp("Mandatory parameter '$param' is missing");
            $ok = '';
        }
    }

    return $ok if (exists $params{optional} and not defined $params{optional});

    my @known = ( @mandatory, @{ $params{optional} // [] } );
    for my $param (sort keys %{ $params{params} }) {
        unless (scalar(grep {$param eq $_} @known)) {
            carp("Unknown parameter '$param' passed");
            $ok = '';
        }
    }

    return $ok;
}

# recursively make copy of arbitrary data structure for persistence (in RAM, not in disk)
sub deep_copy {
    my $orig = shift;
    my $ref = ref($orig);

    if ($ref =~ /^(|CODE|GLOB|LVALUE|FORMAT|IO|VSTRING)$/) {
        my $copy = $orig;
        return $copy;
    }
    elsif ($ref =~ /^(SCALAR|REF)$/) {
        my $copy = deep_copy($$orig);
        return \$copy;
    }   
    elsif ($ref eq 'ARRAY') {
        my @copy = @$orig;
        $_ = deep_copy($_) for (@copy);
        return \@copy;
    } 
    elsif ($ref eq 'HASH') {
        my %copy = %$orig;
        $_ = deep_copy($_) for (values %copy);
        return \%copy;
    }                  
    elsif ($ref eq 'Regexp') { 
        return qr/$orig/;      
    }   
}

1;
