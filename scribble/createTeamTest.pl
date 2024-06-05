#! /usr/bin/env perl
#
# Dit script is uitsluitend bedoeld om te experimenteren met het aanmaken van teams
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

use MsTeams;
#use MsGroup;
#use Logger;

#
# Test config
my %config;
Config::Simple->import_from("$FindBin::Bin/../config/EduTeamsTest.cfg",\%config) or die("No config: $!");

# my $logger = Logger->new(
#     'filename' => "$FindBin::Bin/Log/EduTeamsTest.log",
#     'verbose' => 1
# );
# $logger->make_log("$FindBin::Bin/$FindBin::Script started.");


# my $driver = $config{'DB_DRIVER'};
# my $db = "$FindBin::Bin/db/".$config{'DB_NAME'};
# my $db_user = $config{'DB_USER'};
# my $db_pass = $config{'DB_PASS'};
# my $dsn = "DBI:$driver:dbname=$db";
# my $dbh = DBI->connect($dsn, $db_user, $db_pass, { RaiseError => 1 })
#     or die $DBI::errstr;    

my $teams_object = MsTeams->new(
	'app_id'        => $config{'APP_ID'},
	'app_secret'    => $config{'APP_PASS'},
	'tenant_id'     => $config{'TENANT_ID'},
	'login_endpoint'=> $config{'LOGIN_ENDPOINT'},
	'graph_endpoint'=> $config{'GRAPH_ENDPOINT'},
	#'filter'        => '$filter=startswith(mail,\'Section_\')',
    'select'        => '$select=id,displayName,description,mail',
);

sub listTeams {
# ff kijken of we groepen op kunnen halen
    if ($teams_object->_get_access_token){
        # Eerst de teams ophalen in Graph
        my $teams = $teams_object->fetch_teams();
        while (my ($i, $team) = each @{$teams}){
            say "Description: $team->{'description'}";
        #     my $group_object = MsGroup->new(
        #         'app_id'        => $config{'APP_ID'},
        #         'app_secret'    => $config{'APP_PASS'},
        #         'tenant_id'     => $config{'TENANT_ID'},
        #         'login_endpoint'=> $config{'LOGIN_ENDPOINT'},
        #         'graph_endpoint'=> $config{'GRAPH_ENDPOINT'},
        #         'select'        => '$select=id,displayName,userPrincipalName',
        #         'id'            => $group->{'id'},
        #     );
        #     # Eigenaren (docenten ophalen)
        #     my $owners = $group_object->fetch_owners();
        #     # $owners is een AOH
        #     foreach my $owner (@$owners){
        #         say "Owner: $owner->{'displayName'}";
        #     }
        #     # Leden (leerlingen ophalen)
        #     my $members = $group_object->fetch_members();
        #     # $members is een AOH
        #     foreach my $member (@$members){
        #         say "Member: $member->{'displayName'}";
        #     }
        }
	}
}

listTeams;
# Als we teams gaan maken dan maken we ze met eigenaren en leden
# Normaal komen die gegevens uit Magister/Azure tijden het sync process
# Om te testen maak ik een hash met wat beschikbare gebruikers
my $users = {
    'docent1@ict-atlascollege.nl' => {
        'id' => '50794d26-aa78-4cf2-bede-a39ae2da20ad',
        'displayName' => 'Test Docent 1',
    },
    'docent2@ict-atlascollege.nl' => {
        'id' => 'bb32a504-c67e-475d-9b47-3c6c8e49cf6f',
        'displayName' => 'Test Docent 2',
    },
    'leerling1@ict-atlascollege.nl' => {
        'id' => 'db8f7592-bb6f-4b6c-9d9a-a7b6184fac6e',
        'displayName' => 'Test Leerling 1',
    },
    'leerling2@ict-atlascollege.nl' => {
        'id' => '16886be3-8a11-4114-b535-12a0334a4ad8',
        'displayName' => 'Test Leerling 2',
    },
    'leerling3@ict-atlascollege.nl' => {
        'id' => '6991e4da-f259-4ef9-b263-8d7acde1a4b1',
        'displayName' => 'Test Leerling 3',
    },
    'leerling4@ict-atlascollege.nl' => {
        'id' => 'dd4726df-6f48-44ef-9f98-1c1b2f6eee43',
        'displayName' => 'Test Leerling 4',
    },
};

my $naam = "team_test_ 1"; # Om ff snel een nieuwe groep te kunnen maken
# #
# # Data structure om een team te maken
my $new_team = {
        "description" => "My $naam group description",
        "displayName" => "My $naam group displayName",
        "mailEnabled" => \1,
        "mailNickName" => "Section_$naam",
};
# # add the groupType array
# push(@{$new_group->{'groupTypes'}}, 'Unified');
# # add the owners
# my @owners; # ff een array met 2 owners
# push(@owners, 'docent1@ict-atlascollege.nl');
# push(@owners, 'docent2@ict-atlascollege.nl');
# # Zodat we in een loop de owner kunnen toevoegen
# foreach my $owner (@owners){
#     push(@{$new_group->{'owners@odata.bind'}}, 'https://graph.microsoft.com/v1.0/users/'.$users->{$owner}->{'id'});
#     # een owner moet ook member zijn
#     push(@{$new_group->{'members@odata.bind'}}, 'https://graph.microsoft.com/v1.0/users/'.$users->{$owner}->{'id'});
# }
# # en de gewone leden toevoegen
# # push(@{$new_group->{'members@odata.bind'}}, 'https://graph.microsoft.com/v1.0/users/'.$users->{'leerling2@ict-atlascollege.nl'}->{'id'});
# # push(@{$new_group->{'members@odata.bind'}}, 'https://graph.microsoft.com/v1.0/users/'.$users->{'leerling3@ict-atlascollege.nl'}->{'id'});
# # push(@{$new_group->{'members@odata.bind'}}, 'https://graph.microsoft.com/v1.0/users/'.$users->{'leerling4@ict-atlascollege.nl'}->{'id'});

my $result = $teams_object->create_team($new_team);
if ($result->is_success){
    my $created_team = decode_json($result->{'_content'});
    say "ID: $created_team->{'id'}";
    say "TimeStamp: $created_team->{'createdDateTime'}";
} else {
    #foutafhandeling
    if ($result->{'_rc'} eq '400'){ # bad request
        my $content = decode_json($result->{'_content'});
        say $content->{'error'}->{'message'};
    }else{
        say "Er is een fout opgetreden: $result->{'_rc'}";
    }
}
# # Benieuwd of de group direct zichtbaar is
listTeams;

# created group _content
# {
#     "@odata.context": "https://graph.microsoft.com/v1.0/$metadata#groups/$entity",
#     "id": "9a8643bf-a9d0-4ed1-9295-fbb75bc3bf9a",
#     "deletedDateTime": null,
#     "classification": null,
#     "createdDateTime": "2024-05-24T14:39:30Z",
#     "creationOptions": [],
#     "description": "My first group description",
#     "displayName": "My first group displayName",
#     "expirationDateTime": null,
#     "groupTypes": [
#         "Unified"
#     ],
#     "isAssignableToRole": null,
#     "mail": "Section_MyFirstGroup@ICTAtlasCollege.onmicrosoft.com",
#     "mailEnabled": true,
#     "mailNickname": "Section_MyFirstGroup",
#     "membershipRule": null,
#     "membershipRuleProcessingState": null,
#     "onPremisesDomainName": null,
#     "onPremisesLastSyncDateTime": null,
#     "onPremisesNetBiosName": null,
#     "onPremisesSamAccountName": null,
#     "onPremisesSecurityIdentifier": null,
#     "onPremisesSyncEnabled": null,
#     "preferredDataLocation": null,
#     "preferredLanguage": null,
#     "proxyAddresses": [
#         "SMTP:Section_MyFirstGroup@ICTAtlasCollege.onmicrosoft.com"
#     ],
#     "renewedDateTime": "2024-05-24T14:39:30Z",
#     "resourceBehaviorOptions": [],
#     "resourceProvisioningOptions": [],
#     "securityEnabled": false,
#     "securityIdentifier": "S-1-12-1-2592490431-1322363344-3086718354-2596258651",
#     "theme": null,
#     "uniqueName": null,
#     "visibility": "Public",
#     "onPremisesProvisioningErrors": [],
#     "serviceProvisioningErrors": []
# }
