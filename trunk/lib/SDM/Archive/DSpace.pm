package SDM::Archive::DSpace;

use strict;
use warnings;

sub rest_call {
    my ($o) = @_;

    $o = {} unless $o;

    Carp::confess("Programmer error: need action or link, verb (get, post or put), request_type (json or xml)")
        unless ($o->{'action'} || $o->{'link'}) && $o->{'verb'} && $o->{'request_type'};

    Carp::confess("Need dspace_rest_url configuration option in /etc/aconsole.pl")    
        unless defined($SDM::Archive::data_desc_struct->{'dspace_rest_url'});
    Carp::confess("Need dspace_upload_user_email configuration option in /etc/aconsole.pl")    
        unless defined($SDM::Archive::data_desc_struct->{'dspace_upload_user_email'});
    Carp::confess("Need dspace_upload_user_pass configuration option in /etc/aconsole.pl")    
        unless defined($SDM::Archive::data_desc_struct->{'dspace_upload_user_pass'});

    Carp::confess("verb must be one of [get,post,put]; got [" . safe_string($o->{'verb'}) . "]")
        unless $o->{'verb'} eq "get" || $o->{'verb'} eq 'post' || $o->{'verb'} eq 'put';
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

    if (!$SDM::Archive::runtime->{'dspace_rest'}->{'dspace_server'}) {
        $SDM::Archive::runtime->{'dspace_rest'}->{'dspace_server'} = $dspace_server;
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
            if ($c->{'name'} eq $o->{'collection_name'}) {
                if ($target_collection) {
                    Carp::confess("More than one collection matches name [" . $o->{'collection_name'} . "]");
                }

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

    my $expand_key = "metadata";
    if (defined($o->{'expand'})) {
        $expand_key = $o->{'expand'};
    }
    my $limit = $o->{'limit'} || 100;

    my $get_params = [];
    if ($expand_key) {
        push @{$get_params}, "expand=" . $expand_key;
    }
    if ($limit) {
        push @{$get_params}, "limit=" . $limit;
    }

    my $link = $o->{'collection_obj'}->{'link'} . "/items/" .
            (scalar(@{$get_params}) ? "?" . join("&", @{$get_params}) : "");

    $SDM::Archive::runtime->{'dspace_rest'}->{'full_collections'} = {}
        unless defined($SDM::Archive::runtime->{'dspace_rest'}->{'full_collections'});

    my $items;
    if (defined($SDM::Archive::runtime->{'dspace_rest'}->{'full_collections'}->{$link}) &&
        !defined($o->{'refresh-cache'})) {
        $items = $SDM::Archive::runtime->{'dspace_rest'}->{'full_collections'}->{$link};
    }
    else {
        $items = SDM::Archive::DSpace::rest_call({
            'verb' => 'get',
            'link' => $link,
            'request' => '{}',
            'request_type' => 'json',
            });
        $SDM::Archive::runtime->{'dspace_rest'}->{'full_collections'}->{$link} = $items;
    }
        
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

        if ($o->{'language'} && $m->{'language'} &&
            $o->{'language'} ne $m->{'language'}) {
            next;
        }

        if ($out_values) {
            if (defined($o->{'unique-values'})) {
                Carp::confess("Data consistency error: expected unique metadata value for key [$key]; got several; metadata structure:" .
                    Data::Dumper::Dumper($metadata_array));
            }

            if (ref($out_values) eq 'ARRAY') {
                $out_values = [@{$out_values}, $m];
            }
            else {
                $out_values = [$out_values, $m];
            }
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
        my $item_id = $o->{'item_id'};
        
        if (SDM::Archive::DSpace::is_handle($item_id)) {
            my $item = SDM::Archive::DSpace::get_item_by_handle({
                'collection' => $o->{'collection_obj'},
                'handle' => $item_id,
                });
            Carp::confess("Invalid handle [$item_id]")
                unless $item;
            $item_id = $item->{'id'};
        }

        my $rest_top = $o->{'collection_obj'}->{'link'};
        $rest_top =~ s/\/collections\/.+$//;
        my $item = SDM::Archive::DSpace::rest_call({
            'verb' => 'get',
            'link' => $rest_top . '/items/' . $item_id . "/?expand=all",
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

sub get_item_by_handle {
    my ($o) = @_;

    $o = {} unless $o;

    Carp::confess("Programmer error: need collection object")
        unless $o->{'collection'};
    Carp::confess("Programmer error: need collection object")
        unless $o->{'handle'};

    my $coll_items = SDM::Archive::DSpace::get_collection_items({
        'collection_obj' => $o->{'collection'},
        'limit' => $o->{'limit'} || 4000,
        'expand' => '',
        });

    ITEMS: foreach my $item (@{$coll_items}) {
        if ($item->{'handle'} eq $o->{'handle'}) {
            return $item;
        }
    }

    return undef;
}

sub change_item_metadata {
    my ($action, $o) = @_;

    $o = {} unless $o;

    Carp::confess("Programmer error: action should be either update or append, got [" . SDM::Archive::safe_string($action) . "]")
        unless $action && ($action eq 'update' || $action eq 'append');

    Carp::confess("Programmer error: need item")
        unless $o->{'item'};
    Carp::confess("Programmer error: need metadata struct")
        unless
            $o->{'metadata'} &&
            ref($o->{'metadata'}) eq 'HASH' &&
            defined($o->{'metadata'}->{'key'}) &&
            defined($o->{'metadata'}->{'value'}) &&
            defined($o->{'metadata'}->{'language'});
    Carp::confess("Programmer error: got perl structure [" . ref($o->{'metadata'}->{'value'}) .
        "] instead of scalar as metadata value")
        if ref($o->{'metadata'}->{'value'}) ne '';

    my $res = SDM::Archive::DSpace::rest_call({
        'verb' => ($action eq 'append' ? 'post' : 'put'),
        'action' => 'items/' . $o->{'item'}->{'id'} . "/metadata",
        'request' => '[
              {"key": "' . $o->{'metadata'}->{'key'} .
              '", "value": "' . $o->{'metadata'}->{'value'} .
              '", "language": "' . SDM::Archive::safe_string($o->{'metadata'}->{'language'}) .
              '"}
            ]',
        'request_type' => 'json',
        });
    
    SDM::Archive::do_log(
        "dspace server [" . $SDM::Archive::runtime->{'dspace_rest'}->{'dspace_server'} . "] " .
        "item [" . $o->{'item'}->{'id'} . " " . $o->{'item'}->{'handle'} .
        "] metadata [" . $o->{'metadata'}->{'key'} . "] " .
        ($action eq 'append' ? 'appended' : 'updated') .
        " with [" . $o->{'metadata'}->{'value'} . "]");

    return $res;
}

sub add_item_metadata {
    return change_item_metadata("append", @_);
}

sub update_item_metadata {
    return change_item_metadata("update", @_);
}

sub item_list_print {
    my ($o) = @_;

    $o = {} unless $o;

    Carp::confess("Programmer error: need collection_obj and item_id")
        unless $o->{'collection_obj'} && $o->{'item_id'};

    my $item = SDM::Archive::DSpace::get_item({
        'collection_obj' => $o->{'collection_obj'},
        'item_id' => $o->{'item_id'},
        });
    
    my $res;

    my $desc = SDM::Archive::DSpace::get_metadata_by_key($item->{'metadata'}, 'dc.description');
    if (ref($desc) eq 'ARRAY') {
        my $id = SDM::Archive::DSpace::get_metadata_by_key($item->{'metadata'}, 'dc.identifier.other', {'language' => 'ru'});
        $res = join(" ", $item->{'id'}, $item->{'handle'}, $id->{'value'});
    }
    else {
        $res = join(" ", $item->{'id'}, $item->{'handle'}, $desc->{'value'});
    }

    return $res;
}

sub is_handle {
    my ($s) = @_;
    return ($s && $s =~ /^\d+\/\d+$/);
}

return 1;
