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
use lib "$FindBin::Bin/../lib";

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
	#'filter'        => '$filter=startswith(mail,\'EduTeam_\')',
    'select'        => '$select=id,displayName,description,mail',
);

my $name = "2324-0Blaat.wi";
my $description = $name . " description";

my $new_team = {
    'template@odata.bind' => 'https://graph.microsoft.com/v1.0/teamsTemplates(\'educationClass\')',
    "description" => $description,
    "displayName" => $name,
    "mailNickname"  => "EduTeam_".$name
};

# add the owners => met deze methode mag er maar 1 lid toegvoegd worden.
my $owner = '50794d26-aa78-4cf2-bede-a39ae2da20ad';
my $user = {
    '@odata.type'=> '#microsoft.graph.aadUserConversationMember',
    'user@odata.bind' => "https://graph.microsoft.com/v1.0/users(\'$owner\')"
};
push(@{$user->{'roles'}}, 'owner');
push(@{$new_team->{'members'}}, $user);

print Dumper $new_team;
#my $json = encode_json($new_team);
#say $json;
#exit 1;


my $result = $groups_object->team_create($new_team);
#print Dumper $result;
if ($result->is_success){
    say "Team created";
    print Dumper $result;
} else {
    #foutafhandeling
    if ($result->{'_rc'} eq '400'){ # bad request
        my $content = decode_json($result->{'_content'});
        say $content->{'error'}->{'message'};
    }else{
        say "Er is een fout opgetreden: $result->{'_rc'}";
    }
}
