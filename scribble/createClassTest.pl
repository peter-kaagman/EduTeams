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
	#'filter'        => '$filter=startswith(mail,\'Section_\')',
    'select'        => '$select=id,displayName,description,mail',
);


my $new_class = {
    "description" => "My first class description",
    "displayName" => "My first class displayName",
    "mailNickname" => "Section_firstClass",
    "externalId" => "Section_firstClass",
#    "externalSource" => "manual",
#    "externalSourceDetail" => "EduTeams",
    "course" => {
        "displayName" => "FirstClass",
    },
};

my $result = $groups_object->create_class($new_class);
print Dumper $result;
if ($result->is_success){
    my $created_team = decode_json($result->{'_content'});
    say "ID: $created_team->{'id'}";
    say "TimeStamp: $created_team->{'createdDateTime'}";
    # De group bestaat. Nu leden toegvoegen? Testen!
    # ff een array met users
    
    # Gegevens in de database opnemen om gebruikers toevoegen 
    # en de team transitie

} else {
    #foutafhandeling
    if ($result->{'_rc'} eq '400'){ # bad request
        my $content = decode_json($result->{'_content'});
        say $content->{'error'}->{'message'};
    }else{
        say "Er is een fout opgetreden: $result->{'_rc'}";
    }
}
