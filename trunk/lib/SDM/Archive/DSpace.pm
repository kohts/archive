package SDM::Archive::DSpace;

use strict;
use warnings;

sub rest_call {
    my ($o) = @_;

    $o = {} unless $o;

    Carp::confess("Programmer error: need action or link, verb (get or post), request_type (json or xml)")
        unless ($o->{'action'} || $o->{'link'}) && $o->{'verb'} && $o->{'request_type'};

    Carp::confess("Need dspace_rest_url configuration option in /etc/aconsole.pl")    
        unless defined($SDM::Archive::data_desc_struct->{'dspace_rest_url'});
    Carp::confess("Need dspace_upload_user_email configuration option in /etc/aconsole.pl")    
        unless defined($SDM::Archive::data_desc_struct->{'dspace_upload_user_email'});
    Carp::confess("Need dspace_upload_user_pass configuration option in /etc/aconsole.pl")    
        unless defined($SDM::Archive::data_desc_struct->{'dspace_upload_user_pass'});

    Carp::confess("verb must be one of [get,post]; got [" . safe_string($o->{'verb'}) . "]")
        unless $o->{'verb'} eq "get" || $o->{'verb'} eq 'post';
    $o->{'verb'} = uc($o->{'verb'});

    my $ua = LWP::UserAgent->new;
    $ua->default_header('accept' => "application/" . $o->{'request_type'});
    $ua->default_header('Content-Type' => "application/" . $o->{'request_type'} . ";charset=utf-8");

    if (!$o->{'dspace_token'}) {
        if (!defined($o->{'action'}) || $o->{'action'} ne 'login') {
            if (!defined($SDM::Archive::runtime->{'dspace_rest'}->{'token'})) {
                my $login_token = SDM::Archive::DSpace::rest_call({
                    'verb' => 'post',
                    'action' => 'login',
                    'request' =>
                        '{"email": "' . $SDM::Archive::data_desc_struct->{'dspace_upload_user_email'} .
                        '", "password": "' . $SDM::Archive::data_desc_struct->{'dspace_upload_user_pass'} .
                        '"}',
                    'request_type' => 'json',
                    'dspace_token' => '',
                    });
                Carp::confess("Unable to login: $!")
                    if !$login_token;

                #print $login_token . "\n";
                $SDM::Archive::runtime->{'dspace_rest'}->{'token'} = $login_token; 
            }
            $o->{'dspace_token'} = $SDM::Archive::runtime->{'dspace_rest'}->{'token'};
            $ua->default_header('rest-dspace-token' => $o->{'dspace_token'});
        }
    }

    my $req;
    my $dspace_server = $SDM::Archive::data_desc_struct->{'dspace_rest_url'};
    if ($dspace_server =~ m%(http://[^/]+)%) {
        $dspace_server = $1;
    }
    
    if ($o->{'action'}) {
        $req = HTTP::Request->new($o->{'verb'} => $SDM::Archive::data_desc_struct->{'dspace_rest_url'} . "/" . $o->{'action'});
    }
    else {
        $req = HTTP::Request->new($o->{'verb'} => $dspace_server . $o->{'link'});
    }
    
    if ($o->{'request'}) {
        $req->content(Encode::encode_utf8($o->{'request'}));
    }
    elsif ($o->{'request_binary'}) {
        $req->content($o->{'request_binary'});
    }
    else {
        $req->content();
    }

    my $r = $ua->request($req);

    if (!$r->is_success || $r->code ne 200) {
        if ($o->{'ignore_error'}) {
            Carp::carp("Unable to get data while doing [" . Data::Dumper::Dumper($o) . "] from [" .
                $SDM::Archive::data_desc_struct->{'dspace_rest_url'} .
                "]: " . $r->status_line);
        }
        else {
            Carp::confess("Unable to get data while doing [" . Data::Dumper::Dumper($o) . "] from [" .
                $SDM::Archive::data_desc_struct->{'dspace_rest_url'} . "]: " . $r->status_line);
        }
    }
    
    return $r->content;
}

sub get_community_by_name {
    my ($community_name, $o) = @_;

    $o = {} unless $o;

    my $communities = SDM::Archive::DSpace::rest_call({
        'verb' => 'get',
        'action' => 'communities',
        'request' => '{}',
        'request_type' => 'json',
        });

    my $comm_struct;
    eval {
        $comm_struct = JSON::decode_json($communities);
    };
    if ($@) {
        Carp::confess("Error parsing communities json: " . $@);
    }

    my $target_community;
    foreach my $c (@{$comm_struct}) {
        if ($c->{'name'} eq $community_name) {
            if ($target_community) {
                Carp::confess("More than one community matches name [" . $community_name . "]");
            }

            $target_community = $c;
        }
    }

    return $target_community;
}

sub get_collection {
    my ($o) = @_;

    $o = {} unless $o;

    Carp::confess("Programmer error: need at least collection_name")
        unless $o->{'collection_name'};
    
    if ($o->{'community_obj'}) {
        my $collections = SDM::Archive::DSpace::rest_call({
            'verb' => 'get',
            'link' => $o->{'community_obj'}->{'link'} . "/collections",
            'request' => '{}',
            'request_type' => 'json',
            });
        my $coll_struct;
        eval {
            $coll_struct = JSON::decode_json($collections);
        };
        if ($@) {
            Carp::confess("Error parsing json: " . $@);
        }

    #    print Data::Dumper::Dumper($coll_struct);
        my $target_collection;
        foreach my $c (@{$coll_struct}) {
            if ($target_collection) {
                Carp::confess("More than one collection matches name [" . $o->{'collection_name'} . "]");
            }

            if ($c->{'name'} eq $o->{'collection_name'}) {
                $target_collection = $c;
            }
        }

        return $target_collection; 
    }
    else {
        return SDM::Archive::DSpace::get_collection_by_name($o->{'collection_name'});
    }
}

sub get_collection_by_name {
    my ($collection_name, $o) = @_;

    $o = {} unless $o;

    my $collections = SDM::Archive::DSpace::rest_call({
        'verb' => 'get',
        'action' => 'collections',
        'request' => '{}',
        'request_type' => 'json',
        });

    my $coll_struct;
    eval {
        $coll_struct = JSON::decode_json($collections);
    };
    if ($@) {
        Carp::confess("Error parsing collections json: " . $@);
    }

    my $target_collection;

    foreach my $c (@{$coll_struct}) {
        if ($c->{'name'} eq $collection_name) {
            if ($target_collection) {
                Carp::confess("More than one collection matches name [" . $collection_name . "]");
            }

            $target_collection = $c;
        }
    }

    return $target_collection;
}

sub get_collection_items {
    my ($o) = @_;

    $o = {} unless $o;

    Carp::confess("Programmer error: need collection_obj")
        unless defined($o->{'collection_obj'});

    my $items = SDM::Archive::DSpace::rest_call({
        'verb' => 'get',
        'link' => $o->{'collection_obj'}->{'link'} . "/items/?expand=metadata",
        'request' => '{}',
        'request_type' => 'json',
        });
    my $items_struct;
    eval {
        $items_struct = JSON::decode_json($items);
    };
    if ($@) {
        Carp::confess("Error parsing items json: " . $@);
    }

    return $items_struct;
}

sub get_metadata_by_key {
    my ($metadata_array, $key, $o) = @_;

    $o = {} unless $o;

    my $out_values;
    foreach my $m (@{$metadata_array}) {
        next unless $m->{'key'} eq $key;

        if ($out_values) {
            if (defined($o->{'unique-values'})) {
                Carp::confess("Data consistency error: expected unique metadata value for key [$key]; got several; metadata structure:" .
                    Data::Dumper::Dumper($metadata_array));
            }

            $out_values = [$out_values, $m];
        }
        else {
            $out_values = $m;
        }
    }
    return $out_values;
}

sub get_item {
    my ($o) = @_;

    $o = {} unless $o;

    Carp::confess("Programmer error: need collection_obj")
        unless defined($o->{'collection_obj'});
    
    if (defined($o->{'storage_group'}) && defined($o->{'storage_item'})) {
        my $items = SDM::Archive::DSpace::get_collection_items({
            'collection_obj' => $o->{'collection_obj'},
            });

        return undef unless $items;

        foreach my $i (@{$items}) {
            my $storage_group = get_metadata_by_key($i->{'metadata'}, 'sdm-archive.misc.inventoryGroup', {'unique-value' => 1});
            my $storage_item = get_metadata_by_key($i->{'metadata'}, 'sdm-archive.misc.storageItem', {'unique-value' => 1});
            
            if ($storage_group->{'value'} eq 'Novikova' && $o->{'storage_group'} eq 1 &&
                $storage_item->{'value'} eq $o->{'storage_item'}) {

                return $i;
            }
        }
    }
    elsif (defined($o->{'item_id'})) {
        my $rest_top = $o->{'collection_obj'}->{'link'};
        $rest_top =~ s/\/collections\/.+$//;
        my $item = SDM::Archive::DSpace::rest_call({
            'verb' => 'get',
            'link' => $rest_top . '/items/' . $o->{'item_id'} . "/?expand=all",
            'request' => '{}',
            'request_type' => 'json',
            });

        my $struct;
        eval {
            $struct = JSON::decode_json($item);
        };
        if ($@) {
            Carp::confess("Error parsing items json: " . $@);
        }
        return $struct;
    }
    else {
        Carp::confess("Programmer error: need item parameters");
    }
}

return 1;
