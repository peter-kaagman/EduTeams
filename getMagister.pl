#! /usr/bin/env perl
#
# Dit script normaliseert de gedwonloade docentgegevens vanuit Magister.
# Ze worden toegevoegd aan de database indien voor de locatie teams gemaakt worden.
# 
use v5.11;
use strict;
use warnings;
#use Text::CSV qw( csv ); # CSV afhandeling in Magister.pm
use DBI;
use Data::Dumper;
use FindBin;
use Config::Simple;
use lib "$FindBin::Bin/lib";

use MsUser; # Om een UPN te vinden
use Magister; # Diverse magister functies
use Logger; # Om te loggen

my $logger = Logger->new(
    'filename' => "$FindBin::Bin/Log/EduTeams.log",
    'verbose' => 0
);
$logger->make_log("$FindBin::Bin/$FindBin::Script started.");

my %config;
Config::Simple->import_from("$FindBin::Bin/config/EduTeams.cfg", \%config) or die("No config: $!");
#print Dumper \%config; exit 0;

my $driver = $config{'DB_DRIVER'};
my $db = "$FindBin::Bin/db/".$config{'DB_NAME'};
my $db_user = $config{'DB_USER'};
my $db_pass = $config{'DB_PASS'};
my $dsn = "DBI:$driver:dbname=$db";
my $dbh = DBI->connect($dsn, $db_user, $db_pass, { RaiseError => 1 })
    or die $DBI::errstr;



# Prepare db shit, volgorde is van belang ivm truncatesd en foreign keys
#
# NB
# Zowel hier als in het Azure deel maak ik STHs om te zoeken naan docenten en leerlingen,
# ik vraag mij af of het niet efficienter is om een hash te maken waarin ik kan zoeken
#
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

# docent
$dbh->do('Delete From magisterdocent'); # Truncate the table
$qry = "Insert Into magisterdocent (stamnr, upn, naam, azureid) values (?,?,?,?) ";
my $sth_magisterdocent = $dbh->prepare($qry);
my $DocentenHoH; # ipv zoeken in de database

# leerling
$dbh->do('Delete From magisterleerling'); # Truncate the table
$qry = "Insert Into magisterleerling (stamnr, b_nummer, upn, naam) values (?,?,?,?) ";
my $sth_magisterleerling = $dbh->prepare($qry);
my $LeerlingenHoH; # ipv zoeken in de database

# Magister object om magister dingen mee te doen
my $mag_session= Magister->new(
    'user'          => $config{'MAGISTER_USER'},
    'secret'        => $config{'MAGISTER_SECRET'},
    'endpoint'      => $config{'MAGISTER_URL'},
    'lesperiode'    => $config{'MAGISTER_LESPERIODE'}

);
# Graph object om graph dingen mee te doen
my $user_object = MsUser->new(
    'app_id'         => $config{'APP_ID'},
    'app_secret'     => $config{'APP_PASS'},
    'tenant_id'      => $config{'TENANT_ID'},
    'login_endpoint' => $config{'LOGIN_ENDPOINT'},
    'graph_endpoint' => $config{'GRAPH_ENDPOINT'},        
);

# Functie om een ID te zoeken met een UPN.
# De inlogcode is alleen bruikbaar indien er nog een AD is
sub getAzureId {
    my $upn = shift;
    if ($user_object->_get_access_token){
        my $AzureId = $user_object->fetch_id_by_upn($upn);
        return $AzureId;
    }else{
        return "Fout bij ophalen AzureId: geen access token";
    }
}

# Maakt een entry voor de docent
# Geeft de ROWID terug
# Docent wordt pas aangemaakt indien er een aktieve groep gevonden is, de docent kan dus al bestaan
sub getMagisterDocentROWID {
    my $stamnr = shift;
    my $docent = shift;
    #say "Op zoek naar een ROWID voor $stamnr";
    if ($DocentenHoH->{$stamnr}){
        return $DocentenHoH->{$stamnr};
    }else{
        my $azureid = getAzureId(lc($docent->{'upn'}));
        if ($azureid ne 'onbekend'){
            # $qry = "Insert Into magisterdocent (stamnr, upn, naam, azureid) values (?,?,?,?) ";
            $sth_magisterdocent->execute($stamnr, ,$docent->{'upn'},$docent->{'naam'},$azureid);
            my $ROWID =  $dbh->last_insert_id("","","magisterdocent","ROWID");
            $DocentenHoH->{$stamnr} = $ROWID;
            return $ROWID; 
        }else{
            return 'onbekend';
        }
    }
}

# Maakt een entry voor de leerling
# Geeft de ROWID terug
# Leerling heeft verschillende groepen en komt dus meerdere keren voor
sub getMagisterLeerlingROWID {
    my $stamnr = shift;
    my $leerling = shift;
    if ($LeerlingenHoH->{$stamnr}){
        return $LeerlingenHoH->{$stamnr};
    }else{
        my $upn = $leerling->{'b_nummer'}.'@atlascollege.nl';
        #$qry = "Insert Into magisterleerling (stamnr, b_nummer, upn, naam) values (?,?,?,?) ";
        $sth_magisterleerling->execute($stamnr, lc($leerling->{'b_nummer'}),lc($upn),$leerling->{'naam'});
        my $ROWID =  $dbh->last_insert_id("","","magisterleerling","ROWID");
        $LeerlingenHoH->{$stamnr} = $ROWID;
        return $ROWID; 
    }
}

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
    my $docenten = $mag_session->getDocenten(); # $docenten is een HOH indexed op stamnr

    while (my ($stamnr,$docent) = each(%$docenten)){
        # Het docenten rooster bevat zowel de vak- als de clustergroepen
        my $groepen = $mag_session->getRooster($stamnr,"GetPersoneelGroepVakken"); # Rooster aanvraag voor een docent
        foreach my $groep (keys %$groepen){
            # Is het een groep van een aktieve locatie
            if ($groep =~/^($config{'AKTIEVE_LOCATIES'}).+/){
                # ROWID ophalen voor de docent
                # Hier pas docent aanmaken, alleen als hij een aktieve groep lesgeeft
                my $docentROWID = getMagisterDocentROWID($stamnr, $docent);
                # Niets maken als de ROWID onbekend is, dit duid op een ongeldige UPN in Magister
                if ($docentROWID ne 'onbekend'){
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
                    $sth_magisterdocentenrooster->execute($docentROWID,$teamROWID);
                    $logger->make_log("$FindBin::Bin/$FindBin::Script Docent => $docent->{'naam'} => $groep_formatted");
                }else{
                    $logger->make_log("$FindBin::Bin/$FindBin::Script ERROR Docent => $docent->{'naam'} heeft een ongeldige UPN in Magister");

                }
            }
        }
    }
}

sub Leerlingen {
    my $leerlingen = $mag_session->getLeerlingen(); # $leerlingen is een HOH indexed op stamnr
    while (my ($stamnr,$leerling) = each(%$leerlingen)){
        # Alleen lln behandelen van aktieve scholen
        if ($leerling->{'studie'} =~ /^($config{'AKTIEVE_LOCATIES'}).+/){
            #say "Leerling: ".$leerling->{'naam'}." stamnr: ".$stamnr;
            #print Dumper $leerling;
            
            # Voor leerlingen staan de cluster- en vakgroepen apart in Magister
            # say "Leerling clustergroepen";
            my $groepen = $mag_session->getRooster($stamnr,"GetLeerlingGroepen"); # Rooster aanvraag voor een leerling
            #print Dumper $groepen;
            foreach my $groep (keys %$groepen){
                #say "Groep is: $groep";
                # Alleen doorgaan als de groep in $TeamsHoH staat en er dus een docent voor is
                # Hievoor is de formatted groep naam nodig
                # <lesperiode>-<groepnaam>
                my $groep_formatted = $config{'MAGISTER_LESPERIODE'}.'-'.$groep; # $groep niet aanpassen, dat is de index van de hash
                #say "Formatted: $groep_formatted";
                if($TeamsHoH->{$groep_formatted}){
                    # Er is een ROWID voor het team, nu de ROWID voor de leerling ophalen
                    my $leerlingROWID = getMagisterLeerlingROWID($stamnr,$leerling);
                    # $qry = "Insert Into magisterleerlingenrooster (leerlingid,teamid) values (?,?) ";
                    $sth_magisterleerlingenrooster->execute($leerlingROWID,$TeamsHoH->{$groep_formatted});
                    $logger->make_log("$FindBin::Bin/$FindBin::Script Leerling => $leerling->{'naam'} =>  $groep_formatted");                    
                }
            }

            # say "Leerling vakken";
            my $vakken = $mag_session->getRooster($stamnr,"GetLeerlingVakken"); # Rooster aanvraag voor een leerling 
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
                    # Er is een ROWID voor het team, nu de ROWID voor de leerling ophalen
                    # Als de leerling nog niet bestond dan wordt hij hier pas gemaakt, als er een aktief vak is
                    my $leerlingROWID = getMagisterLeerlingROWID($stamnr,$leerling);
                    # $qry = "Insert Into magisterleerlingenrooster (leerlingid,teamid) values (?,?) ";
                    $sth_magisterleerlingenrooster->execute($leerlingROWID,$TeamsHoH->{$vaknaam_formatted});
                    $logger->make_log("$FindBin::Bin/$FindBin::Script Leerling => $leerling->{'naam'} =>  $vaknaam_formatted");                    
                }
            }

        }
    }
}

# Een jaarlaag wordt gebasseerd op geldige groepen in Magister.
# Dwz dat de groepen docenten en leerlingen moeten hebben.
# Van een groep zonder leerlingen worden de lln dus niet toegevoegd
my $json = read_file("$FindBin::Bin/config/".$config{'JAARLAGEN'}, { binmode => ':raw'});
my $jaarlagen = decode_json $json;
print Dumper $jaarlagen;

sub jaarLagen {
    $logger->make_log("$FindBin::Bin/$FindBin::Script Jaarlagen maken gestart");                    
    my $sth_docentenzoeken = $dbh->prepare("Select docentid From magisterdocentenrooster Where teamid = ?");      # docenten zoeken van een team
    my $sth_leerlingenzoeken = $dbh->prepare("Select leerlingid From magisterleerlingenrooster Where teamid = ?");# leerlingen zoeken van een team
    my $sth = $dbh->prepare('Select * From magisterteam Where naam Like ?');    # zoek een team op naam
    
    # De hash jaarlagen doorlopen
    while (my($search,$jaarlaag_naam) = each (%{$jaarlagen})){
        # Zoek de teams die aan het filter voldoen (lesperiode toevoegen)
        $sth->execute($config{'MAGISTER_LESPERIODE'}.'-'.$search);
        my $teams = $sth->fetchall_hashref('naam'); # gevonden teams ff in een hash zetten
        # doorloop de gevonden teams
        while (my ($naam, $team) = each(%{$teams})){ 
            # ROWID ophalen voor de jaarlaag, dit voegt hem zonodig toe aan de tabel
            my $jaarlaag_rowid = getMagisterTeamROWID($config{'MAGISTER_LESPERIODE'}.'-'.$jaarlaag_naam, 'jaarlaag');
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
    $sth_docentenzoeken->finish;
    $sth_leerlingenzoeken->finish;
}

&Docenten();
&Leerlingen();
&jaarLagen();

$sth_magisterdocent->finish;
$sth_magisterteam->finish;
$sth_magisterdocentenrooster->finish;
$sth_magisterleerling->finish;
#$dbh->disconnect;
$logger->make_log("$FindBin::Bin/$FindBin::Script ended.");