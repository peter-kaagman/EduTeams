#! /usr/bin/env perl
#
# Dit script maakt hashes van de Magister en Azure teams en vergelijkt deze tov elkaar
# 
use v5.11;
use strict;
use warnings;
use DBI;
use Data::Dumper;
#use Data::Printer;
use FindBin;
use Config::Simple;
use Time::Piece;
use Time::Seconds;
use JSON qw(decode_json encode_json);
use lib "$FindBin::Bin/lib";

use Logger; # Om te loggen
use MsGroups;
use MsGroup;


my $logger = Logger->new(
    'filename' => "$FindBin::Bin/Log/EduTeams.log",
    'verbose' => 1
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

# Handler om gemaakte groepen te kunnen vastleggen
my $sth_team_created = $dbh->prepare('Insert Into teamcreated (timestamp, naam, members, owners ) values (?,?,?,?)');

my ($Azure, $Magister, $LlnId, $ToDo); # Global hashes to store info

# Deze maak ik global omdat ik maar 1x de verbinding wil maken
my $groups_object = MsGroups->new(
	'app_id'        => $config{'APP_ID'},
	'app_secret'    => $config{'APP_PASS'},
	'tenant_id'     => $config{'TENANT_ID'},
	'login_endpoint'=> $config{'LOGIN_ENDPOINT'},
	'graph_endpoint'=> $config{'GRAPH_ENDPOINT'},
	#'filter'        => '$filter=startswith(mail,\'Section_\')',
    'select'        => '$select=id,displayName,description,mail',
);


sub createEduTeam {
    my $name = shift;
    my $description;
    # Jaarlagen krijgen een herkenbare description 
    if ($Magister->{$name}->{'type'} eq 'jaarlaag'){
        $description = $name."_Jaarlag";
    }else{
        $description = $name;
    }
    my $new_team = {
        'template@odata.bind' => 'https://graph.microsoft.com/v1.0/teamsTemplates(\'educationClass\')',
        "description" => "Section_".$description,
        "displayName" => "Section_".$name
    };
    # Team wordt gemaakt via de teams interface
    # het MOET 1 eigenaar hebben (ook niet meer dan 1)

    # Haal de eerste docent uit de hash
    my ($user_id) = keys %{$Magister->{$name}->{'docenten'}};
    # En verwijder hem uit de lijst zodat hij niet nogmaals toegevoegd wordt
    delete($Magister->{$name}->{docenten}->{$user_id});
    # Maak een member schema
    my $user = {
        '@odata.type'=> '#microsoft.graph.aadUserConversationMember',
        'user@odata.bind' => "https://graph.microsoft.com/v1.0/users(\'$user_id\')"
    };
    # Voeg de owner rol toe
    push(@{$user->{'roles'}}, 'owner');
    # Voeg het member schema toe aan het team schema
    push(@{$new_team->{'members'}}, $user);

    my $result = $groups_object->team_create($new_team);
    if ($result->is_success){
        # Er komt geen result object terug met ID
        # Ik wil echter wel een kwartier wachten voor ik verder iets doe met het team
        # toevoegen aan groupcreated dus zonder id.
        my $now = localtime->epoch;
    #     #say "TimeStamp: $now" ;
        # Gegevens in de database opnemen om gebruikers toevoegen 
        # naam, leden nog toevoegen aan de database, dan hoeft dat niet nog een keer opgezocht te wordne
        $sth_team_created->execute(
            $now,
            $name, 
            encode_json($Magister->{$name}->{'leerlingen'}),
            encode_json($Magister->{$name}->{'docenten'})
        );
        $logger->make_log("$FindBin::Bin/$FindBin::Script Class $name gemaakt,  naam is $name}");
    } else {
        #foutafhandeling
        if ($result->{'_rc'} eq '400'){ # bad request
            my $content = decode_json($result->{'_content'});
            $logger->make_log("$FindBin::Bin/$FindBin::Script ERROR met $name, Bad Request: $content->{'error'}->{'message'}");
        }else{
            $logger->make_log("$FindBin::Bin/$FindBin::Script ERROR Onbekende fout met $name, RC is $result->{'_rc'}");
        }
    }
}


# Azure hash
sub AzureHash{
    $logger->make_log("$FindBin::Bin/$FindBin::Script Azure hash maken.");

    my $qry = << "END_QRY";
    Select
        azureteam.*,
        azuredocent.azureid As 'docent_azureid',
        azuredocent.naam As 'docent_naam',
        azureleerling.upn As 'leerling_upn',
        azureleerling.azureid As 'leerling_azureid',
        azureleerling.naam As 'leerling_naam'
    From azureteam
    Left Join azuredocrooster       On azuredocrooster.azureteam_id = azureteam.ROWID
    Left Join azuredocent           On azuredocrooster.azuredocent_id = azuredocent.ROWID
    Left Join azureleerlingrooster   On azureleerlingrooster.azureteam_id = azureteam.ROWID
    Left Join azureleerling         On azureleerlingrooster.azureleerling_id = azureleerling.ROWID
END_QRY
    my $sth = $dbh->prepare($qry);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref()){
        $Azure->{$row->{'description'}}->{'id'} = $row->{'id'};
        $Azure->{$row->{'description'}}->{'displayName'} = $row->{'displayName'};
        if ($row->{'docent_naam'}){
            $Azure->{$row->{'description'}}->{'docenten'}->{$row->{'docent_azureid'}} = $row->{'docent_naam'};
        #}else{
        #    $logger->make_log("$FindBin::Bin/$FindBin::Script ". $row->{'description'}. " heeft geen docenten");
        }
        if ($row->{'leerling_naam'}){
            $Azure->{$row->{'description'}}->{'leerlingen'}->{$row->{'leerling_upn'}} = $row->{'leerling_naam'};
            # Leerling id in een hash stoppen met upn als index, scheelt een hoop requests
            $LlnId->{$row->{'leerling_upn'}} = $row->{'leerling_azureid'};
        #}else{
        #    $logger->make_log("$FindBin::Bin/$FindBin::Script ". $row->{'description'}. " heeft geen leerlingen");
        }
}
$sth->finish;
#print Dumper $Azure;
$logger->make_log("Aantal Azure teams: " . scalar keys %$Azure);
$logger->make_log("$FindBin::Bin/$FindBin::Script Azure hash gemaakt.");
}

# Magister hash
sub MagisterHash {
    $logger->make_log("$FindBin::Bin/$FindBin::Script Magister hash maken.");

    my $qry = << "END_QRY";
    Select
        magisterteam.*,
        magisterdocent.azureid As 'azureid',
        magisterdocent.naam As 'docent_naam',
        magisterleerling.upn As 'leerling_upn',
        magisterleerling.naam As 'leerling_naam'
    From magisterteam
    Left Join magisterdocentenrooster   On magisterdocentenrooster.teamid = magisterteam.ROWID
    Left Join magisterdocent            On magisterdocentenrooster.docentid = magisterdocent.ROWID
    Left Join magisterleerlingenrooster On magisterleerlingenrooster.teamid = magisterteam.ROWID
    Left Join magisterleerling          On magisterleerlingenrooster.leerlingid = magisterleerling.ROWID
END_QRY
    my $sth = $dbh->prepare($qry);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref()){
        $Magister->{$row->{'naam'}}->{'type'} = $row->{'type'};
        if ($row->{'docent_naam'}){
            $Magister->{$row->{'naam'}}->{'docenten'}->{$row->{'azureid'}} = $row->{'docent_naam'};
        #}else{
        #    $logger->make_log("$FindBin::Bin/$FindBin::Script ". $row->{'naam'}. " heeft geen docenten");
        }
        if ($row->{'leerling_naam'}){
            $Magister->{$row->{'naam'}}->{'leerlingen'}->{$row->{'leerling_upn'}} = $row->{'leerling_naam'};
        #}else{
        #    $logger->make_log("$FindBin::Bin/$FindBin::Script ". $row->{'naam'}. " heeft geen leerlingen");
        }
    }
    $sth->finish;
    #print Dumper $Magister;
    $logger->make_log("Aantal Magister teams: " . scalar keys %$Magister);
    $logger->make_log("$FindBin::Bin/$FindBin::Script Magister hash gemaakt.");
}


# Vergelijk Magister met Azure
sub MagisterAzure{
    # Mutaties vanuit Magister hebben invloed op de vergelijking vanuit Azure die hierop volgt.
    # het archiveren van teams en het toevoegen van leerlingen dus direct ook verwerken in de Azure hash.

    $logger->make_log("$FindBin::Bin/$FindBin::Script Magister vergelijken met Azure.");
    while (my ($magisternaam, $magisterteam) = each( %$Magister)){
        #say $naam;
        #print Dumper $magisterteam;

        # Een magister team moet leerlingen hebben
        # Een team heeft altijd tenminste 1 docent, anders staat hij niet in de db
        if ( ! $magisterteam->{'leerlingen'} ){
            # Dit team heeft geen leerlingen
            # Zou dus niet mogen bestaan in Azure
            if ($Azure->{$magisternaam}){
                # Geen leerlingen, maar er is wel een Azure team
                # Hier iets doen met Azure
                push (@{$ToDo->{'Magister'}->{'Archiveren'}}, $magisternaam);
                # Een team wat gearchiveerd moet worden hoeft niet meer beoordeeld te worden vanuit Azure
                delete($Azure->{$magisternaam});
            # }else{
            #     # Hier niets doen
            #     say "Team $magisternaam heeft geen leerlingen en bestaat niet in Azure";
            }
        }else{
            # Dit team heeft leerlingen
            # en zou dus moeten bestaan in Azure;
            if (! $Azure->{$magisternaam}){
                # Azure team bestaat niet
                # Hier iets doen met Azure
                push (@{$ToDo->{'Magister'}->{'MagisterMaken'}}, $magisternaam)
                # Team staat niet in de Azure hash, wordt dus van daar uit niet gecontroleerd. Zo laten.
            }else{
                # Azure bestaat 
                # Eigenaren en leden controleren
                # Eigenaren
                foreach my $magister_upn (keys %{$magisterteam->{'docenten'}}){
                    if (! $Azure->{$magisternaam}->{'docenten'}->{$magister_upn}){
                        push(@{$ToDo->{'Magister'}->{'MagisterDocentToevoegen'}->{$magisternaam}}, $magister_upn);
                        # Dit heeft impact op de controlle vanuit Azure, deze docent dus ook toevoegen aan de Azure hash
                        $Azure->{$magisternaam}->{'docenten'}->{$magister_upn} = 'toegevoegd door Magister vergelijking'; # heb de naam hier niet beschikbaar
                    }
                }
                # Leerlingen
                foreach my $magister_upn (keys %{$magisterteam->{'leerlingen'}}){
                    if (! $Azure->{$magisternaam}->{'leerlingen'}->{$magister_upn}){
                        push(@{$ToDo->{'Magister'}->{'MagisterLeerlingToevoegen'}->{$magisternaam}}, $magister_upn);
                        # Dit heeft impact op de controlle vanuit Azure, deze leerling dus ook toevoegen aan de Azure hash
                        $Azure->{$magisternaam}->{'leerlingen'}->{$magister_upn} = 'toegevoegd door Magister vergelijking'; # heb de naam hier niet beschikbaar
                    }
                }
            }
        }

    }
    $logger->make_log("$FindBin::Bin/$FindBin::Script Magister vergelijken klaar.");
}

# Vergelijk Azure met Magister
sub AzureMagister{
    #
    # Vanuit Azure gezien worden er alleen archiveringen en verwijderingen gedaan.
    # Magister is leidend. Tijdens de vergelijking vanuit Magister zijn de toevoegingen al gedaan.
    #
    $logger->make_log("$FindBin::Bin/$FindBin::Script Starten Azure vergelijking.");
    while (my ($azurenaam, $azureteam) = each( %$Azure)){
        # Is het een team zonder eigenaar of leerlingen?
        if (! $azureteam->{'docenten'} || ! $azureteam->{'leerlingen'}){
            #say "$azurenaam heeft geen eigenaar of leden";
            #print Dumper $azureteam;
            push (@{$ToDo->{'Azure'}->{'AzureArchiverenLeden'}}, $azurenaam)
        }else{
            # Het is een geldig team met eigenaar en leden
            # Is het ook aktief in Magister?
            if (!$Magister->{$azurenaam}){
                # Het team komt niet voor in Magister => archiveren
                push (@{$ToDo->{'Azure'}->{'AzureArchiverenNietInMagister'}}, $azurenaam)
            }else{
                # Geldig Azure team en staat ook in de Magister hash
                # Eigenaren en leden controleren dus. 
                # Toevoegen gebeurt al vanuit Magister, alleen verwijderen dus
                # Eigenaren
                foreach my $azure_id (keys %{$azureteam->{'docenten'}}){
                    if (! $Magister->{$azurenaam}->{'docenten'}->{$azure_id}){
                        push(@{$ToDo->{'Azure'}->{'AzureDocentVerwijderen'}->{$Azure->{$azurenaam}->{'id'}}}, $azure_id);
                    }
                }
                # Leerlingen
                print Dumper $azureteam->{'leerlingen'};
                foreach my $azure_upn (keys %{$azureteam->{'leerlingen'}}){
                    if (! $Magister->{$azurenaam}->{'leerlingen'}->{$azure_upn}){
                        say "LLn verwijderen uit $azurenaam => $azure_upn";
                        push(@{$ToDo->{'Azure'}->{'AzureLeerlingVerwijderen'}->{$Azure->{$azurenaam}->{'id'}}}, $azure_upn);
                    }
                }

            }
        }
    }
    $logger->make_log("$FindBin::Bin/$FindBin::Script Einde Azure vergelijking.");
}

AzureHash(); # <= maak een hash van wat we weten vanuit Azure
#print Dumper $Azure;
MagisterHash(); # <= maak een hash van wat we weten vanuit Magister
#print Dumper $Magister;
MagisterAzure(); # Vergelijkt vanuit Magsiter gezien, koppelt terug in $ToDo maar wijzigt ook de AzureHash
AzureMagister(); # Vergelijkt vanuit Azure gezien, koppelt terug in $ToDo
# We hebben nu een hash met wijzigingen die uitgevoerd moeten worden
say "ToDo";
print Dumper $ToDo if $ToDo;
#exit 1;
say "Azure";
print Dumper $Azure;
say "Magister";
print Dumper $Magister;

# Magister
    # Archiveren
    # MagisterMaken <= Een team staat in Magister maar niet in Azure
foreach my $NewClass (@{$ToDo->{'Magister'}->{'MagisterMaken'}}){
    createEduTeam($NewClass);
}
    # MagisterDocentToevoegen
    # MagisterLeerlingToevoegen

# Azure
    # AzureArchiverenNietInMagister <= Een team staat wel in Azure maar niet (meer) in Magister
foreach my $Team2Archive (@{$ToDo->{'Azure'}->{'AzureArchiverenNietInMagister'}}){
    # Om te archiveren is alleen het team id nodig
    $groups_object->team_archive(
        $Azure->{$Team2Archive}->{'id'},
        $Team2Archive
    );
}
    # AzureLeerlingVerwijderen
while (my($id,$array) = each(%{$ToDo->{'Azure'}->{'AzureLeerlingVerwijderen'}})){
    say "Lln verwijderen uit: $id";
    my $group_object = MsGroup->new(
        'app_id'        => $config{'APP_ID'},
        'app_secret'    => $config{'APP_PASS'},
        'tenant_id'     => $config{'TENANT_ID'},
        'access_token'  => $groups_object->_get_access_token, #reuse token
        'login_endpoint'=> $config{'LOGIN_ENDPOINT'},
        'graph_endpoint'=> $config{'GRAPH_ENDPOINT'},
        'select'        => '$select=id,displayName,userPrincipalName',
        'id'            => $id,
    );
    foreach my $lln_upn  (@{$array}){
        say "LLN id $lln_upn => $LlnId->{$lln_upn}";
        $group_object->team_removeMember($LlnId->{$lln_upn})
    }
}  
    # AzureDocentVerwijderen
while (my($id,$array) = each(%{$ToDo->{'Azure'}->{'AzureDocentVerwijderen'}})){
    say "Docent verwijderen uit: $id";
    my $group_object = MsGroup->new(
        'app_id'        => $config{'APP_ID'},
        'app_secret'    => $config{'APP_PASS'},
        'tenant_id'     => $config{'TENANT_ID'},
        'login_endpoint'=> $config{'LOGIN_ENDPOINT'},
        'graph_endpoint'=> $config{'GRAPH_ENDPOINT'},
        'select'        => '$select=id,displayName,userPrincipalName',
        'id'            => $id,
    );
    foreach my $docent_id  (@{$array}){
        $group_object->team_removeMember($docent_id)
    }
}  


$logger->make_log("$FindBin::Bin/$FindBin::Script Beeindigd.");

