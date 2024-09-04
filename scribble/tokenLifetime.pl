#! /usr/bin/env perl
#
# Dit script is uitsluitend bedoeld om te experimenteren met het aanmaken van groepen
#
use strict;
use warnings;
use v5.11;

use Data::Dumper;
use Config::Simple;
use DBI;
use FindBin;
#use Time::Piece;
use lib "$FindBin::Bin/../lib";

use MsUser;

#
# Test config
my %config;
Config::Simple->import_from("$FindBin::Bin/../config/EduTeams.cfg",\%config) or die("No config: $!");

my $user_object = MsUser->new(
	'app_id'        => $config{'APP_ID'},
	'app_secret'    => $config{'APP_PASS'},
	'tenant_id'     => $config{'TENANT_ID'},
	'login_endpoint'=> $config{'LOGIN_ENDPOINT'},
	'graph_endpoint'=> $config{'GRAPH_ENDPOINT'},
	#'filter'        => '$filter=startswith(mail,\'EduTeam_\')',
    'select'        => '$select=id,displayName,description,mail',
);

while (1){
    my $now = localtime;
    print "Het is nu $now ";
    my $upn = 'p.kaagman@atlascollege.nl';
    my $id = $user_object->fetch_id_by_upn($upn);
    print "$upn => $id ";
    my $refresh = localtime($user_object->_get_token_refresh);
    print "Refresh op $refresh ";
    my $expire = localtime($user_object->_get_token_expires);
    say "Expire op $expire";
    sleep 10;
}
