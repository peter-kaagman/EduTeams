#! /usr/bin/env perl

use strict;
use warnings;
use v5.11;

use Data::Dumper;
use Config::Simple;
use DBI;
use FindBin;
use lib "$FindBin::Bin/lib";

use MsGroups;
use MsGroup;
use Logger;


my %config;
Config::Simple->import_from("$FindBin::Bin/config/EduTeamsTest.cfg",\%config) or die("No config: $!");

my $logger = Logger->new(
    'filename' => "$FindBin::Bin/Log/EduTeams.log",
    'verbose' => 1
);
$logger->make_log("$FindBin::Bin/$FindBin::Script started.");


my $driver = $config{'DB_DRIVER'};
my $db = "$FindBin::Bin/db/".$config{'DB_NAME'};
my $db_user = $config{'DB_USER'};
my $db_pass = $config{'DB_PASS'};
my $dsn = "DBI:$driver:dbname=$db";
my $dbh = DBI->connect($dsn, $db_user, $db_pass, { RaiseError => 1 })
    or die $DBI::errstr;    

# Prepare db shit, volgorde is van belang ivm truncatesd en foreign keys
# azuredocent
$dbh->do('Delete From azuredocent'); # Truncate the table 
my $qry = "Insert Into azuredocent (upn, azureid, naam) values (?,?,?) ";
my $sth_azuredocent = $dbh->prepare($qry);
my $AzureDocenten; # ipv zoeken in de database
#$qry = "Select ROWID From azuredocent Where upn = ?";
#my $sth_azuredocent_zoeken = $dbh->prepare($qry);

# azuredocrooster
$dbh->do('Delete From azuredocrooster'); # Truncate the table 
$qry = "Insert Into azuredocrooster (azureteam_id,azuredocent_id) values (?,?) ";
my $sth_azuredocrooster = $dbh->prepare($qry);

# azureleerling
$dbh->do('Delete From azureleerling'); # Truncate the table 
$qry = "Insert Into azureleerling (upn, azureid, naam) values (?,?,?) ";
my $sth_azureleerling = $dbh->prepare($qry);
my $AzureLeerlingen; # ipv zoeken in de database
#$qry = "Select ROWID From azureleerling Where upn = ?";
#my $sth_azureleerling_zoeken = $dbh->prepare($qry);

# azureleerlingrooster
$dbh->do('Delete From azureleerlingrooster'); # Truncate the table 
$qry = "Insert Into azureleerlingrooster (azureteam_id,azureleerling_id) values (?,?) ";
my $sth_azureleerlingrooster = $dbh->prepare($qry);

# azureteam
$dbh->do('Delete From azureteam'); # Truncate the table 
$qry = "Insert Into azureteam (id, securename, description, displayName) values (?,?,?,?) ";
my $sth_azureteam = $dbh->prepare($qry);

my $groups_object = MsGroups->new(
	'app_id'        => $config{'APP_ID'},
	'app_secret'    => $config{'APP_PASS'},
	'tenant_id'     => $config{'TENANT_ID'},
	'login_endpoint'=> $config{'LOGIN_ENDPOINT'},
	'graph_endpoint'=> $config{'GRAPH_ENDPOINT'},
	'filter'        => '$filter=startswith(mailNickname,\'Section_'.$config{'MAGISTER_LESPERIODE'}.'\')', # lesperiode in de select zodat alleen het huidige jaar opgehaald wordt
    'select'        => '$select=id,displayName,description,mailNickname',
);


# Maakt een entry voor de docent als die nog niet bestaat
# Geeft de ROWID terug
sub getAzureDocentROWID {
    my $docent = shift;
    if ($AzureDocenten->{$docent->{'email'}}){
        # docent gevonden => return ROWID
        return $AzureDocenten->{$docent->{'email'}};
    }else{
        # Docent niet gevonden => aanmaken
        #my $qry = "Insert Into azuredocent (upn, azureid, naam) values (?,?,?) ";
        #print Dumper $docent;
        $sth_azuredocent->execute(
            lc($docent->{'email'}), 
            $docent->{'userId'}, 
            $docent->{'displayName'}
        );
        my $rowid =  $dbh->last_insert_id("","","azuredocent","ROWID");
        $AzureDocenten->{$docent->{'email'}} = $rowid;
        #say $rowid;
        #print Dumper $AzureDocenten;
        return $rowid;
    }
}
# Maakt een entry voor de leerling als die nog niet bestaat
# Geeft de ROWID terug
sub getAzureLeerlingROWID {
    my $leerling = shift;
    if ($AzureLeerlingen->{$leerling->{'email'}}){
        # leerling gevonden => return ROWID
        return $AzureLeerlingen->{$leerling->{'email'}};
    }else{
        # Leerling niet gevonden => aanmaken
        #print Dumper $docent;
        #my $qry = "Insert Into azuredocent (upn, azureid, naam) values (?,?,?) ";
        $sth_azureleerling->execute(
            lc($leerling->{'email'}),
            $leerling->{'userIs'},
            $leerling->{'displayName'}
        );
        my $rowid =  $dbh->last_insert_id("","","azureleerling","ROWID");
        $AzureLeerlingen->{$leerling->{'email'}} = $rowid;
        return $rowid;
    }
}

# Maakt een entry voor de groep.
# Geeft de ROWID terug
sub getAzureTeamROWID {
    my $team = shift;
    #$qry = "Insert Into azureteam (id, securename,description, displayName) values (?,?,?,?) ";
    $sth_azureteam->execute($team->{'id'},$team->{'secureName'},$team->{'description'},$team->{'displayName'});
    return $dbh->last_insert_id("","","azureteam","ROWID");
}

if ($groups_object->_get_access_token){
    # Eerst de classes ophalen in Graph
	my $teams = $groups_object->groups_fetch();
#	while (my ($i, $team) = each @{$teams}){
	foreach my $team (@{$teams}){
        # description en displayName kunnen aangepast zijn, naam halen uit de mailNick
        $team->{'mailNickname'} =~ /^Section_($config{'MAGISTER_LESPERIODE'}.+)/;
        $team->{'secureName'} = $1;
        $logger->make_log("$FindBin::Bin/$FindBin::Script Team gevonden: ". $team->{'secureName'});
        # Registreren in azureteams, team zal nog niet bestaan
        my $azureteamROWID = getAzureTeamROWID($team);
        # Object maken voor deze groep met het doel owers en leden op te halen
        my $group_object = MsGroup->new(
            'app_id'        => $config{'APP_ID'},
            'app_secret'    => $config{'APP_PASS'},
            'tenant_id'     => $config{'TENANT_ID'},
            'login_endpoint'=> $config{'LOGIN_ENDPOINT'},
            'graph_endpoint'=> $config{'GRAPH_ENDPOINT'},
            'access_token'  => $groups_object->_get_access_token, # hergebruik het token
            'token_expires' => $groups_object->_get_token_expires,
            'select'        => '$select=id,displayName,userPrincipalName',
            'id'            => $team->{'id'},
        );
        # Member ophalen van het team
        my $members = $group_object->team_members();
        foreach my $member (@{$members}){
            #print Dumper $member;
            #my $roles = decode_json($member=>{'roles'});
            if ($member->{'roles'}[0]){
                my $azuredocentROWID = getAzureDocentROWID($member);
                # ROWID van docent en team is bekend => toevoegen aan azuredocrooster
                # $qry = "Insert Into azuredocrooster (azureteam_id,azuredocent_id) values (?,?) ";
                $sth_azuredocrooster->execute($azureteamROWID,$azuredocentROWID);
            }else{
                my $azureleerlingROWID = getAzureLeerlingROWID($member);
                # ROWID van lln en team is bekend => toevoegen aan azureleerlingrooster
                # $qry = "Insert Into azureleerlingrooster (azureteam_id,azureleerling_id) values (?,?) ";
                $sth_azureleerlingrooster->execute($azureteamROWID,$azureleerlingROWID);
            }
        }
	}
}else{
	$logger->make_log("$FindBin::Bin/$FindBin::Script No token!");
}
$logger->make_log("$FindBin::Bin/$FindBin::Script ended.");
