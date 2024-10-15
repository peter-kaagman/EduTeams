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
use Parallel::ForkManager;
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
my $sth_users = $dbh->prepare("Select azureid,upn,ROWID From users");
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
    # We gaan niet langer per docent de roosters opvragen
    # we vragen echter een één custom queries op voor vakken en groepen

    #Clusters:
    #Declare @periode varchar(4)='#lesperiode#'
    #SELECT DISTINCT
    #    sis_pers.stamnr AS stamnummer,
    #    sis_pers.E_Mailwerk AS email,
    #    sis_bgrp.groep as KlasGroep,
    #    sis_blok.c_lokatie as LocatieCode,
    #    sis_pgvk.c_vak
    #FROM sis_pgvk
    #    LEFT JOIN sis_pers on sis_pgvk.idPers=sis_pers.idPers
    #    LEFT JOIN sis_bgrp on sis_pgvk.idBgrp=sis_bgrp.idBgrp
    #    LEFT JOIN sis_blpe on sis_pgvk.lesperiode=sis_blpe.lesperiode
    #    LEFT JOIN sis_bvak on sis_pgvk.c_vak=sis_bvak.c_vak
    #    LEFT JOIN sis_blok on sis_bgrp.c_lokatie=sis_blok.c_lokatie
    #WHERE 
    #    sis_blpe.lesperiode = @periode

    # De query haalt zowel lesgroepen als vakgroepen op
    # De vakgroep moet gecombineerd worden met de vakcode
    my $lesgroepen = $mag_session->getLayout('EduTeam-Doc-lesgroep','lesperiode='.$config{'MAGISTER_LESPERIODE'}); # vakken is een AoH
    foreach my $lesgroep (@{$lesgroepen}){
        # Alleen de aktieve locaties vlgs config
        if ($lesgroep->{'KlasGroep'} =~/^($config{'AKTIEVE_LOCATIES'}).+/){
            my $rowidDoc = $usersByUpn->{ lc($lesgroep->{'email'}) }->{'rowid'};
            # Alleen door als er een rowID is voor de docent => hij bestaat in Azure
            if ($rowidDoc){
                #say Dumper $lesgroep;
        my ($rowidTeam, $formattedTeamName);
        if ($lesgroep->{'KlasGroep'} =~ /^\d.+\..+/){
                $formattedTeamName = $config{'MAGISTER_LESPERIODE'}.'-'.$lesgroep->{'KlasGroep'};
                $rowidTeam = getMagisterTeamROWID($formattedTeamName, $lesgroep->{'LocatieCode'}, 'cluster');
        }else{
                $formattedTeamName = $config{'MAGISTER_LESPERIODE'}.'-'.$lesgroep->{'KlasGroep'}.'-'.$lesgroep->{'Vak'};
                $rowidTeam = getMagisterTeamROWID($formattedTeamName, $lesgroep->{'LocatieCode'}, 'cluster');
        }
                # Er zijn nu voldoende gevens om hier een rooster entry voor te maken
        $logger->make_log("$FindBin::Script INFO $lesgroep->{'email'} : $rowidDoc => $formattedTeamName : $rowidTeam");
                #my $qry = "Insert Into magisterdocentenrooster (docid,teamid) values (?,?) ";
                $sth_magisterdocentenrooster->execute($rowidDoc,$rowidTeam);
            }else{
                say Dumper $lesgroep;
                $logger->make_log("$FindBin::Script WARNING Docent => $lesgroep->{'email'} bestaat niet in Azure");
            }
        }
    }
}

sub Leerlingen {
    # We gaan niet langer per leerling de roosters opvragen
    # we vragen echter een tweetal custom queries op voor vakken en groepen
    
    #Vakken:
    #Declare @periode varchar(4)='#lesperiode#'
    #SELECT DISTINCT
    #    sis_lvak.idleer AS id_leerling,
    #    sis_lvak.stamnr AS stamnr,
    #    sis_bgrp.groep AS groep,
    #    sis_lvak.c_vak AS course
    #FROM sis_lvak
    #    INNER JOIN sis_aanm ON sis_lvak.stamnr = sis_aanm.stamnr
    #    INNER JOIN sis_bgrp ON sis_bgrp.idbgrp = sis_aanm.idbgrp
    #    INNER JOIN sis_bvak ON sis_lvak.c_vak = sis_bvak.c_vak
    #WHERE
    #    sis_lvak.dbegin <= GETDATE()
    #    AND
    #    sis_lvak.deinde > GETDATE()
    #    AND
    #    sis_aanm.lesperiode = @periode
    #ORDER BY 
    #    sis_lvak.idleer
    my $vakken = $mag_session->getLayout('EduTeam-Lln-vakken','lesperiode='.$config{'MAGISTER_LESPERIODE'}); # vakken is een AoH, geen lesperiode nodig
    foreach my $vak (@{$vakken}){
        # Alleen de aktieve locaties vlgs config
        if ($vak->{'groep'} =~/^($config{'AKTIEVE_LOCATIES'}).+/){
	        # Eerst een UPN maken van het stambr
	        my $upn = "b$vak->{'Stamnr'}\@atlascollege.nl";
            my $rowidLln = $usersByUpn->{$upn}->{'rowid'};
            # Alleen door als er een rowID is voor de docent => hij bestaat in Azure
            if ($rowidLln){
                # Dit zijn vakken, de team naam moet dus samengesteld worden
                my $formattedTeamName = $config{'MAGISTER_LESPERIODE'}.'-'.$vak->{'groep'} . '-' . $vak->{'course'};
                # Als het rowid voor dit team niet bestaat dan is er geen docent voor de groep
                my $rowidTeam = $TeamsHoH->{$formattedTeamName};
                if ($rowidTeam){
                    #say "Deze wel $vak->{'groep'} => $upn : $rowidLln => $formattedTeamName : $rowidTeam";
                    # "Insert Into magisterleerlingenrooster (leerlingid,teamid) values (?,?) ";
                    $sth_magisterleerlingenrooster->execute($rowidLln,$rowidTeam);
                }else{
                    #$logger->make_log("$FindBin::Script INFO groep $formattedTeamName heeft geen docent");
                }
            }else{
                $logger->make_log("$FindBin::Script WARNING leerling => $upn bestaat niet in Azure");
            }
	    }
    }

    #Clusters:
    #SELECT
    #    sis_lvak.idleer AS id_leerling,
    #    sis_lvak.stamnr AS stamnr,
    #    sis_bgrp.groep AS groep
    #FROM sis_lvak
    #    INNER JOIN sis_bgrp ON sis_lvak.idBgrp=sis_bgrp.idBgrp
    #    INNER JOIN sis_bvak ON sis_lvak.c_vak = sis_bvak.c_vak
    #WHERE
    #    sis_lvak.dbegin <= GETDATE()
    #    AND
    #    sis_lvak.deinde > GETDATE()
    #ORDER BY
    #    sis_lvak.idleer

    my $lesgroepen = $mag_session->getLayout('EduTeam-Lln-lesgroep'); # vakken is een AoH
    foreach my $lesgroep (@{$lesgroepen}){
        # Alleen de aktieve locaties vlgs config
        if ($lesgroep->{'groep'} =~/^($config{'AKTIEVE_LOCATIES'}).+/){
          # Eerst een UPN maken van het stamnr
          my $upn = "b$lesgroep->{'Stamnr'}\@atlascollege.nl";
          my $rowidLln = $usersByUpn->{$upn}->{'rowid'};
          # Alleen door als er een rowID is voor de docent => hij bestaat in Azure
          if ($rowidLln){
            my $formattedTeamName = $config{'MAGISTER_LESPERIODE'}.'-'.$lesgroep->{'groep'};
            # Als het rowid voor dit team niet bestaat dan is er geen docent voor de groep
            my $rowidTeam = $TeamsHoH->{$formattedTeamName};
            if ($rowidTeam){
              say "Deze wel $lesgroep->{'groep'} => $upn : $rowidLln => $formattedTeamName : $rowidTeam";
              # "Insert Into magisterleerlingenrooster (leerlingid,teamid) values (?,?) ";
              $sth_magisterleerlingenrooster->execute($rowidLln,$rowidTeam);
            }else{
              #$logger->make_log("$FindBin::Script INFO groep $formattedTeamName heeft geen docent");
            }
          }else{
            say Dumper $lesgroep;
            $logger->make_log("$FindBin::Script WARNING Leerling => $upn bestaat niet in Azure");
          }
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
