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

# azuredocrooster
$dbh->do('Delete From azuredocrooster'); # Truncate the table 
my $qry = "Insert Into azuredocrooster (azureteam_id,azuredocent_id) values (?,?) ";
my $sth_azuredocrooster = $dbh->prepare($qry);


# azureleerlingrooster
$dbh->do('Delete From azureleerlingrooster'); # Truncate the table 
$qry = "Insert Into azureleerlingrooster (azureteam_id,azureleerling_id) values (?,?) ";
my $sth_azureleerlingrooster = $dbh->prepare($qry);

# azureteam
$dbh->do('Delete From azureteam'); # Truncate the table 
$qry = "Insert Into azureteam (id, securename, description, displayName) values (?,?,?,?) ";
my $sth_azureteam = $dbh->prepare($qry);

# Users
# Users dient als zoek hash 
my $sth_users = $dbh->prepare("Select azureid,upn,ROWID From users");
$sth_users->execute();
my $usersByUpn = $sth_users->fetchall_hashref('upn');
# ById is niet nodig, scheelt tijd en geheugen
#$sth_users->execute();
#my $usersById = $sth_users->fetchall_hashref('azureid');

# azureteam
$dbh->do('Delete From azureteam_members'); # Truncate the table 
$qry = "Insert Into azureteam_members (teamid,user_azureid,user_memberid) values (?,?,?) ";
my $sth_azureteam_members = $dbh->prepare($qry);


my $groups_object = MsGroups->new(
	'app_id'        => $config{'APP_ID'},
	'app_secret'    => $config{'APP_PASS'},
	'tenant_id'     => $config{'TENANT_ID'},
	'login_endpoint'=> $config{'LOGIN_ENDPOINT'},
	'graph_endpoint'=> $config{'GRAPH_ENDPOINT'},
	'filter'        => '$filter=startswith(mailNickname,\'EduTeam_'.$config{'MAGISTER_LESPERIODE'}.'\')', # lesperiode in de select zodat alleen het huidige jaar opgehaald wordt
    'select'        => '$select=id,displayName,description,mailNickname',
);



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
	foreach my $team (@{$teams}){
        # description en displayName kunnen aangepast zijn, naam halen uit de mailNick
        $team->{'mailNickname'} =~ /^EduTeam_($config{'MAGISTER_LESPERIODE'}.+)/;
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
            #'select'        => '$select=id,displayName,userPrincipalName',
            'id'            => $team->{'id'},
        );
        # Member ophalen van het team
        my $members = $group_object->team_members();
        foreach my $member (@{$members}){
            # azuretem_members tabel bijwerken met MembershipId
            # deze is nodig bij het verwijderen van een teamlid.
            # deze is dus altijd voorhanden
            #print Dumper $member;
            #$qry = "Insert Into azureteam_members (teamid,user_azureid,user_memberid) values (?,?,?) ";
            $sth_azureteam_members->execute($team->{'id'},$member->{'userId'},$member->{'id'});
            if ($member->{'roles'}[0]){
                # ROWID van docent en team is bekend => toevoegen aan azuredocrooster
                # $qry = "Insert Into azuredocrooster (azureteam_id,azuredocent_id) values (?,?) ";
                $sth_azuredocrooster->execute($azureteamROWID,$usersByUpn->{$member->{'email'}}->{'rowid'});
            }else{
                # ROWID van lln en team is bekend => toevoegen aan azureleerlingrooster
                # $qry = "Insert Into azureleerlingrooster (azureteam_id,azureleerling_id) values (?,?) ";
                $sth_azureleerlingrooster->execute($azureteamROWID,$usersByUpn->{$member->{'email'}}->{'rowid'});
            }
        }
	}
}else{
	$logger->make_log("$FindBin::Bin/$FindBin::Script No token!");
}
$logger->make_log("$FindBin::Bin/$FindBin::Script ended.");
