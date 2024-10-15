#! /usr/bin/env perl

use strict;
use warnings;
use v5.11;

use Data::Dumper;
use Config::Simple;
#use JSON qw(decode_json encode_json);
use Time::Piece;
use Time::Seconds;
use FindBin;
use lib "$FindBin::Bin/../../msgraph-perl/lib";

use MsGroups;
use MsGroup;


my %config;
Config::Simple->import_from("$FindBin::Bin/../config/EduTeams.cfg",\%config) or die("No config: $!");

my $groups_object = MsGroups->new(
	'app_id'        => $config{'APP_ID'},
	'app_secret'    => $config{'APP_PASS'},
	'tenant_id'     => $config{'TENANT_ID'},
	'login_endpoint'=> $config{'LOGIN_ENDPOINT'},
	'graph_endpoint'=> $config{'GRAPH_ENDPOINT'},
	#'filter'        => '$filter=startswith(displayName,\'CSG\')',
    'select'        => '$select=id,displayName,description,mailNickname,createdDateTime',
);

my $groups = $groups_object->groups_fetch();
foreach my $group (@{$groups}){
	# print Dumper $group;
	my $date = Time::Piece->strptime(
		$group->{'createdDateTime'},
		"%Y-%m-%dT%H:%M:%SZ"
	);
	# say $date->strftime("%d-%m-%Y");
	printf(
		"%s;%s;%s;%s;%s\n",
		$group->{'id'},
		$date->strftime("%d-%m-%Y"),
		$group->{'description'} ,
		$group->{'displayName'},
		$group->{'mailNickname'}
	);
}