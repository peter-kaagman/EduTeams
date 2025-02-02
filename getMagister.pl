#! /usr/bin/env perl
#
# Dit script normaliseert de gedwonloade docent- en leerling gegevens vanuit Magister.
# Ze worden toegevoegd aan de database indien voor de locatie teams gemaakt worden.
# 

use v5.11;
use strict;
use warnings;
use DBI;
use Data::Dumper;
use FindBin;
use JSON;
use File::Slurp;
use Config::Simple;
use Time::Piece;
#use Parallel::ForkManager;
use lib "$FindBin::Bin/../magister-perl/lib";
use lib "$FindBin::Bin/../msgraph-perl/lib";
use lib "$FindBin::Bin/lib";

use Shared;

use Magister; # Diverse magister functies
use Logger; # Om te loggen

my %config;
Config::Simple->import_from("$FindBin::Bin/config/EduTeams.cfg", \%config) or die("No config: $!");

my $logger = Logger->new(
    'filename' => "$FindBin::Bin/Log/EduTeams.log",
    'verbose' => $config{'LOG_VERBOSE'}
);
$logger->make_log("$FindBin::Script started.");

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
# docrooster
$dbh->do('Delete From magisterdocentenrooster'); # Truncate the table 
my $qry = "Insert Into magisterdocentenrooster (docentid,teamid) values (?,?) ";
my $sth_magisterdocentenrooster = $dbh->prepare($qry);

# llnrooster
$dbh->do('Delete From magisterleerlingenrooster'); # Truncate the table 
$qry = "Insert Into magisterleerlingenrooster (leerlingid,teamid) values (?,?) ";
my $sth_magisterleerlingenrooster = $dbh->prepare($qry);

# team
$dbh->do('Delete From magisterteam'); # Truncate the table 
$qry = "Insert Into magisterteam (naam, locatie, type) values (?,?,?) ";
my $sth_magisterteam = $dbh->prepare($qry);
my $TeamsHoH; # ipv zoeken in de database

# Users
# Users dient als zoek hash 
# Alleen active users in de resultset issue 12
my $sth_users = $dbh->prepare("Select azureid,upn,ROWID From users Where active = 1");
$sth_users->execute();
my $usersByUpn = $sth_users->fetchall_hashref('upn');

# Magister object om magister dingen mee te doen
my $mag_session= Magister->new(
    'user'          => $config{'MAGISTER_USER'},
    'secret'        => $config{'MAGISTER_SECRET'},
    'endpoint'      => $config{'MAGISTER_URL'},
    'lesperiode'    => $config{'MAGISTER_LESPERIODE'}

);


# Maakt een entry voor de groep als die nog niet bestaat
# Een groep kan toegewezen zijn aan verschillende docenten, kan dus al bestaan
# Geeft de ROWID terug
sub getMagisterTeamROWID {
    my $groep = shift;
    my $locatie = shift;
    my $type = shift;
    #say "Opzoek naar een ROWID voor $groep";
    if ($TeamsHoH->{$groep}){
        # team gevonden => return ROWID
        return $TeamsHoH->{$groep};
    }else{
        # Team niet gevonden => aanmaken
        #"Insert Into magisterteam (naam, locatie, type) values (?,?,?) ";
        $sth_magisterteam->execute($groep, $locatie, $type);
        my $ROWID =  $dbh->last_insert_id("","","magisterteam","ROWID");
        $TeamsHoH->{$groep} = $ROWID;
        return $ROWID;
    }

}

sub Docenten {
    # De query haalt zowel lesgroepen als vakgroepen op
    # De vakgroep moet gecombineerd worden met de vakcode
    my $lesgroepen = $mag_session->getLayout('EduTeam-Doc-lesgroep','lesperiode='.$config{'MAGISTER_LESPERIODE'}); # vakken is een AoH
    foreach my $lesgroep (@{$lesgroepen}){
        # Alleen de aktieve locaties vlgs config
        if ($lesgroep->{'team'} =~/^$config{'MAGISTER_LESPERIODE'}-($config{'AKTIEVE_LOCATIES'}).+/){
            # printf("%s %s\n", $lesgroep->{"\x{feff}email"}, $lesgroep->{"team"});
            my $rowidDoc = $usersByUpn->{ lc($lesgroep->{"\x{feff}email"}) }->{'rowid'};
            # Alleen door als er een rowID is voor de docent => hij bestaat in Azure
            if ($rowidDoc){
                my $rowidTeam = getMagisterTeamROWID($lesgroep->{'team'}, $lesgroep->{'LocatieCode'}, 'cluster');
                # Er zijn nu voldoende gevens om hier een rooster entry voor te maken
                $logger->make_log("$FindBin::Script INFO " . $lesgroep->{"\x{feff}email"} . " => $rowidDoc => $lesgroep->{'team'} : $rowidTeam");
                #my $qry = "Insert Into magisterdocentenrooster (docid,teamid) values (?,?) ";
                $sth_magisterdocentenrooster->execute($rowidDoc,$rowidTeam);
            }else{
        #         say Dumper $lesgroep;
                $logger->make_log("$FindBin::Script WARNING Docent => ".$lesgroep->{"\x{feff}email"}." bestaat niet in Azure of is niet aktief");
            }
        # }else{
        #     say "Niet aktief";
        #     say Dumper $lesgroep;
        }
    }
}

sub Leerlingen {
    # We gaan niet langer per leerling de roosters opvragen
    # Issue 8 
    # We vragen middels een UNION ook gelijk vakken EN clusters op
    # StamNr en Team naam komen formatted terug uit de query
    my $vakken_clusters = $mag_session->getLayout('EduTeam-Lln-lesgroep','lesperiode='.$config{'MAGISTER_LESPERIODE'}); 
    foreach my $vak (@{$vakken_clusters}){
        if ($vak->{'code'} =~/^$config{'MAGISTER_LESPERIODE'}-($config{'AKTIEVE_LOCATIES'}).+/){
            # printf("%s %s\n", $vak->{"\x{feff}b_nummer"}, $vak->{'code'});
            # Alleen door als er een rowID is voor de lln => hij bestaat in Azure
            my $upn = $vak->{"\x{feff}b_nummer"}.'@atlascollege.nl';
            my $rowidLln = $usersByUpn->{$upn}->{'rowid'};
            if ($rowidLln){
                # Als het rowid voor dit team niet bestaat dan is er geen docent voor de groep
                my $rowidTeam = $TeamsHoH->{$vak->{'code'}};
                if ($rowidTeam){
                    # say "Deze wel $vak->{'code'} => $upn : $rowidLln => $vak->{'code'} : $rowidTeam";
                    $logger->make_log("$FindBin::Script INFO  $upn => $rowidLln => $vak->{'code'} : $rowidTeam");
                    # "Insert Into magisterleerlingenrooster (leerlingid,teamid) values (?,?) ";
                    $sth_magisterleerlingenrooster->execute($rowidLln,$rowidTeam);
                # }else{
                #     say "$vak->{'code'} heeft geen docent";
                }
            }else{
                $logger->make_log("$FindBin::Script WARNING leerling => $upn bestaat niet in Azure");
            }
        # } else {
        #     say "Geen aktieve locatie"
        }
    }
}


sub Jaarlagen {
    $logger->make_log("$FindBin::Script Jaarlagen maken gestart");                    
    # # Een jaarlaag wordt gebasseerd op geldige groepen in Magister.
    # # Dwz dat de groepen docenten en leerlingen moeten hebben.
    # # Van een groep zonder leerlingen worden de lln dus niet toegevoegd
    my $json = read_file("$FindBin::Bin/config/".$config{'JAARLAGEN'}, { binmode => ':raw'});
    #say "JSON is $json";
    my $jaarlagen = decode_json($json);
    #print Dumper $jaarlagen;
    my $sth_docentenzoeken = $dbh->prepare("Select docentid From magisterdocentenrooster Where teamid = ?");      # docenten zoeken van een team
    my $sth_leerlingenzoeken = $dbh->prepare("Select leerlingid From magisterleerlingenrooster Where teamid = ?");# leerlingen zoeken van een team
    my $sth = $dbh->prepare('Select * From magisterteam Where naam Like ?');    # zoek een team op naam
    
    # De hash jaarlagen doorlopen
    while (my($search,$jaarlaag_naam) = each (%{$jaarlagen})){
        #say "We gaan zoeken naar $search die krijgt de naam $jaarlaag_naam";
        # Zoek de teams die aan het filter voldoen (lesperiode toevoegen)
        $sth->execute($config{'MAGISTER_LESPERIODE'}.'-'.$search);
        my $teams = $sth->fetchall_hashref('naam'); # gevonden teams ff in een hash zetten
        #say "Gevonden teams voor jaarlaag";
        #print Dumper $teams;
        # doorloop de gevonden teams
        while (my ($naam, $team) = each(%{$teams})){
            #say "Leden ophalen uit $naam"; 
            # ROWID ophalen voor de jaarlaag, dit voegt hem zonodig toe aan de tabel
            my $jaarlaag_rowid = getMagisterTeamROWID($config{'MAGISTER_LESPERIODE'}.'-'.$jaarlaag_naam."_Jaarlaag", 'jaarlaag');
            #say "Jaarlaag rowid $jaarlaag_rowid";
            my $team_rowid = $TeamsHoH->{$naam}; # team rowid van het team waar de leden uit opgehaald moeten worden
            #say "team rowid $team_rowid";
            # Docenten opvragen voor dit team uit het docentenrooster
            $sth_docentenzoeken->execute($team_rowid);
            while (my $row = $sth_docentenzoeken->fetchrow_hashref()){
                # ROWID van de jaarlaag is bekend en de ROWID van de docent
                #say "Deze docent toevoegen $row->{'docentid'}";
                #my $qry = "Insert Into magisterdocentenrooster (docentid,teamid) values (?,?) ";
                $sth_magisterdocentenrooster->execute($row->{'docentid'},$jaarlaag_rowid);
            }
            # Leerlingen opvragen voor dit team uit het leerlingenrooster
            $sth_leerlingenzoeken->execute($team_rowid);
            while (my $row = $sth_leerlingenzoeken->fetchrow_hashref()){
                # ROWID van de jaarlaag is bekend en de ROWID van de leerling
                #say "Deze leerling toevoegen $row->{'leerlingid'}";
                #my $qry = "Insert Into magisterleerlingenrooster (leerlingid,teamid) values (?,?) ";
                $sth_magisterleerlingenrooster->execute($row->{'leerlingid'},$jaarlaag_rowid);
            }
            
        }
    }
    $sth->finish;
    $sth_docentenzoeken->finish;
    $sth_leerlingenzoeken->finish;
}

my $start = localtime->epoch;
$logger->make_log("$FindBin::Script INFO Start docenten rooster @ ". localtime);
Docenten();
my $einde = localtime->epoch;
$logger->make_log("$FindBin::Script INFO Einde docenten rooster @ ". localtime . " duurde " . ($einde-$start) . " seconden");

$start = localtime->epoch;
$logger->make_log("$FindBin::Script INFO Start leerlingen rooster @ ". localtime);
Leerlingen();
$einde = localtime->epoch;
$logger->make_log("$FindBin::Script INFO Einde leerlingen rooster @ ". localtime . " duurde " . ($einde-$start) . " seconden");

$logger->make_log("$FindBin::Script INFO Start jaarlagen @ ". localtime);
Jaarlagen();
$logger->make_log("$FindBin::Script INFO Einde jaarlagen @ ". localtime);

$sth_users->finish;
$sth_magisterteam->finish;
$sth_magisterdocentenrooster->finish;
$sth_magisterleerlingenrooster->finish;
$dbh->disconnect;
$logger->make_log("$FindBin::Script ended.");
