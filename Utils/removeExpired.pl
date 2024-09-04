#! /usr/bin/env perl

use strict;
use warnings;
use v5.11;

use Data::Dumper;
use Config::Simple;
#use JSON qw(decode_json encode_json);
use FindBin;
use lib "$FindBin::Bin/../lib";

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
	'filter'        => '$filter=startswith(mailNickname,\'Exp\')',
    'select'        => '$select=id,displayName,description,mailNickname',
);

my $groups = $groups_object->groups_fetch();
my $count = 0;
foreach my $group (@{$groups}){
	$count++;
	my $group_object = MsGroup->new(
		'app_id'        => $config{'APP_ID'},
		'app_secret'    => $config{'APP_PASS'},
		'tenant_id'     => $config{'TENANT_ID'},
		'access_token'	=> $groups_object->_get_access_token, # reuse the access we have allready
		'token_expires' => $groups_object->_get_token_expires,
		'login_endpoint'=> $config{'LOGIN_ENDPOINT'},
		'graph_endpoint'=> $config{'GRAPH_ENDPOINT'},
		'select'        => '$select=id,displayName,description,isArchived,mailNickname',
		'id'			=> $group->{'id'},
	);
	my $team_info = $group_object->team_info;
	if ($team_info->{'isArchived'}){
		say "$team_info->{'displayName'} is archived: $team_info->{'isArchived'} => deleting";
		#my $result = $group_object->group_delete;
		#print Dumper $team_info;
	}  else {
		say "$team_info->{'displayName'} is not archived: $team_info->{'isArchived'}, archiving";
		my $result = $groups_object->team_archive($group->{'id'},$team_info->{'description'});
		if ( $result eq 'Ok'){
			say "$group->{'id'} is archived";
		}else{
			say "Failed:";
			print Dumper $result;
		}
		#print Dumper $team_info;
		#print Dumper $group;
	}
}
say "$count teams gevonden";