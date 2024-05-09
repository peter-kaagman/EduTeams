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
Config::Simple->import_from("$FindBin::Bin/EduTeams.cfg",\%config) or die("No config: $!");

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
my $qry = "Insert Into azuredocent (upn, naam) values (?,?) ";
my $sth_azuredocent = $dbh->prepare($qry);
$qry = "Select ROWID From azuredocent Where upn = ?";
my $sth_azuredocent_zoeken = $dbh->prepare($qry);

# azuredocrooster
$dbh->do('Delete From azuredocrooster'); # Truncate the table 
$qry = "Insert Into azuredocrooster (azureteam_id,azuredocent_id) values (?,?) ";
my $sth_azuredocrooster = $dbh->prepare($qry);

# azureleerling
$dbh->do('Delete From azureleerling'); # Truncate the table 
$qry = "Insert Into azureleerling (upn, naam) values (?,?) ";
my $sth_azureleerling = $dbh->prepare($qry);
$qry = "Select ROWID From azureleerling Where upn = ?";
my $sth_azureleerling_zoeken = $dbh->prepare($qry);

# azureleerlingrooster
$dbh->do('Delete From azureleerlingrooster'); # Truncate the table 
$qry = "Insert Into azureleerlingrooster (azureteam_id,azureleerling_id) values (?,?) ";
my $sth_azureleerlingrooster = $dbh->prepare($qry);

# azureteam
$dbh->do('Delete From azureteam'); # Truncate the table 
$qry = "Insert Into azureteam (id, description, displayName) values (?,?,?) ";
my $sth_azureteam = $dbh->prepare($qry);
# Een azure team bestaat nooit, hoef dus niet te zoeken
#$qry = "Select ROWID From azureteam Where naam = ?";
#my $sth_azureteam_zoeken = $dbh->prepare($qry);

my $groups_object = MsGroups->new(
	'app_id'        => $config{'APP_ID'},
	'app_secret'    => $config{'APP_PASS'},
	'tenant_id'     => $config{'TENANT_ID'},
	'login_endpoint'=> $config{'LOGIN_ENDPOINT'},
	'graph_endpoint'=> $config{'GRAPH_ENDPOINT'},
	'filter'        => '$filter=startswith(mail,\'Section_\')',
    'select'        => '$select=id,displayName,description,mail',
);


# Maakt een entry voor de docent als die nog niet bestaat
# Geeft de ROWID terug
sub getAzureDocentROWID {
    my $docent = shift;
    $sth_azuredocent_zoeken->execute(lc($docent->{'userPrincipalName'}));
    my $row = $sth_azuredocent_zoeken->fetchrow_hashref();
    #print Dumper $row;
    if ($row->{'rowid'}){
        # docent gevonden => return ROWID
        return $row->{'rowid'};
    }else{
        # Docent niet gevonden => aanmaken
        #print Dumper $docent;
        #my $qry = "Insert Into azuredocent (upn, naam) values (?,?) ";
        $sth_azuredocent->execute(lc($docent->{'userPrincipalName'}),$docent->{'displayName'});
        return $dbh->last_insert_id("","","azuredocent","ROWID");
    }
}
# Maakt een entry voor de leerling als die nog niet bestaat
# Geeft de ROWID terug
sub getAzureLeerlingROWID {
    my $leerling = shift;
    $sth_azureleerling_zoeken->execute(lc($leerling->{'userPrincipalName'}));
    my $row = $sth_azureleerling_zoeken->fetchrow_hashref();
    #print Dumper $row;
    if ($row->{'rowid'}){
        # leerling gevonden => return ROWID
        return $row->{'rowid'};
    }else{
        # Leerling niet gevonden => aanmaken
        #print Dumper $docent;
        #my $qry = "Insert Into azuredocent (upn, naam) values (?,?) ";
        $sth_azureleerling->execute(lc($leerling->{'userPrincipalName'}),$leerling->{'displayName'});
        return $dbh->last_insert_id("","","azureleerling","ROWID");
    }
}

# Maakt een entry voor de groep, deze zal nooit bestaan.
# Geeft de ROWID terug
sub getAzureTeamROWID {
    my $group = shift;
    #$qry = "Insert Into azureteam (id, description, displayName) values (?,?,?) ";
    $sth_azureteam->execute($group->{'id'},$group->{'description'},$group->{'displayName'});
    return $dbh->last_insert_id("","","azureteam","ROWID");
}

if ($groups_object->_get_access_token){
    # Eerst de groepen ophalen in Graph
	my $groups = $groups_object->fetch_groups();
	my $count = scalar @$groups;
	$logger->make_log("$FindBin::Bin/$FindBin::Script $count groupen opgehaald.");
	while (my ($i, $group) = each @{$groups}){
        
        # Normalize description, in sommige gevallen staat de LOC ervoor
        # Dit voorkomt ook dat ik kan filteren op description
        $group->{'description'} =~ s/.+\w\w\w\s(.+)/$1/;
        # Alleen het huidige studiejaar
        if ($group->{'description'} =~ /^$config{'STUDIE_JAAR'}/){
            $logger->make_log("$FindBin::Bin/$FindBin::Script Team gevonden: ". $group->{description});
            my $azureteamROWID = getAzureTeamROWID($group);
            # Object maken voor deze groep met het doel owers en leden op te halen
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
                $logger->make_log("$FindBin::Bin/$FindBin::Script Docent gevonden: ".$owner->{'displayName'});
                my $azuredocentROWID = getAzureDocentROWID($owner);
                # RowId docent en team is bekend => toevoegen aan het rooster
                $sth_azuredocrooster->execute($azureteamROWID,$azuredocentROWID)
            }
            # Leden (leerlingen ophalen)
            my $members = $group_object->fetch_members();
            # $members is een AOH
            foreach my $member (@$members){
                # NB Docenten zijn zelf ook lid, deze dus overslaan
                if ($member->{'userPrincipalName'} =~ /^b[0-9]{6}.*/){  # UPN begint met een b nummer
                    $logger->make_log("$FindBin::Bin/$FindBin::Script Leerling gevonden:".$member->{'displayName'});
                    my $azureleerlingROWID = getAzureLeerlingROWID($member);
                    # RowId leerling en team is bekend => toevoegen aan het rooster
                    $sth_azureleerlingrooster->execute($azureteamROWID,$azureleerlingROWID);
                }
            }
        }
	}
}else{
	$logger->make_log("$FindBin::Bin/$FindBin::Script No token!");
}
$logger->make_log("$FindBin::Bin/$FindBin::Script ended.");
