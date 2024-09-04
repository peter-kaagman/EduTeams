#! /usr/bin/env perl
#
# Dit script normaliseert de gedwonloade docent- en leerling gegevens vanuit Magister.
# Ze worden toegevoegd aan de database indien voor de locatie teams gemaakt worden.
# 
# #32 
# Pre rebuild
# docenten => 167 seconden
# leerlinge => 33' 23"
#
# Post rebuild
# INFO Start docenten rooster @ Tue Jul  9 23:07:02 2024
# INFO Einde docenten rooster @ Tue Jul  9 23:08:03 2024 duurde 61 seconden
# Start leerlingen rooster @ Tue Jul  9 23:08:03 2024
# INFO Einde leerlingen rooster @ Tue Jul  9 23:15:18 2024 duurde 435 seconden

use v5.11;
use strict;
use warnings;
#use Text::CSV qw( csv ); # CSV afhandeling in Magister.pm
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
$qry = "Insert Into magisterteam (naam, type) values (?,?) ";
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
    my $type = shift;
    #say "Opzoek naar een ROWID voor $groep";
    if ($TeamsHoH->{$groep}){
        # team gevonden => return ROWID
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

sub Docenten {
    my $docenten = $mag_session->getDocenten(); # $docenten is een HOH indexed op upn
    #print Dumper $docenten;
    my $pm = Parallel::ForkManager->new($config{'MAGISTER_THREADS'}, "$FindBin::Bin/".$config{'CACHE_DIR'}."/");

    # Callback
    $pm->run_on_finish( sub{
        my ($pid,$exit_code,$ident,$exit,$core_dump,$data) = @_;
        if ($data->{error}){
            say "Er is iets fout gegaan: ", $data->{'error'};
            say $data->{'lastresult'};
            die("Er is iets fout gegaan: " . $data->{'error'});
        }
        my $groepen = $data->{'rooster'};
        if ($groepen){
#            foreach my $groep (keys %$groepen){
            while ( my ($groep_key,$groep)  = each(%$groepen)){
                # Is het een groep van een aktieve locatie
                if ($groep_key =~/^($config{'AKTIEVE_LOCATIES'}).+/){
                    # ROWID moet in usersByUpn staan, anders staat de docent niet in Azure
                    # Prefix groep met lesperiode uit conifg
                    my $groep_formatted = $config{'MAGISTER_LESPERIODE'}.'-'.$groep->{'klas'};
                    # Groepen met een punt in de naam zijn clustergroepen
                    # Zonder punt zijn klassengroepen, hier moet nog "-vak" aan toegevoegd worden.
                    # anders zijn ze niet uniek.
                    my $type = "clustergroep"; # Uitgaan van clustergroep
                    if ( $groep->{'klas'} !~ /\./ ){
                        #print Dumper $groepen->{$groep};
                        $type = "klasgroep"; # wijzigen indien van toepassing
                        $groep_formatted = $groep_formatted."-".$groep->{'code'};
                    }
                    # ROWID ophalen voor de groep
                    my $teamROWID = getMagisterTeamROWID($groep_formatted,$type);
                    # Beide ROWIDs zijn nu bekend => roosterentry maken
                    #my $qry = "Insert Into magisterdocentenrooster (docid,teamid) values (?,?) ";
                    $sth_magisterdocentenrooster->execute($usersByUpn->{$ident}->{'rowid'},$teamROWID);
                    $logger->make_log("$FindBin::Script DEBUG Docent => $ident => $groep_formatted");
                }
            }
        }
        #$par_result->{$ident} = scalar keys %{$vakken};
    });

    DOC_ROOSTER:
    while (my ($upn,$docent) = each(%$docenten)){
        # Alleen door als er een UPN is en deze in de hash staat
        if ($upn && $usersByUpn->{$upn}){
            my $pid = $pm->start($upn) and next DOC_ROOSTER; # FORK
            my $doc_vakken;
            $doc_vakken->{'rooster'}= $mag_session->getRooster($docent->{'stamnr'},"GetPersoneelGroepVakken");
            if ($mag_session->_get_errorstate){
                $doc_vakken->{'error'} = $mag_session->_get_errorstate;
                $doc_vakken->{'lastresult'} = $mag_session->_get_lastresult;
            }
            # De eerste waarde in finish is de exit_code, de twee de data reference
            $pm->finish(42,$doc_vakken); # exit child
        }else{
            $logger->make_log("$FindBin::Script WARNING De UPN $upn voor docent:$docent->{'naam'} kan niet worden gevonden in Azure");
        }
    }
    $pm->wait_all_children;
}

sub Leerlingen {
    my $leerlingen = $mag_session->getLeerlingen(); # $leerlingen is een HOH indexed op upn
    my $pm = Parallel::ForkManager->new($config{'MAGISTER_THREADS'}, "$FindBin::Bin/".$config{'CACHE_DIR'}."/"); 

    # Callback
    $pm->run_on_finish( sub{
        my ($pid,$exit_code,$ident,$exit,$core_dump,$roosters) = @_;
        if ($roosters->{error}){
            say "Er is iets fout gegaan: ", $roosters->{'error'};
            say $roosters->{'lastresult'};
            die("Er is iets fout gegaan: " . $roosters->{'error'});
        }
        foreach my $groep (keys %{ $roosters->{'groepen'} }){
            #say "Groep is: $groep";
            # Alleen doorgaan als de groep in $TeamsHoH staat en er dus een docent voor is
            # Hievoor is de formatted groep naam nodig
            # <lesperiode>-<groepnaam>
            my $groep_formatted = $config{'MAGISTER_LESPERIODE'}.'-'.$groep; # $groep niet aanpassen, dat is de index van de hash
            #say "Formatted: $groep_formatted";
            if($TeamsHoH->{$groep_formatted}){
                # $qry = "Insert Into magisterleerlingenrooster (leerlingid,teamid) values (?,?) ";
                $sth_magisterleerlingenrooster->execute($usersByUpn->{$ident}->{'rowid'},$TeamsHoH->{$groep_formatted});
                $logger->make_log("$FindBin::Script DEBUG Leerling => $ident => $groep_formatted");
            }
        }
        # Voor een leerling vakken krijg je alleen de vakcodes terug
        # Deze moet gecombineerd worden al <klas>-<vakcode>
        foreach  my $vakcode (keys %{ $roosters->{'vakken'} }){
            # Alleen doorgaan als vak in $TeamsHoH staat en er dus een docent voor is
            # Hievoor is de formatted vak naam nodig
            # <lesperiode>-<klas>-<vakcode>
            my $vaknaam_formatted = $config{'MAGISTER_LESPERIODE'}.'-'.$roosters->{'klas'}."-".$vakcode; # $vakcode niet aanpassen, dat is de index van de hash
            #say "Formatted: $vaknaam_formatted";
            if($TeamsHoH->{$vaknaam_formatted}){
                # $qry = "Insert Into magisterleerlingenrooster (leerlingid,teamid) values (?,?) ";
                $sth_magisterleerlingenrooster->execute($usersByUpn->{$ident}->{'rowid'},$TeamsHoH->{$vaknaam_formatted});
                $logger->make_log("$FindBin::Script DEBUG Leerling => $ident => $vaknaam_formatted");
            }
        }
    });

    LLN_ROOSTER:
    while (my ($upn,$leerling) = each(%$leerlingen)){
        # Alleen door als de lln in Azure staat
        # En als er ook daadwerkelijk een UPN is
        if ($upn && $usersByUpn->{$upn}){
            # Alleen lln behandelen van aktieve scholen
            if ($leerling->{'studie'} =~ /^($config{'AKTIEVE_LOCATIES'}).+/){
                my $pid = $pm->start($upn) and next LLN_ROOSTER; # FORK
                my $result;
                # $leerling->{'klas'} is nodig in de callback, toevoegen aan de $result die overgedragen wordt
                $result->{'klas'} = $leerling->{'klas'};
                # Voor leerlingen staan de cluster- en vakgroepen apart in Magister
                # say "Leerling clustergroepen";
                $result->{'groepen'} = $mag_session->getRooster($leerling->{'stamnr'},"GetLeerlingGroepen"); # Rooster aanvraag voor een leerling
                if ($mag_session->_get_errorstate){
                    $result->{'error'} = $mag_session->_get_errorstate;
                    $result->{'lastresult'} = $mag_session->_get_lastresult;
                }
                # say "Leerling vakken";
                $result->{'vakken'} = $mag_session->getRooster($leerling->{'stamnr'},"GetLeerlingVakken"); # Rooster aanvraag voor een leerling 
                if ($mag_session->_get_errorstate){
                    $result->{'error'} = $mag_session->_get_errorstate;
                    $result->{'lastresult'} = $mag_session->_get_lastresult;
                }
                $pm->finish(42,$result); # exit child
            }
        }
    }
    $pm->wait_all_children;
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
