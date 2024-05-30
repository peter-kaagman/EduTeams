#! /usr/bin/env perl
#
# Als een group gemaakt is moet minimaal 15 minuten gewacht wordne
# voor er een team van gemaakt kan worden.
# Dit script (via cron?) periodiek uitvoeren
#
use strict;
use warnings;
use v5.11;

use Data::Dumper;
use Config::Simple;
use DBI;
use FindBin;
use JSON;
use lib "$FindBin::Bin/lib";

use MsGroups;
use MsGroup;
#use Logger;

#
# Test config
my %config;
Config::Simple->import_from("$FindBin::Bin/config/EduTeamsTest.cfg",\%config) or die("No config: $!");

# my $logger = Logger->new(
#     'filename' => "$FindBin::Bin/Log/EduTeamsTest.log",
#     'verbose' => 1
# );
# $logger->make_log("$FindBin::Bin/$FindBin::Script started.");


my $driver = $config{'DB_DRIVER'};
my $db = "$FindBin::Bin/db/".$config{'DB_NAME'};
my $db_user = $config{'DB_USER'};
my $db_pass = $config{'DB_PASS'};
my $dsn = "DBI:$driver:dbname=$db";
my $dbh = DBI->connect($dsn, $db_user, $db_pass, { RaiseError => 1 })
    or die $DBI::errstr;    
