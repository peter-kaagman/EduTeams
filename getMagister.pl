#! /usr/bin/env perl
#
# Dit script normaliseert de gedwonloade docent- en leerling gegevens vanuit Magister.
# Ze worden toegevoegd aan de database indien voor de locatie teams gemaakt worden.
# 
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
use lib "$FindBin::Bin/lib";

use Magister; # Diverse magister functies
use Logger; # Om te loggen

my $logger = Logger->new(
    'filename' => "$FindBin::Bin/Log/EduTeams.log",
    'verbose' => 0
);
$logger->make_log("$FindBin::Bin/$FindBin::Script started.");

my %config;
Config::Simple->import_from("$FindBin::Bin/config/EduTeamsTest.cfg", \%config) or die("No config: $!");
#print Dumper \%config; exit 0;

my $driver = $config{'DB_DRIVER'};
my $db = "$FindBin::Bin/db/".$config{'DB_NAME'};
my $db_user = $config{'DB_USER'};
my $db_pass = $config{'DB_PASS'};
my $dsn = "DBI:$driver:dbname=$db";
my $dbh = DBI->connect($dsn, $db_user, $db_pass, { RaiseError => 1 })
    or die $DBI::errstr;



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
# ById is niet nodig, scheelt tijd en geheugen
#$sth_users->execute();
#my $usersById = $sth_users->fetchall_hashref('azureid');

# print Dumper $usersByUpn;
# exit 1;

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

    while (my ($upn,$docent) = each(%$docenten)){
        # Alleen door als er een UPN is en deze in de hash staat
        if ($upn && $usersByUpn->{$upn}){
            # Het docenten rooster bevat zowel de vak- als de clustergroepen
            my $groepen = $mag_session->getRooster($docent->{'stamnr'},"GetPersoneelGroepVakken"); # Rooster aanvraag voor een docent
            # Het is niet gezegd dat elke medewerker in Magister ook een docent is
            if ($groepen){
                foreach my $groep (keys %$groepen){
                    # Is het een groep van een aktieve locatie
                    if ($groep =~/^($config{'AKTIEVE_LOCATIES'}).+/){
                        # ROWID moet in usersByUpn staan, anders staat de docent niet in Azure
                        # Prefix groep met lesperiode uit conifg
                        my $groep_formatted = $config{'MAGISTER_LESPERIODE'}.'-'.$groep; # $groep niet aanpassen, dat is de index van de hash
                        # Groepen met een punt in de naam zijn clustergroepen
                        # Zonder punt zijn klassengroepen, hier moet nog "-vak" aan toegevoegd worden.
                        # anders zijn ze niet uniek.
                        my $type = "clustergroep"; # Uitgaan van clustergroep
                        if ( $groep !~ /\./ ){
                            #print Dumper $groepen->{$groep};
                            $type = "klasgroep"; # wijzigen indien van toepassing
                            $groep_formatted = $groep_formatted."-".$groepen->{$groep}->{'code'};
                        }
                        # ROWID ophalen voor de groep
                        my $teamROWID = getMagisterTeamROWID($groep_formatted,$type);
                        # Beide ROWIDs zijn nu bekend => roosterentry maken
                        #my $qry = "Insert Into magisterdocentenrooster (docid,teamid) values (?,?) ";
                        $sth_magisterdocentenrooster->execute($usersByUpn->{$upn}->{'rowid'},$teamROWID);
                        $logger->make_log("$FindBin::Bin/$FindBin::Script INFO Docent => $docent->{'naam'} => $groep_formatted");
                    }
                }
            }
        }else{
            $logger->make_log("$FindBin::Bin/$FindBin::Script ERROR Docent:$docent->{'naam'}:$upn:heeft een ongeldige UPN in Magister");
        }
    }
}

sub Leerlingen {
    my $leerlingen = $mag_session->getLeerlingen(); # $leerlingen is een HOH indexed op upn
    while (my ($upn,$leerling) = each(%$leerlingen)){
        # Alleen door als de lln in Azure staat
        # En als er ook daadwerkelijk een UPN is
        if ($upn && $usersByUpn->{$upn}){
            # Alleen lln behandelen van aktieve scholen
            if ($leerling->{'studie'} =~ /^($config{'AKTIEVE_LOCATIES'}).+/){
                #say "Leerling: ".$leerling->{'naam'}." stamnr: ".$stamnr;
                #print Dumper $leerling;
                
                # Voor leerlingen staan de cluster- en vakgroepen apart in Magister

                # say "Leerling clustergroepen";
                my $groepen = $mag_session->getRooster($leerling->{'stamnr'},"GetLeerlingGroepen"); # Rooster aanvraag voor een leerling
                #print Dumper $groepen;
                foreach my $groep (keys %$groepen){
                    #say "Groep is: $groep";
                    # Alleen doorgaan als de groep in $TeamsHoH staat en er dus een docent voor is
                    # Hievoor is de formatted groep naam nodig
                    # <lesperiode>-<groepnaam>
                    my $groep_formatted = $config{'MAGISTER_LESPERIODE'}.'-'.$groep; # $groep niet aanpassen, dat is de index van de hash
                    #say "Formatted: $groep_formatted";
                    if($TeamsHoH->{$groep_formatted}){
                        # $qry = "Insert Into magisterleerlingenrooster (leerlingid,teamid) values (?,?) ";
                        $sth_magisterleerlingenrooster->execute($usersByUpn->{$upn}->{'rowid'},$TeamsHoH->{$groep_formatted});
                        $logger->make_log("$FindBin::Bin/$FindBin::Script INFO Leerling => $leerling->{'naam'} =>  $groep_formatted");                    
                    }
                }

                # say "Leerling vakken";
                my $vakken = $mag_session->getRooster($leerling->{'stamnr'},"GetLeerlingVakken"); # Rooster aanvraag voor een leerling 
                #print Dumper $vakken;
                # Voor een leerling vakken krijg je alleen de vakcodes terug
                # Deze moet gecombineerd worden al <klas>-<vakcode>
                foreach  my $vakcode (keys %$vakken){
                    #say "Vakcode is: $vakcode";
                    # Alleen doorgaan als vak in $TeamsHoH staat en er dus een docent voor is
                    # Hievoor is de formatted vak naam nodig
                    # <lesperiode>-<klas>-<vakcode>
                    my $vaknaam_formatted = $config{'MAGISTER_LESPERIODE'}.'-'.$leerling->{'klas'}."-".$vakcode; # $vakcode niet aanpassen, dat is de index van de hash
                    #say "Formatted: $vaknaam_formatted";
                    if($TeamsHoH->{$vaknaam_formatted}){
                        # $qry = "Insert Into magisterleerlingenrooster (leerlingid,teamid) values (?,?) ";
                        $sth_magisterleerlingenrooster->execute($usersByUpn->{$upn}->{'rowid'},$TeamsHoH->{$vaknaam_formatted});
                        $logger->make_log("$FindBin::Bin/$FindBin::Script INFO Leerling => $leerling->{'naam'} =>  $vaknaam_formatted");                    
                    }
                }

            }
        }
    }
}


sub Jaarlagen {
    $logger->make_log("$FindBin::Bin/$FindBin::Script Jaarlagen maken gestart");                    
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
        print Dumper $teams;
        # doorloop de gevonden teams
        while (my ($naam, $team) = each(%{$teams})){
            #say "Leden ophalen uit $naam"; 
            # ROWID ophalen voor de jaarlaag, dit voegt hem zonodig toe aan de tabel
            my $jaarlaag_rowid = getMagisterTeamROWID($config{'MAGISTER_LESPERIODE'}.'-'.$jaarlaag_naam, 'jaarlaag');
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

Docenten();
Leerlingen();
Jaarlagen();

$sth_users->finish;
$sth_magisterteam->finish;
$sth_magisterdocentenrooster->finish;
$sth_magisterleerlingenrooster->finish;
$dbh->disconnect;
$logger->make_log("$FindBin::Bin/$FindBin::Script ended.");