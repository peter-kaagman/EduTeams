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

use MsUsers;
use MsUser;


my %config;
Config::Simple->import_from("$FindBin::Bin/../config/EduTeams.cfg",\%config) or die("No config: $!");

# my $users_object = MsUsers->new(
# 	'app_id'        => $config{'APP_ID'},
# 	'app_secret'    => $config{'APP_PASS'},
# 	'tenant_id'     => $config{'TENANT_ID'},
# 	'login_endpoint'=> $config{'LOGIN_ENDPOINT'},
# 	'graph_endpoint'=> $config{'GRAPH_ENDPOINT'},
# 	#'filter'        => '$filter=startswith(displayName,\'CSG\')',
#     'select'        => '$select=id,displayName,mailNickname,primaryRole',
# );

# my $users = $users_object->fetch_edusers;
# print Dumper $users;

my $user_object = MsUser->new(
	'app_id'        => $config{'APP_ID'},
	'app_secret'    => $config{'APP_PASS'},
	'tenant_id'     => $config{'TENANT_ID'},
	'login_endpoint'=> $config{'LOGIN_ENDPOINT'},
	'graph_endpoint'=> $config{'GRAPH_ENDPOINT'},
	#'filter'        => '$filter=startswith(displayName,\'CSG\')',
    'select'        => '$select=id,displayName,mailNickname,primaryRole',
    'id'            => '50794d26-aa78-4cf2-bede-a39ae2da20ad' # docent 1
);

my $result = $user_object->eduUser_set_role('teacher');
print Dumper $result;
