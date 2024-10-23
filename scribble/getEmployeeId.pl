#! /usr/bin/env perl

use strict;
use warnings;
use v5.11;

use Data::Dumper;
use Config::Simple;
use FindBin;
use lib "$FindBin::Bin/../../msgraph-perl/lib";


use MsGroup;
use MsGroups;


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

my $group_id = $groups_object->group_find_id('personeel');
say $group_id;

my $group_object = MsGroup->new(
    'app_id'        => $config{'APP_ID'},
    'app_secret'    => $config{'APP_PASS'},
    'tenant_id'     => $config{'TENANT_ID'},
    'access_token'  => $groups_object->_get_access_token, #reuse token
    'token_expires' => $groups_object->_get_token_expires,
    'login_endpoint'=> $config{'LOGIN_ENDPOINT'},
    'graph_endpoint'=> $config{'GRAPH_ENDPOINT'},
    'id'            => $group_id,
    'select'        => '$select=id,displayName,userPrincipalName,employeeId'
);

my $members = $group_object->group_fetch_members();

my $count = 0;
foreach my $member (@{$members}){
    if ($member->{'employeeId'}){
        #say lc($member->{'userPrincipalName'})," => $member->{'employeeId'}"
    }else{
        $count++;
        say "$count :",lc($member->{'userPrincipalName'}), " => geen employeeId"
    }
}
