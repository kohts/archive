package SDM::Archive::DB;

use strict;
use warnings;
use SDM::Archive;

our $db_cache = {};

sub get_kamis_db {
    my $dbh = SDM::Archive::DB::get_db({
        'host' => 'localhost',
        'user' => 'root',
        'pass' => '',
        'dbname' => 'kamis_import',
        });
    Carp::confess("Unable to connect to kamis_import database: " . $DBI::errstr)
        unless $dbh;

    if ($dbh->{'private_R2D2'}->{'from_cache'}) {
        return $dbh;
    }

    $dbh->{'private_R2D2'} = {} unless defined($dbh->{'private_R2D2'});

    return $dbh;
}

# build dsn ready to be used by DBI from hashref with keys
#
sub make_dbh_dsn {
    my ($db) = @_;   # hashref with DSN info
    return $db->{'_dsn'} if $db->{'_dsn'};  # already made?

    my $dsn = "DBI:mysql";  # join("|",$dsn,$user,$pass) (because no refs as hash keys)
    $dsn .= ":$db->{'dbname'}";
    $dsn .= ";host=$db->{'host'}" if $db->{'host'};
    $dsn .= ";port=$db->{'port'}" if $db->{'port'};
    $dsn .= ";mysql_socket=$db->{'sock'}" if $db->{'sock'};
    $dsn .= ";mysql_connect_timeout=$db->{'connect_timeout'}" if $db->{'connect_timeout'};

    $db->{'_dsn'} = $dsn;
    return $dsn;
}


# test if connection is still available
# (replication, non-latin symbols, etc.)
#
# returns the number of seconds to wait
# until next connection retry
#
sub connection_bad {
    my ($dbh, $opts) = @_;
    
    $opts = {} unless $opts;

    return 5 if !$dbh || (ref($dbh) ne "DBI::db");

    my $ss = eval {
        $dbh->selectrow_hashref("select unix_timestamp();");
    };
    

    #http://dev.mysql.com/doc/refman/5.0/en/error-messages-server.html
    #
    # Error: 1227 SQLSTATE: 42000 (ER_SPECIFIC_ACCESS_DENIED_ERROR)
    # Message: Access denied; you need the %s privilege for this operation
    #
    if ($dbh->err && $dbh->err != 1227) {
        print STDERR localtime() . " [$$]: " . $dbh->errstr . "\n" if $ENV{'MAGIC_DEBUG'};
        return 5;
    }
    
    if (!$ss || !$ss->{'unix_timestamp()'}) {
        print STDERR " [$$]: select unix_timestamp() didn't return a value\n";
        return 0.1;
    }

    # connection seems to be ok.
    return 0;
}

sub get_db {
    my ($db, $opts) = @_;

    Carp::confess("Programmer error: invalid db struct")
        unless ref($db) eq 'HASH';

    $opts //= {};

    $db->{'pass'} = $db->{'password'} if !$db->{'pass'} && $db->{'password'};
    $db->{'port'} = 3306 unless $db->{'port'};

    my $missing_elements = [];
    foreach my $e (qw/dbname host port user pass/) {
        if (!defined($db->{$e})) {
            push (@{$missing_elements}, $e);
        }
    }
    if (scalar(@{$missing_elements}) > 0) {
        Carp::confess ("Programmer error: db struct requires following elements: " . join(",", @{$missing_elements}));
    }
    
    my $cache_id_string = join(":", map {$db->{$_}} sort keys %{$db});

    if ($db_cache->{$cache_id_string}) {
        if (!SDM::Archive::DB::connection_bad($db_cache->{$cache_id_string})) {
          $db_cache->{$cache_id_string}->{'private_R2D2'}->{'from_cache'} = time();
          return $db_cache->{$cache_id_string};
        }
        $db_cache->{$cache_id_string} = undef;
    }

    my $dsn = make_dbh_dsn($db);
    my $dbh;

    my $tz_adjustment;

    my $loop = 1;
    my $tries = 8;
    while ($loop) {
        $loop = 0;
       
        my $connect_options = {
            #
            # dbh options should be set with quation
            # because handles are cached and might be
            # reused later expecting defaults (shown below)
            #
            PrintError => $opts->{'PrintError'} || 0, # from DBI-1.613 documentation:
                                                      # 
                                                      #   The PrintError attribute can be used to force errors
                                                      #   to generate warnings (using warn) in addition
                                                      #   to returning error codes in the normal way.
                                                      #   When set "on", any method which results in an error occurring
                                                      #   will cause the DBI to effectively do a
                                                      #   warn("$class $method failed: $DBI::errstr") 
                                                      #
                                                      #   By default, DBI->connect sets PrintError "on".
                                                      #
                                                      # we set it to off, to cope with log pollution
                                                      # and to promote error handling.
                                                      #

            RaiseError => $opts->{'RaiseError'} || 0, # from DBI-1.613 documentation:
                                                      # 
                                                      #   The RaiseError attribute can be used to force errors
                                                      #   to raise exceptions rather than simply return error codes
                                                      #   in the normal way.
                                                      # 
                                                      #   It is "off" by default.
                                                      #
                                                      #   When set "on", any method which results in an error
                                                      #   will cause the DBI to effectively do a
                                                      #   die("$class $method failed: $DBI::errstr"),

            AutoCommit => $opts->{'AutoCommit'} || 1, # from DBI-1.613 documentation:
                                                      # 
                                                      #   If true, then database changes cannot be rolled-back (undone).
                                                      #   If false, then database changes automatically occur
                                                      #   within a "transaction", which must either be committed
                                                      #   or rolled back using the commit or rollback methods.
                                                      #
                                                      #   Drivers should always default to AutoCommit mode.
            mysql_enable_utf8 => 1,
            };

        $dbh = DBI->connect($dsn, $db->{'user'}, $db->{'pass'}, $connect_options);

        if (! $dbh) {
            # if max connections, try again shortly.
            if ($DBI::err == 1040 && $tries) {
                $tries--;
                $loop = 1;
                Time::HiRes::usleep(250_000);
            }
        }
        else {
            my $connection_id = $dbh->selectrow_array("select connection_id()");

            if ($connection_id) {
                $dbh->{'private_R2D2'}->{'connection_id'} = $connection_id;
                $dbh->{'private_R2D2'}->{'dsn'} = $dsn;

                if ($ENV{'MAGIC_DEBUG'}) {
                    print STDERR localtime() . " [$$]: db connection [$connection_id] dsn [$dsn]\n";
                }
            }
            else {
                print STDERR "[$$] got db connection without connection id\n";
                $tries--;
            }

            # Magic library expects all the time values to be GMT+0 internally,
            # making it generally timezone agnostic
#            $dbh->do("SET TIME_ZONE = '+00:00'") || Carp::confess("Unable to set timezone to UTC: " . $dbh->errstr);

            my $sth = SDM::Archive::DB::execute_statement({
                'dbh' => \$dbh,
                'sql' => "select NOW()",
                'bound_values' => [],
                });
            my $mysql_time = SDM::Archive::Utils::datetime_to_unixtime($sth->fetchrow_arrayref()->[0]);
            my $my_time = time();
            $tz_adjustment = $mysql_time - $my_time;
        }
    }

    my $seconds_to_retry = SDM::Archive::DB::connection_bad($dbh, $opts);

    if ($seconds_to_retry) {
      # do not leave possibly open connection
      $dbh->{'RaiseError'} = 0;
      $dbh->{'PrintError'} = 0;
      eval {
        $dbh->disconnect;
      };

      undef $dbh;
    } else {
        $dbh->{'private_R2D2'} = {
            'cached_at' => time(),
            'tz_adjustment' => $tz_adjustment,
            };
    }

    # update database connection cache
    $db_cache->{$cache_id_string} = $dbh;

    return $dbh;
}

sub execute_statement {
    my ($opts) = @_;

    $opts = {} unless $opts;
    $opts->{'bound_values'} = [] unless $opts->{'bound_values'};
    $opts->{'on_error'} = "die" unless $opts->{'on_error'};
    $opts->{'try'} = 1 unless $opts->{'try'};

    my $dbh_ref = $opts->{'dbh'};
    Carp::confess("Programmer error: execute_statement expects dbh reference")
        if ref($dbh_ref) ne 'REF';
    Carp::confess("Programmer error: execute_statement bound_values must be an ARRAY reference")
        if ref($opts->{'bound_values'}) ne 'ARRAY';

    my $dbh = ${$dbh_ref};

    Carp::confess("Programmer error: execute_statement expects dbh and sql parameters at least")
        unless $dbh && $opts->{'sql'};
    # we've got dbh with error, won't even try to use it
    Carp::confess($dbh->{'private_R2D2'}->{'connection_id'} . " error: " . $dbh->errstr . ", before executing statement [$opts->{'sql'}]")
        if $dbh->err;

    # check that it's really DBI db handle
    Carp::confess("Programmer error: execute_statement works only with dbh returned by get_client_db or get_cluster_db")
        if ref($dbh) ne 'DBI::db';

    my $sth = $dbh->prepare($opts->{'sql'});
    Carp::confess($dbh->{'private_R2D2'}->{'connection_id'} . " error: " . $dbh->errstr .
        ", while preparing statement [$opts->{'sql'}]")
        if $dbh->err;

    $sth->execute(@{$opts->{'bound_values'}});
    Carp::confess($dbh->{'private_R2D2'}->{'connection_id'} . " error: " . $dbh->errstr .
        ", while executing statement [$opts->{'sql'}], bound values: " . Data::Dumper::Dumper($opts->{'bound_values'}))
        if $dbh->err;


    # if there were no errors -- update last used stamp
    $dbh->{'private_R2D2'}->{'last_execute_statement_at'} = time();

    # either there were no error during request
    # or there was error which we were not able
    # to resolve automatically and user requested it
    # to be propagated; let him get it.
    #
    # this is real (Iponweb::)DBI::st (!)
    #
    return $sth;
}


sub non_null_fields {
    my ($full_row) = @_;
    my $row_clean;
    foreach my $k (keys %{$full_row}) {
        if (defined($full_row->{$k})) {
            $row_clean->{$k} = $full_row->{$k};
        }
    }
    return $row_clean;
}


1;
