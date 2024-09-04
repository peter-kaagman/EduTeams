#! /usr/bin/env perl
#
# Dit script normaliseert de gedwonloade docentgegevens vanuit Magister.
# Ze worden toegevoegd aan de database indien voor de locatie teams gemaakt worden.
# 
use v5.11;
use strict;
use warnings;
use DBI;
use Data::Dumper;
use FindBin;
use Config::Simple;
use JSON;
use File::Slurp;
use lib "$FindBin::Bin/../../msgraph-perl/lib";

use Logger; # Om te loggen

my %config;
Config::Simple->import_from("$FindBin::Bin/../config/EduTeamsTest.cfg", \%config) or die("No config: $!");

my $logger = Logger->new(
    'filename' => "$FindBin::Bin/../Log/EduTeams.log",
    'verbose' => $config{'LOG_VERBOSE'}
);
$logger->make_log("$FindBin::Bin/$FindBin::Script started.");

my $driver = $config{'DB_DRIVER'};
my $db = "$FindBin::Bin/../".$config{'CACHE_DIR'}."/".$config{'DB_NAME'};
my $db_user = $config{'DB_USER'};
my $db_pass = $config{'DB_PASS'};
my $dsn = "DBI:$driver:dbname=$db";
my $dbh = DBI->connect($dsn, $db_user, $db_pass, { RaiseError => 1 })
    or die $DBI::errstr;

# Nadat de gegevens uit Magister opgehaald zijn kunnen de jaarlagen gemaakt worden.
# Jaarlagen zijn virtuele clusters die gemaakt worden door een query op magister
#
# Dit hoort eigenlijk in getMagister.pl te staan. Maar dat duurt eeuwen voor elke test run
# Er is een afhankelijkheid van een aantal zaken die getMagister regelt. Deze hier ff faken

# Database koppelingen maken maar niet leegmaken.
# docrooster
#$dbh->do('Delete From magisterdocentenrooster'); # Truncate the table 
my $qry = "Insert Into magisterdocentenrooster (docentid,teamid) values (?,?) ";
my $sth_magisterdocentenrooster = $dbh->prepare($qry);

# llnrooster
#$dbh->do('Delete From magisterleerlingenrooster'); # Truncate the table 
$qry = "Insert Into magisterleerlingenrooster (leerlingid,teamid) values (?,?) ";
my $sth_magisterleerlingenrooster = $dbh->prepare($qry);

# team
#$dbh->do('Delete From magisterteam'); # Truncate the table 
$qry = "Insert Into magisterteam (naam, type) values (?,?) ";
my $sth_magisterteam = $dbh->prepare($qry);
my $TeamsHoH; # ipv zoeken in de database
# De zoekhash ff vullen
my $sth = $dbh->prepare('Select rowid, naam From magisterteam');
$sth->execute();
while (my $row = $sth->fetchrow_hashref()){
    $TeamsHoH->{$row->{'naam'}} = $row->{'rowid'};
}
#print Dumper $TeamsHoH;

# Users
# Users dient als zoek hash 
my $sth_users = $dbh->prepare("Select azureid,upn,ROWID From users");
$sth_users->execute();
my $usersByUpn = $sth_users->fetchall_hashref('upn');

# Maakt een entry voor de groep als die nog niet bestaat
# Een groep kan toegewezen zijn aan verschillende docenten, kan dus al bestaan
# Geeft de ROWID terug
sub getMagisterTeamROWID {
    my $groep = shift;
    my $type = shift;
    #say "Opzoek naar een ROWID voor $groep";
    if ($TeamsHoH->{$groep}){
        # team gevonden => return ROWID
        #say "Gevonden $TeamsHoH->{$groep}";
        return $TeamsHoH->{$groep};
    }else{
        # Team niet gevonden => aanmaken
        # $qry = "Insert Into magisterteam (naam, type) values (?,?) ";
        $sth_magisterteam->execute($groep, $type);
        my $ROWID =  $dbh->last_insert_id("","","magisterteam","ROWID");
        $TeamsHoH->{$groep} = $ROWID;
        return $ROWID;
    }

}
#
# Einde afhankelijkheid



sub jaarLagen {
    #say "Sub jaarlagen";
    # Een jaarlaag wordt gebasseerd op geldige groepen in Magister.
    # Dwz dat de groepen docenten en leerlingen moeten hebben.
    # Van een groep zonder leerlingen worden de lln dus niet toegevoegd
    my $json = read_file("$FindBin::Bin/../config/".$config{'JAARLAGEN'}, { binmode => ':raw'});
    my $jaarlagen = decode_json $json;
    print Dumper $jaarlagen;
    my $sth_docentenzoeken = $dbh->prepare("Select docentid From magisterdocentenrooster Where teamid = ?");      # docenten zoeken van een team
    my $sth_leerlingenzoeken = $dbh->prepare("Select leerlingid From magisterleerlingenrooster Where teamid = ?");# leerlingen zoeken van een team
    my $sth = $dbh->prepare('Select * From magisterteam Where naam Like ?');    # zoek een team op naam
    
    # De hash jaarlagen doorlopen
    while (my($search,$jaarlaag_naam) = each (%{$jaarlagen})){
        # Zoek de teams die aan het filter voldoen (lesperiode toevoegen)
        #say "Zoeken naar ".$config{'MAGISTER_LESPERIODE'}.'-'.$search;
        $sth->execute( $config{'MAGISTER_LESPERIODE'}.'-'.$search );
        my $teams = $sth->fetchall_hashref('naam'); # gevonden teams ff in een hash zetten
        #say "gevonden";
        print Dumper $teams;
        # doorloop de gevonden teams
        while (my ($naam, $team) = each(%{$teams})){ 
            # ROWID ophalen voor de jaarlaag, dit voegt hem zonodig toe aan de tabel
            # Maak de naam incl de suffix _Jaarlaag
            my $jaarlaag_rowid = getMagisterTeamROWID($config{'MAGISTER_LESPERIODE'}.'-'.$jaarlaag_naam."_Jaarlaag", 'jaarlaag');
            my $team_rowid = $TeamsHoH->{$naam}; # team rowid van het team waar de leden uit opgehaald moeten worden
            # Docenten opvragen voor dit team uit het docentenrooster
            $sth_docentenzoeken->execute($team_rowid);
            while (my $row = $sth_docentenzoeken->fetchrow_hashref()){
                # ROWID van de jaarlaag is bekend en de ROWID van de docent
                #my $qry = "Insert Into magisterdocentenrooster (docentid,teamid) values (?,?) ";
                $sth_magisterdocentenrooster->execute($row->{'docentid'},$jaarlaag_rowid);
            }
            # Leerlingen opvragen voor dit team uit het leerlingenrooster
            $sth_leerlingenzoeken->execute($team_rowid);
            while (my $row = $sth_leerlingenzoeken->fetchrow_hashref()){
                # ROWID van de jaarlaag is bekend en de ROWID van de leerling
                #my $qry = "Insert Into magisterleerlingenrooster (leerlingid,teamid) values (?,?) ";
                $sth_magisterleerlingenrooster->execute($row->{'leerlingid'},$jaarlaag_rowid);
            }
            
        }
    }
    $sth->finish;
}

jaarLagen();