#! /usr/bin/env perl

#
# SDS maakt een mailNickname als Section_<SIS_ID>, dit is voor EduTeams
# niet bruikbaar. Om de SDS teams "over te kunnen nemen" moet de mailNicname
# het nieuwe format krijgen: EduTeam_<klas_naam>
# Dit script is bedoeld om de mailNickname van bestaande teams aan te passen.
#

use strict;
use warnings;
use v5.11;

use Data::Dumper;
use Config::Simple;
use DBI;
use FindBin;
use JSON;
use lib "$FindBin::Bin/../lib";

use MsGroups;
use MsGroup;
#use Logger;

#
my %config;
Config::Simple->import_from("$FindBin::Bin/../config/EduTeams.cfg",\%config) or die("No config: $!");

my $groups_object = MsGroups->new(
	'app_id'        => $config{'APP_ID'},
	'app_secret'    => $config{'APP_PASS'},
	'tenant_id'     => $config{'TENANT_ID'},
	'login_endpoint'=> $config{'LOGIN_ENDPOINT'},
	'graph_endpoint'=> $config{'GRAPH_ENDPOINT'},
	'filter'        => '$filter=startswith(mailNickname,\'Section_\')',
    'select'        => '$select=id,displayName,description,mailNickname',
);

my $groepen = $groups_object->groups_fetch;
my $count =0;
foreach my $groep (@{$groepen}){
	$count++;
	my $newMailNickname = "EduTeam_$groep->{'description'}";
    printf(
		"%s %-15s %-20s %s\n" ,
		$groep->{'id'},
		$groep->{'mailNickname'},
		$groep->{'description'},
		$newMailNickname
	);
}
say "$count groepen gevonden";