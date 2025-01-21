#! /usr/bin/env perl
#
use v5.11;
use strict;
use warnings;
use Text::CSV qw( csv );
use DBI;
use Data::Dumper;
use Config::Simple;
use FindBin;

use lib "$FindBin::Bin/../../msgraph-perl/lib";

use MsGroups;
use MsGroup;
use MsUser;


my %config;
Config::Simple->import_from("$FindBin::Bin/../config/EduTeams.cfg", \%config) or die("No config: $!");

my $groups_object = MsGroups->new(
	'app_id'        => $config{'APP_ID'},
	'app_secret'    => $config{'APP_PASS'},
	'tenant_id'     => $config{'TENANT_ID'},
	'login_endpoint'=> $config{'LOGIN_ENDPOINT'},
	'graph_endpoint'=> $config{'GRAPH_ENDPOINT'},
	'select'        => '$select=id,displayName,description,mailNickname',
);

my $group_id = $groups_object->group_find_id('personeel');

my $group_object = MsGroup->new(
	'app_id'        => $config{'APP_ID'},
	'app_secret'    => $config{'APP_PASS'},
	'tenant_id'     => $config{'TENANT_ID'},
	'login_endpoint'=> $config{'LOGIN_ENDPOINT'},
	'graph_endpoint'=> $config{'GRAPH_ENDPOINT'},
	'select'        => '$select=id,displayName,userPrincipalName,employeeId,createdDateTime,accountEnabled',
    'id'            => $groups_object->group_find_id('personeel'),
    'access_token'  => $groups_object->_get_access_token,
    'token_expires' => $groups_object->_get_token_expires,
);

my $members = $group_object->group_fetch_members;

my $i = 0;
foreach my $member (@{$members}){
    if ( (! $member->{'employeeId'})&& ($member->{'accountEnabled'}) ){
		$i++;
        printf("%3s %-40s %-30s %s\n",$i, $member->{'userPrincipalName'},$member->{'displayName'},$member->{'createdDateTime'}) ;
    }
}


