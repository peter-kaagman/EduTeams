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
use JSON;
use lib "$FindBin::Bin/../../msgraph-perl/lib";

use MsGroups;
use MsGroup;
#use Logger;

#
# Test config
my %config;
Config::Simple->import_from("$FindBin::Bin/../config/EduTeamsTest.cfg",\%config) or die("No config: $!");

my $groups_object = MsGroups->new(
	'app_id'        => $config{'APP_ID'},
	'app_secret'    => $config{'APP_PASS'},
	'tenant_id'     => $config{'TENANT_ID'},
	'login_endpoint'=> $config{'LOGIN_ENDPOINT'},
	'graph_endpoint'=> $config{'GRAPH_ENDPOINT'},
    'select'        => '$select=id,displayName,description,mail',
);

my $created_class;

my $name = 'Try_2';
my $new_class = {
    "description" => $name,
    "displayName" => $name,
    "mailNickname" => $name,
    "externalId" => $name,
};

my $owner_id = "50794d26-aa78-4cf2-bede-a39ae2da20ad";

my $result = $groups_object->class_create($new_class);
#print Dumper $result;
if ($result->is_success){
    $created_class = decode_json($result->decoded_content);
} else {
    #foutafhandeling
    if ($result->{'_rc'} eq '400'){ # bad request
        my $content = decode_json($result->{'_content'});
        say $content->{'error'}->{'message'};
    }else{
        say "Er is een fout opgetreden: $result->{'_rc'}";
    }
}

if ($created_class){
    print Dumper $created_class;
    my $group_object = MsGroup->new(
        'app_id'        => $config{'APP_ID'},
        'app_secret'    => $config{'APP_PASS'},
        'tenant_id'     => $config{'TENANT_ID'},
        'access_token'  => $groups_object->_get_access_token, #reuse token
        'token_expires' => $groups_object->_get_token_expires,
        'login_endpoint'=> $config{'LOGIN_ENDPOINT'},
        'graph_endpoint'=> $config{'GRAPH_ENDPOINT'},
        'id'            => $created_class->{'id'},
    );
    # Add owner
    my $result = $group_object->group_add_member($owner_id, 1);
    say "Add owner";
    #print Dumper decode_json $result->decoded_content;
    #Transform
    $result = $group_object->team_from_group();
    say "Transitie";
    print Dumper decode_json $result->decoded_content;
}