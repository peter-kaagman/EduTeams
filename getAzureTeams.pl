#! /usr/bin/env perl

use strict;
use warnings;
use v5.11;

use Data::Dumper;
use Config::Simple;
use DBI;
use Parallel::ForkManager;
use FindBin;
use lib "$FindBin::Bin/../msgraph-perl/lib";
use lib "$FindBin::Bin/lib";

use Shared;

use MsGroups;
use MsGroup;
use Logger;


my %config;
Config::Simple->import_from("$FindBin::Bin/config/EduTeams.cfg",\%config) or die("No config: $!");

my $logger = Logger->new(
    'filename' => "$FindBin::Bin/Log/EduTeams.log",
    'verbose' => $config{'LOG_VERBOSE'}
);

my $driver = $config{'DB_DRIVER'};
my $db = "$FindBin::Bin/".$config{'CACHE_DIR'}."/".$config{'DB_NAME'};
my $db_user = $config{'DB_USER'};
my $db_pass = $config{'DB_PASS'};
my $dsn = "DBI:$driver:dbname=$db";
my $dbh = DBI->connect($dsn, $db_user, $db_pass, { RaiseError => 1 })
    or die $DBI::errstr;    

# Als er row staan in teamcreated dan is createTeam.pl nog bezig
if (
        sync_can_run($dbh) &&                               # controle of createTeam.pl nog bezig is
        write_pid("$FindBin::Bin/Run/$config{'PID_FILE'}")  # PID moet wegeschreven zijn
){
    $logger->make_log("$FindBin::Script INFO started.");
}else{
    $logger->make_log("$FindBin::Script INFO kan niet starten.");
    exit 1;
}


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
#print Dumper $usersByUpn;
my $sth_users_update_memberid = $dbh->prepare('Update users set memberid = ? where azureid = ?');


my $groups_object = MsGroups->new(
	'app_id'        => $config{'APP_ID'},
	'app_secret'    => $config{'APP_PASS'},
	'tenant_id'     => $config{'TENANT_ID'},
	'login_endpoint'=> $config{'LOGIN_ENDPOINT'},
	'graph_endpoint'=> $config{'GRAPH_ENDPOINT'},
	'filter'        => '$filter=startswith(mailNickname,\'EduTeam_'.$config{'MAGISTER_LESPERIODE'}.'\')', # lesperiode in de select zodat alleen het huidige jaar opgehaald wordt
	#'filter'        => '$filter=startswith(mailNickname,\'Section_'.'\')', # lesperiode in de select zodat alleen het huidige jaar opgehaald wordt
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
    #my $teams_result;
	my $teams = $groups_object->groups_fetch();
    $logger->make_log("$FindBin::Script INFO ".scalar @{$teams}." teams gevonden.");
    #print Dumper \$teams;exit 1;

    # Vanaf hier met threads werken
    my $pm = Parallel::ForkManager->new($config{'AZURE_THREADS'}, "$FindBin::Bin/".$config{'CACHE_DIR'}."/");

    # Callback
    $pm->run_on_finish( sub{
        my ($pid,$exit_code,$ident,$exit,$core_dump,$team) = @_;
        if ($team->{error}){
            say "Er is iets fout gegaan: ", $team->{'error'};
            say $team->{'lastresult'};
            die("Er is iets fout gegaan: " . $team->{'error'});
        }

        my $teamROWID = getAzureTeamROWID($team);
        my $owners;
        foreach my $owner (@{$team->{'owners'}}){
            # Ff toevoegen aan een hash zodat ik kan checken om een member docent is
            $owners->{$usersByUpn->{ lc($owner->{'userPrincipalName'}) }->{'rowid'}} = $teamROWID;
            #my $qry = "Insert Into azuredocrooster (azureteam_id,azuredocent_id) values (?,?) ";
            $sth_azuredocrooster->execute($teamROWID, $usersByUpn->{ lc($owner->{'userPrincipalName'}) }->{'rowid'});
         }
        foreach my $member (@{$team->{'members'}}){
            # Een docent niet als leerling toevoegen
            #print Dumper $member;
            if (! $owners->{ $usersByUpn->{ lc($member->{'userPrincipalName'}) }->{'rowid'}  }){
                #$qry = "Insert Into azureleerlingrooster (azureteam_id,azureleerling_id) values (?,?) ";
                $sth_azureleerlingrooster->execute($teamROWID, $usersByUpn->{ lc($member->{'userPrincipalName'}) }->{'rowid'});
            }
         }

    });

    MEMBERS:
	foreach my $team (@{$teams}){
        # description en displayName kunnen aangepast zijn, naam halen uit de mailNick
        $team->{'mailNickname'} =~ /^EduTeam_($config{'MAGISTER_LESPERIODE'}.+)/;
        $team->{'secureName'} = $1;
        $logger->make_log("$FindBin::Script INFO Leden ophalen voor $team->{'secureName'}");
        my $pid = $pm->start($team->{'secureName'}) and next MEMBERS; # FORK
        #say "In runner";
        my $group_object = MsGroup->new(
            'app_id'        => $config{'APP_ID'},
            'app_secret'    => $config{'APP_PASS'},
            'tenant_id'     => $config{'TENANT_ID'},
            'login_endpoint'=> $config{'LOGIN_ENDPOINT'},
            'graph_endpoint'=> $config{'GRAPH_ENDPOINT'},
            'select'        => '$select=id,displayName,userPrincipalName',
            'access_token'  => $groups_object->_get_access_token,
            'token_expires' => $groups_object->_get_token_expires,
            'id'            =>  $team->{'id'},
        );
        # De eerste waarde in finish is de exit_code, de twee de data reference
        # Van een nog niet geactiveerd team zijn de leerlingen (nog) geen lid
        # Leden opvragen moet dus via de groups endpoint ipv teams
        # Members en Owners gaat in 2 requests echter
        $team->{'members'} = $group_object->group_fetch_members();
        if ($group_object->_get_errorstate){
            $team->{'error'} = $group_object->_get_errorstate;
            $team->{'lastresult'} = $group_object->_get_lastresult;
        }
        $team->{'owners'} = $group_object->group_fetch_owners();
        if ($group_object->_get_errorstate){
            $team->{'error'} = $group_object->_get_errorstate;
            $team->{'lastresult'} = $group_object->_get_lastresult;
        }
        $pm->finish(0,$team); # exit child
	}
    $pm->wait_all_children;
}else{
	$logger->make_log("$FindBin::Script No token!");
}
$logger->make_log("$FindBin::Script ended.");
