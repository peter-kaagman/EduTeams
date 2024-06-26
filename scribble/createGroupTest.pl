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
Config::Simple->import_from("$FindBin::Bin/config/EduTeamsTest.cfg",\%config) or die("No config: $!");

# my $logger = Logger->new(
#     'filename' => "$FindBin::Bin/Log/EduTeamsTest.log",
#     'verbose' => 1
# );
# $logger->make_log("$FindBin::Bin/$FindBin::Script started.");


my $driver = $config{'DB_DRIVER'};
my $db = "$FindBin::Bin/db/".$config{'DB_NAME'};
my $db_user = $config{'DB_USER'};
my $db_pass = $config{'DB_PASS'};
my $dsn = "DBI:$driver:dbname=$db";
my $dbh = DBI->connect($dsn, $db_user, $db_pass, { RaiseError => 1 })
    or die $DBI::errstr;    

my $groups_object = MsGroups->new(
	'app_id'        => $config{'APP_ID'},
	'app_secret'    => $config{'APP_PASS'},
	'tenant_id'     => $config{'TENANT_ID'},
	'login_endpoint'=> $config{'LOGIN_ENDPOINT'},
	'graph_endpoint'=> $config{'GRAPH_ENDPOINT'},
	#'filter'        => '$filter=startswith(mail,\'EduTeam_\')',
    'select'        => '$select=id,displayName,description,mail',
);

sub listGroups {
# ff kijken of we groepen op kunnen halen
    if ($groups_object->_get_access_token){
        # Eerst de groepen ophalen in Graph
        my $groups = $groups_object->fetch_groups();
        while (my ($i, $group) = each @{$groups}){
            say "Description: $group->{'description'}";
            my $group_object = MsGroup->new(
                'app_id'        => $config{'APP_ID'},
                'app_secret'    => $config{'APP_PASS'},
                'tenant_id'     => $config{'TENANT_ID'},
                'login_endpoint'=> $config{'LOGIN_ENDPOINT'},
                'graph_endpoint'=> $config{'GRAPH_ENDPOINT'},
                'select'        => '$select=id,displayName,userPrincipalName',
                'id'            => $group->{'id'},
            );
            # Eigenaren (docenten ophalen)
            my $owners = $group_object->fetch_owners();
            # $owners is een AOH
            foreach my $owner (@$owners){
                say "Owner: $owner->{'displayName'}";
            }
            # Leden (leerlingen ophalen)
            my $members = $group_object->fetch_members();
            # $members is een AOH
            foreach my $member (@$members){
                say "Member: $member->{'displayName'}";
            }
        }
	}
}

#listGroups;
# Als we groepen gaan maken dan maken we ze met eigenaren en leden
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
};

my $naam = "test_ 1"; # Om ff snel een nieuwe groep te kunnen maken
#
# Bij het aanmaken van een groep kunnen maximaal 20 gebruikers toegevoegd 
# worden. Oplossing hiervoor zou JSON batching kunnen zijn.
# Echter ook JSON batching heeft weer een uitdaging: max 20 request
# Een combinatie van members in de aanmaak request en de rest in de 
# batch lijkt een mogelijkheid
# Echter dit is voor jaarlaag groepen nog altijd te kort.
# De transitie naar team zal in een separaat process plaatsvinden
# ivm de 15 minuten wachttijd voor dit kan.
# Dit process zal dan ook de leden van de group toe gaan voegen voor
# de transitie naar een team.

# Data structure om een groep te maken
my $new_group = {
        "description" => "My $naam group description",
        "displayName" => "My $naam group displayName",
        "mailEnabled" => \1,
        "mailNickName" => "EduTeam_$naam",
        "securityEnabled" => \0,
};
# add the groupType array
push(@{$new_group->{'groupTypes'}}, 'Unified');
# add the owners
my @owners; # ff een array met 2 owners
push(@owners, 'docent1@ict-atlascollege.nl');
push(@owners, 'docent2@ict-atlascollege.nl');
# Zodat we in een loop de owner kunnen toevoegen
foreach my $owner (@owners){
    push(@{$new_group->{'owners@odata.bind'}}, 'https://graph.microsoft.com/v1.0/users/'.$users->{$owner}->{'id'});
    # een owner moet ook member zijn
    push(@{$new_group->{'members@odata.bind'}}, 'https://graph.microsoft.com/v1.0/users/'.$users->{$owner}->{'id'});
}
# en de gewone leden toevoegen
# push(@{$new_group->{'members@odata.bind'}}, 'https://graph.microsoft.com/v1.0/users/'.$users->{'leerling2@ict-atlascollege.nl'}->{'id'});
# push(@{$new_group->{'members@odata.bind'}}, 'https://graph.microsoft.com/v1.0/users/'.$users->{'leerling3@ict-atlascollege.nl'}->{'id'});
# push(@{$new_group->{'members@odata.bind'}}, 'https://graph.microsoft.com/v1.0/users/'.$users->{'leerling4@ict-atlascollege.nl'}->{'id'});

my $result = $groups_object->create_group($new_group);
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
