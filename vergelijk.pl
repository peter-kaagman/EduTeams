#! /usr/bin/env perl
#
# Dit script maakt hashes van de Magister en Azure teams en vergelijkt deze tov elkaar
# 
use v5.11;
use strict;
use warnings;
use utf8;
use DBI;
use Data::Dumper;
#use Data::Printer;
use FindBin;
use Config::Simple;
use Time::Piece;
use File::Path qw(make_path);
#use Time::Seconds;
use Parallel::ForkManager;
use JSON qw(decode_json encode_json);
use lib "$FindBin::Bin/../msgraph-perl/lib";
use lib "$FindBin::Bin/lib";

use Shared;

use Logger; # Om te loggen
use MsGroups;
use MsGroup;

binmode(STDOUT, ":utf8");

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



# Handler om gemaakte groepen te kunnen vastleggen
my $sth_class_created = $dbh->prepare('Insert Into teamcreated (timestamp, id, naam, members ) values (?,?,?,?)');

# Users
# Users dient als zoek hash 
my $sth_users = $dbh->prepare("Select azureid,upn,ROWID,naam From users");
$sth_users->execute();
my $usersById = $sth_users->fetchall_hashref('azureid');

my ($Azure, $Magister,$ToDo); # Global hashes to store info

# Deze maak ik global omdat ik maar 1x de verbinding wil maken
my $groups_object = MsGroups->new(
	'app_id'        => $config{'APP_ID'},
	'app_secret'    => $config{'APP_PASS'},
	'tenant_id'     => $config{'TENANT_ID'},
	'login_endpoint'=> $config{'LOGIN_ENDPOINT'},
	'graph_endpoint'=> $config{'GRAPH_ENDPOINT'},
	#'filter'        => '$filter=startswith(mail,\'EduTeam_\')',
    'select'        => '$select=id,displayName,description,mail',
);

# Azure hash
sub AzureHash{
    $logger->make_log("$FindBin::Script Azure hash maken.");

    # Leerlingen en docenten in één users database levert hier een uitdaging op
    # ik heb geen idee hoe ik dat in één query kan uitvragen, in twee keer dus maar
    # eerst docenten
    #
    # Door een Left Join te gebruiken worden ook teams zonder docenten
    # gevonden. Dit is voor de Azure hash geen probleem. Die teams bestaan nu
    # eenmaal, ook al zouden ze niet mogen bestaan.
    my $qry = << "    END_QRY";
    Select
        azureteam.*,
        users.azureid As 'docent_azureid',
        users.naam As 'docent_naam'
    From azureteam
    Left Join azuredocrooster       On azuredocrooster.azureteam_id = azureteam.ROWID
    Left Join users           On azuredocrooster.azuredocent_id = users.ROWID
    END_QRY

    my $sth = $dbh->prepare($qry);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref()){
        $Azure->{$row->{'secureName'}}->{'id'} = $row->{'id'};
        $Azure->{$row->{'secureName'}}->{'displayName'} = $row->{'displayName'};
        # Left Join kan resulteren in een team zonder docenten
        # dat mag voor de Azure hash, maar dan ik de leerling dus
        # niet aan de hash toevoegen
        if ($row->{'docent_azureid'}){
            $Azure->{$row->{'secureName'}}->{'docenten'}->{$row->{'docent_azureid'}} = $row->{'docent_naam'};
        }
    }
    $sth->finish;
    # Door een Left Join te gebruiken worden ook teams zonder docenten
    # gevonden. Dit is voor de Azure hash geen probleem. Die teams bestaan nu
    # eenmaal, ook al zouden ze niet mogen bestaan.
    $qry = << "    END_QRY";
    Select
        azureteam.*,
        users.azureid As 'leerling_azureid',
        users.naam As 'leerling_naam'
    From azureteam
    Left Join azureleerlingrooster   On azureleerlingrooster.azureteam_id = azureteam.ROWID
    Left Join users         On azureleerlingrooster.azureleerling_id = users.ROWID
    END_QRY

    $sth = $dbh->prepare($qry);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref()){
        $Azure->{$row->{'secureName'}}->{'id'} = $row->{'id'};
        $Azure->{$row->{'secureName'}}->{'displayName'} = $row->{'displayName'};
        # Left Join kan resulteren in een team zonder leerlingen
        # dat mag voor de Azure hash, maar dan ik de leerling dus
        # niet aan de hash toevoegen
        if ($row->{'leerling_azureid'}){
            $Azure->{$row->{'secureName'}}->{'leerlingen'}->{$row->{'leerling_azureid'}} = $row->{'leerling_naam'};
        }
    }
    $sth->finish;
    #print Dumper $Azure;
    $logger->make_log("$FindBin::Script Aantal Azure teams: " . scalar keys %$Azure);
    $logger->make_log("$FindBin::Script Azure hash gemaakt.");
}

# Magister hash
sub MagisterHash {
    $logger->make_log("$FindBin::Script Magister hash maken.");

    # Leerlingen en docenten in één users database levert hier een uitdaging op
    # ik heb geen idee hoe ik dat in één query kan uitvragen, in twee keer dus maar
    # eerst docenten
    #27 Teams zonder docenten mogen niet in de hash staan
    # Oorspronkelijk gebruikte de query een left join, die selecteerd ook lege teams 
    my $qry = << "    END_QRY";
    Select
        magisterteam.*,
        users.azureid As 'azureid',
        users.naam As 'docent_naam'
    From magisterteam
    Join magisterdocentenrooster   On magisterdocentenrooster.teamid = magisterteam.ROWID
    Join users                     On magisterdocentenrooster.docentid = users.ROWID
    END_QRY
    my $sth = $dbh->prepare($qry);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref()){
        $Magister->{$row->{'naam'}}->{'type'} = $row->{'type'};
        $Magister->{$row->{'naam'}}->{'heeft_docent'} = 1;
        $Magister->{$row->{'naam'}}->{'docenten'}->{$row->{'azureid'}} = 'docent';
    }
    $sth->finish;
    # dan leerlingen
    # controleren of er wel een docent is
    #27 Teams zonder leerlingen mogen niet in de hash staan
    # Oorspronkelijk gebruikte de query een left join, die selecteerd ook lege teams 
        $qry = << "    END_QRY";
    Select
        magisterteam.*,
        users.azureid As 'azureid',
        users.naam As 'leerling_naam'
    From magisterteam
    Join magisterleerlingenrooster On magisterleerlingenrooster.teamid = magisterteam.ROWID
    Join users                     On magisterleerlingenrooster.leerlingid = users.ROWID
    END_QRY
    $sth = $dbh->prepare($qry);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref()){
        if ($Magister->{$row->{'naam'}}->{'heeft_docent'}){
                $Magister->{$row->{'naam'}}->{'heeft_leerling'} = 1;
                $Magister->{$row->{'naam'}}->{'leerlingen'}->{$row->{'azureid'}} = 'leerling';
        }
    }
    $sth->finish;
    #print Dumper $Magister;
    $logger->make_log("$FindBin::Script Aantal Magister teams: " . scalar keys %$Magister);
    $logger->make_log("$FindBin::Script Magister hash gemaakt.");
}

# Vergelijk Magister met Azure
sub MagisterAzure{
    # Mutaties vanuit Magister hebben invloed op de vergelijking vanuit Azure die hierop volgt.
    # het archiveren van teams en het toevoegen van leerlingen dus direct ook verwerken in de Azure hash.
    $logger->make_log("$FindBin::Script INFO Magister vergelijken met Azure.");
    while (my ($magisternaam, $magisterteam) = each( %$Magister)){
        # Een magister team moet leerlingen hebben
        # Een team heeft altijd tenminste 1 docent, anders staat hij niet in de db
        if ( ! $magisterteam->{'heeft_leerling'} ){ # ToDo:Testen
            # Dit team heeft geen leerlingen
            # Zou dus niet mogen bestaan in Azure
            if ($Azure->{$magisternaam}){
                # getest 20/7/24 => werkt
                # Geen leerlingen, maar er is wel een Azure team
                # Het team dus archiveren
                # Om te archiveren is zowel het ID als de naam noodzakelijk, geen van beide staat nog in de Azure hash straks
                my $team->{'id'} = $Azure->{$magisternaam}->{'id'};
                $team->{'naam'} = $magisternaam;
                $team->{'bron'} = 'MagisterAzure geen leerlingen in team';
                push (@{$ToDo->{'TeamsArchiveren'}}, $team );
                # Een team wat gearchiveerd moet worden hoeft niet meer beoordeeld te worden vanuit Azure
                delete($Azure->{$magisternaam});
            }else{
            #     # Hier niets doen
                # $logger->make_log("$FindBin::Script DEBUG Team $magisternaam heeft geen leerlingen en bestaat niet in Azure.");
            }
        }else{
            # Dit team heeft leerlingen
            # en zou dus moeten bestaan in Azure;
            if (! $Azure->{$magisternaam}){
                # getest 20/7/24 => werkt
                # Azure team bestaat niet
                # Hier iets doen met Azure
                push (@{$ToDo->{'TeamsMaken'}}, $magisternaam)
                # Team staat niet in de Azure hash, wordt dus van daar uit niet gecontroleerd. Zo laten.
            }else{
                # Azure bestaat 
                # Eigenaren en leden controleren
                # Eigenaren
                foreach my $magister_azureid (keys %{$magisterteam->{'docenten'}}){
                    if (! $Azure->{$magisternaam}->{'docenten'}->{$magister_azureid}){
                        push(@{$ToDo->{'MembersToevoegen'}->{$Azure->{$magisternaam}->{'id'}}->{'docenten'}}, $magister_azureid);
                        # Dit heeft impact op de controlle vanuit Azure, deze docent dus ook toevoegen aan de Azure hash
                        $Azure->{$magisternaam}->{'docenten'}->{$magister_azureid} = 'toegevoegd door Magister vergelijking'; # heb de naam hier niet beschikbaar
                    }
                }
                # Leerlingen
                foreach my $magister_id (keys %{$magisterteam->{'leerlingen'}}){
                    if (! $Azure->{$magisternaam}->{'leerlingen'}->{$magister_id}){
                        push(@{$ToDo->{'MembersToevoegen'}->{$Azure->{$magisternaam}->{'id'}}->{'leerlingen'}}, $magister_id);
                        # Dit heeft impact op de controlle vanuit Azure, deze leerling dus ook toevoegen aan de Azure hash
                        $Azure->{$magisternaam}->{'leerlingen'}->{$magister_id} = 'toegevoegd door Magister vergelijking'; # heb de naam hier niet beschikbaar
                    }
                }
            }
        }
    }
    $logger->make_log("$FindBin::Script INFO Magister vergelijken klaar.");
}

# Vergelijk Azure met Magister
sub AzureMagister{
    #
    # Vanuit Azure gezien worden er alleen archiveringen en verwijderingen gedaan.
    # Magister is leidend. Tijdens de vergelijking vanuit Magister zijn de toevoegingen al gedaan.
    #
    $logger->make_log("$FindBin::Script Starten Azure vergelijking.");
    while (my ($azurenaam, $azureteam) = each( %$Azure)){
        # Is het een team zonder eigenaar of leerlingen?
        if (! $azureteam->{'docenten'} || ! $azureteam->{'leerlingen'}){
            my $team->{'id'} = $Azure->{$azurenaam}->{'id'};
            $team->{'naam'} = $azurenaam;
            $team->{'bron'} = 'AzureMagister geen docent of leerlingen';
            push (@{$ToDo->{'TeamsArchiveren'}}, $team );
        }else{
            # Het is een geldig team met eigenaar en leden
            # Is het ook aktief in Magister?
            if (!$Magister->{$azurenaam}){
                # Het team komt niet voor in Magister => archiveren
                my $team->{'id'} = $Azure->{$azurenaam}->{'id'};
                $team->{'naam'} = $azurenaam;
                $team->{'bron'} = 'AzureMagister niet in magister';
                push (@{$ToDo->{'TeamsArchiveren'}}, $team );
            }else{
                # Geldig Azure team en staat ook in de Magister hash
                # Eigenaren en leden controleren dus. 
                # Toevoegen gebeurt al vanuit Magister, alleen verwijderen dus

                # Eigenaren
                # Bespreking 7 nov 2024 => Docenten niet meer verwijderen
                # foreach my $azure_id (keys %{$azureteam->{'docenten'}}){
                #     #20 Check toegevoegd om docenten niet uit een Jaarlaag team te verwijderen
                #     if (
                #             (! $Magister->{$azurenaam}->{'docenten'}->{$azure_id} ) &&
                #             ( $azurenaam !~ /^.+Jaarlaag$/i)
                #         ){
                #         push(@{$ToDo->{'MembersVerwijderen'}->{ $Azure->{$azurenaam}->{'id'} }->{'docenten'} }, $usersById->{$azure_id}->{'azureid'});
                #     }
                # }
                # Leerlingen
                foreach my $azure_id (keys %{$azureteam->{'leerlingen'}}){
                    if (! $Magister->{$azurenaam}->{'leerlingen'}->{$azure_id}){
                        # Member id opzoeken
                        # $sth_memberid->execute($Azure->{$azurenaam}->{'id'}, $azure_id);
                        # my $row = $sth_memberid->fetchrow_hashref;
                        push(@{$ToDo->{'MembersVerwijderen'}->{$Azure->{$azurenaam}->{'id'} }->{'leerlingen'} }, $usersById->{$azure_id}->{'azureid'});
                    }
                }
            }
        }
    }
    $logger->make_log("$FindBin::Script Einde Azure vergelijking.");
}

sub end_script {
    my $exit_code = shift;
    unlink "$FindBin::Bin/Run/$config{'PID_FILE'}" unless $exit_code;
    $logger->make_log("$FindBin::Script Beeindigd met exitcode $exit_code.");
    exit $exit_code;
}

sub do_dryrun {
    # Bestaat de Dump directory?
    if (! (-d "$FindBin::Bin/$config{'DUMP_DIR'}")){
        eval {make_path("$FindBin::Bin/$config{'DUMP_DIR'}")};
        if ($@){
            $logger->make_log("$FindBin::Script Kan de dump map $FindBin::Bin/$config{'DUMP_DIR'} niet maken");
            end_script(2);
        }
    }
    my $now = localtime->datetime;
    # Users
    if (open FH, '>:encoding(UTF-8)', "$FindBin::Bin/$config{'DUMP_DIR'}/$now-users.json"){
        print FH JSON->new->utf8->pretty->encode($usersById);
        close FH;
    }else{
        say $!;
    }
    # Magister
    if (open FH, '>:encoding(UTF-8)', "$FindBin::Bin/$config{'DUMP_DIR'}/$now-magister.json"){
        print FH JSON->new->utf8->pretty->encode($Magister);
        close FH;
    }else{
        say $!;
    }
    # Azure
    if (open FH, '>:encoding(UTF-8)', "$FindBin::Bin/$config{'DUMP_DIR'}/$now-azure.json"){
        print FH JSON->new->utf8->pretty->encode($Azure);
        close FH;
    }else{
        say $!;
    }
    # ToDo
    # Create an augmented ToDo for debugging purposes
    my $sth_teams = $dbh->prepare("Select id,secureName From azureteam");
    $sth_teams->execute();
    my $teamsById = $sth_teams->fetchall_hashref('id');
    $sth_teams->finish();
    my $ToDo_augmented;
    while (my ($action, $action_content) = each %{$ToDo}){
        if ($action =~ /^Members.*/){
            while (my($teamid,$team_content) = each %{$action_content}){
                while (my($type, $type_content) = each %{$team_content}){
                    # $type content is een array
                    foreach my $userid (@{$type_content}){
                        #say "$action $teamid $teamsById->{$teamid}->{'secureName'}  $type $userid $usersById->{$userid}->{'naam'}";
                        push @{ $ToDo_augmented->{$action}->{ "$teamid=>$teamsById->{$teamid}->{'secureName'}" }->{$type} }, "$userid=>$usersById->{$userid}->{'naam'}";
                    }
                }
            }
        }else{
            # Gewoon toevoegen
            $ToDo_augmented->{$action} = $action_content;
        }
    }    

    if (open FH, '>:encoding(UTF-8)', "$FindBin::Bin/$config{'DUMP_DIR'}/$now-todo.json"){
        print FH JSON->new->utf8->pretty->encode($ToDo_augmented);
        close FH;
    }else{
        say $!;
    }
}

sub sanityCheck {
    my $fail = 0;
    # Heeft Magister data?
    if (! $Magister){
        $fail = 1;
        $logger->make_log("$FindBin::Script WARNING Magister hash heeft geen data, dit is uitermate verdacht.");
    }
    # Max new team
    if ($ToDo->{'TeamsMaken'}){
        if ( (scalar @{$ToDo->{'TeamsMaken'}} >= $config{'MAX_NEW_TEAMS'})){
            $fail = 1;
            $logger->make_log("$FindBin::Script WARNING ". @{$ToDo->{'TeamsMaken'}}." nieuwe teams, de grens is ". $config{MAX_NEW_TEAMS});
        }
    }

    # Max team archiveren
    if ($ToDo->{'TeamsArchiveren'}){
        if (scalar  @{$ToDo->{'TeamsArchiveren'}} > $config{'MAX_TEAMS_DELETED'}){
            $fail = 1 ;
            $logger->make_log("$FindBin::Script WARNING ". @{$ToDo->{'TeamsArchiveren'}}." teams te archiveren, de grens is ". $config{MAX_TEAMS_DELETED});
        }
    }

    # Max members verwijderen 
    if ($ToDo->{'MembersVerwijderen'}){
        my $total;
        while (my ($team, $groep) = each %{$ToDo->{'MembersVerwijderen'}} ){
            $total += scalar @{$groep->{'leerlingen'}} if ($groep->{'leerlingen'});
            $total += scalar @{$groep->{'docenten'}} if ($groep->{'docenten'});
        }
        if ($total > $config{'MAX_USER_DELETED'}){
            $fail = 1 ;
            $logger->make_log("$FindBin::Script WARNING $total gebruikers te verwijderen , de grens is ". $config{'MAX_USER_DELETED'});
        }
    }

    # Max members toevoegen 
    if ($ToDo->{'MembersToevoegen'}){
        my $total;
        while (my ($team, $groep) = each %{$ToDo->{'MembersToevoegen'}} ){
            $total += scalar @{$groep->{'leerlingen'}} if ($groep->{'leerlingen'});
            $total += scalar @{$groep->{'docenten'}} if ($groep->{'docenten'});
        }
        if ($total > $config{'MAX_NEW_USER'}){
            $fail = 1 ;
            $logger->make_log("$FindBin::Script WARNING $total gebruikers toe te voegen , de grens is ". $config{'MAX_NEW_USER'});
        }
    }
    # Uitvoering stoppen indien $fail gezet is
    end_script(3) if $fail;
}
#
# End of functions
#


#
# Script entry point
#

# Gegeven verzamelen
AzureHash(); # <= maak een hash van wat we weten vanuit Azure
MagisterHash(); # <= maak een hash van wat we weten vanuit Magister

#Vergelijkingen => ToDo hash maken
MagisterAzure(); # Vergelijkt vanuit Magsiter gezien, koppelt terug in $ToDo maar wijzigt ook de AzureHash
AzureMagister(); # Vergelijkt vanuit Azure gezien, koppelt terug in $ToDo


# We hebben nu een hash met wijzigingen die uitgevoerd moeten worden
# say "ToDo";
# if ($ToDo){
#     print Dumper $ToDo;
#  }else{
#     say "niets te doen";
#  }

# Dump alle data indien dit een dry run is
if ( ($config{'DUMP'}) || ($config{'DRY_RUN'}) ){
    $logger->make_log("$FindBin::Script INFO Dump maken");
    do_dryrun();
    # Beeindig het script 
    end_script(0) if $config{'DRY_RUN'}; # beeindig als het een dry run is
}

# Als laatste een sanity check voor we echt gaan muteren
sanityCheck();



#
# Vanaf hier gaan we mutaties uitvoeren
#
if ( $ToDo->{'TeamsMaken'} ){
    $logger->make_log("$FindBin::Script INFO Teams maken");
    # Een team bestaat in Magister maar niet in Azure => aanmaken of deactiveren #8
    my $pm = Parallel::ForkManager->new($config{'AZURE_THREADS'}, "$FindBin::Bin/".$config{'CACHE_DIR'}."/");

    # Callback
    $pm->run_on_finish( sub{
        my ($pid,$exit_code,$ident,$exit,$core_dump,$result) = @_;
        if ($exit_code eq 1){
            # say "Exit code was 1";
            # print Dumper $result;
            $logger->make_log("$FindBin::Script INFO Class $ident gedearchiveert.");
        }elsif($exit_code eq 2){
            # say "Creating team $ident";
            if ($result->is_success){
                # Members staan op 2 plaatsen in de Magister hash: leerlingen en docenten
                # Voor teamcreated moeten ze in één hash staan
                my $members = {
                    %{$Magister->{$ident}->{'leerlingen'}},
                    %{$Magister->{$ident}->{'docenten'}}
                };
                my $created_class = decode_json($result->decoded_content);
                my $now = localtime->epoch;
                # Insert Into teamcreated (timestamp, id, naam, members ) values (?,?,?,?)')
                # say "inserting teamcreated";
                $sth_class_created->execute(
                    localtime->epoch,
                    $created_class->{'id'},
                    $result->{'payload'}->{'mailNickname'},
                    encode_json $members
                    #encode_json($Magister->{$ident}->{'members'})
                );
                $logger->make_log("$FindBin::Script INFO Class $ident gemaakt.");
            } else {
                #foutafhandeling
                if ($result->{'_rc'} eq '400'){ # bad request
                    my $content = decode_json($result->{'_content'});
                    $logger->make_log("$FindBin::Script ERROR met $ident, Bad Request: $content->{'error'}->{'message'}");
                }else{
                    $logger->make_log("$FindBin::Script ERROR Onbekende fout met $ident, RC is $result->{'_rc'}");
                    print Dumper $result; exit 1;
                }
            }
        }else{
            $logger->make_log("$FindBin::Script ERROR Callback NewClass onbekende return_code");
        }
    });

    CREATE_TEAM:
    foreach my $NewClass (@{$ToDo->{'TeamsMaken'}}){
        my ($return_code, $result);

        # Als een team eerder gearchiveerd is om wat voor reden dan ook
        # is zijn mailNickname prefixed met "Archived_" zodat hij niet in de
        # lijst met aktieve teams komt. Controleren of dit het geval is
        my $pid = $pm->start($NewClass) and next CREATE_TEAM; # FORK
        my $payload = {
            "description" => $NewClass,
            "displayName" => $NewClass,
            "mailNickname" => "EduTeam_".$NewClass,
        };
        my $isArchived = $groups_object->team_is_archived('Archived_Eduteam_'.$NewClass);
        if($isArchived){
            # say "id is $isArchived, de-archiveren dus";
            my $result = $groups_object->team_dearchive($isArchived, $payload);
            $result->{'payload'} = $payload;
            $return_code = 1;
        }else{
            # say "$NewClass aanmaken dus";
            # Niet gevonden hoe ik een eigenaar toevoeg aan een class
            # members/owners later we dus volledig over aan createTeam.pl
            $result = $groups_object->class_create($payload);
            $result->{'payload'} = $payload;
            $return_code = 2;
        }
        $pm->finish($return_code,$result);
    }
    $pm->wait_all_children;
}

if ($ToDo->{'TeamsArchiveren'}){
    $logger->make_log("$FindBin::Script INFO Archiveren");
    # Een team moet gearchiveert worden
    # - Staat niet in Magister maar wel in Azure
    # - Heeft geen docenten
    # - Heeft geen leerlingen
    foreach my $team (@{$ToDo->{'TeamsArchiveren'}}){
        # Om te archiveren is alleen het team id nodig
        my $result = $groups_object->team_archive($team,'EduTeam');
        if ($result->is_success){
            $logger->make_log("$FindBin::Script INFO Team $team->{'naam'} is gearchiveert");
        }else{
            $logger->make_log("$FindBin::Script WARNING Team $team is niet gearchiveert");
        }
    }
}

# ALTIJD eerst toevoegen en dan pas verwjderen uit Azure, anders kun je een team zonder eigenaar krijgen
if ($ToDo->{'MembersToevoegen'}){
    $logger->make_log("$FindBin::Script INFO Leden toevoegen");
    while ( my( $teamid, $team ) = each(%{$ToDo->{'MembersToevoegen'}}) ){
        #print Dumper 
        my $group_object = MsGroup->new(
            'app_id'        => $config{'APP_ID'},
            'app_secret'    => $config{'APP_PASS'},
            'tenant_id'     => $config{'TENANT_ID'},
            'access_token'  => $groups_object->_get_access_token, #reuse token
            'token_expires' => $groups_object->_get_token_expires,
            'login_endpoint'=> $config{'LOGIN_ENDPOINT'},
            'graph_endpoint'=> $config{'GRAPH_ENDPOINT'},
            'id'            => $teamid,
        );
        # Leerlingen en docenten samenvoegen voor efficientie
        my $members;
        foreach my $member (@{$team->{'leerlingen'}}){
            $members->{$member} = 'leerling';
        }
        foreach my $member (@{$team->{'docenten'}}){
            $members->{$member} = 'docent';
        }
        #print Dumper $members;
        my $pm = Parallel::ForkManager->new($config{'AZURE_THREADS'}, "$FindBin::Bin/".$config{'CACHE_DIR'}."/");
        # Callback
        $pm->run_on_finish( sub{
            my ($pid,$exit_code,$ident,$exit,$core_dump,$result) = @_;
            if (! $result->is_success){
                if($result->{'_rc'} eq 400){
                    $logger->make_log("$FindBin::Script Info $result->{'member_id'} met rol $result->{'member_role'} was al lid van $ident");
                }else{
                    # say $result->{'_rc'};
                    # say "Onbekende fout";
                    $logger->make_log("$FindBin::Script ERROR $result->{'member_id'} met rol $result->{'member_role'} is niet toegevoegd aan $ident");
                    $logger->make_log("$FindBin::Script ERROR De fout was ".$result->decoded_content);
                }
            }else{
                    $logger->make_log("$FindBin::Script INFO $result->{'member_id'} met rol $result->{'member_role'} is toegevoegd aan $ident");
            }
        });

        MEMBERS:
        while (my($id,$role) = each %{$members}){
            my $pid = $pm->start($teamid) and next MEMBERS; # FORK
            # say "$id toevoegen als $role";
            my $result;
            if ($role eq 'docent'){
                $result = $group_object->group_add_member($id, 1);
            }else{
                $result = $group_object->group_add_member($id, 0);
            }
            $result->{'member_id'} = $id;
            $result->{'member_role'} = $role;

            $pm->finish(42,$result); # exit child
        }
        $pm->wait_all_children;
    }
}

if ($ToDo->{'MembersVerwijderen'}){
    # Een docent/lln staat bij een team in Azure maar niet in Magister => docent/lln verwijderen #10
    $logger->make_log("$FindBin::Script INFO Leden verwijderen");
    while ( my( $teamid, $team ) = each(%{$ToDo->{'MembersVerwijderen'}}) ){
        # say "Verwijderen uit $teamid";
        my $group_object = MsGroup->new(
            'app_id'        => $config{'APP_ID'},
            'app_secret'    => $config{'APP_PASS'},
            'tenant_id'     => $config{'TENANT_ID'},
            'access_token'  => $groups_object->_get_access_token, #reuse token
            'token_expires' => $groups_object->_get_token_expires,
            'login_endpoint'=> $config{'LOGIN_ENDPOINT'},
            'graph_endpoint'=> $config{'GRAPH_ENDPOINT'},
            'select'        => '$select=id,displayName,userPrincipalName',
            'id'            => $teamid,
        );
        # Verwijderen via de group => owners moeten dus ook als member verwijderd worden
        # Dit zijn separate methodes in $group_object
        # Push de owner in de member array
        push @{$team->{'leerlingen'}}, @{$team->{'docenten'}} if ($team->{'docenten'});
        # ForkManager opzetten
        my $pm = Parallel::ForkManager->new($config{'AZURE_THREADS'}, "$FindBin::Bin/".$config{'CACHE_DIR'}."/");
        # Callback
        $pm->run_on_finish( sub{
            my ($pid,$exit_code,$ident,$exit,$core_dump,$result) = @_;
            if (! $result->is_success){
                if ($result->{'_rc'} eq 404){
                    $logger->make_log("$FindBin::Script ERROR Gebruiker $ident was geen lid van $teamid");
                    #$logger->make_log("$FindBin::Script ERROR De fout was ".$result->decoded_content);
                }else{
                    $logger->make_log("$FindBin::Script ERROR Onbekende fout met gebruiker $ident group $teamid");
                    $logger->make_log("$FindBin::Script ERROR De fout was ".$result->decoded_content);
                }
            }else{
                    $logger->make_log("$FindBin::Script INFO Gebruiker $ident met rol $result->{'type'} is verwijderd uit $teamid");
            }
        });
        # Starten met members
        REMOVE_MEMBERS:
        foreach my $id (@{$team->{'leerlingen'}}){
            my $pid = $pm->start($id) and next REMOVE_MEMBERS; # FORK
            # say "Verwijder $id uit $teamid";
            my $result = $group_object->group_removeMember($id);
            $result->{'type'} = 'member';
            $pm->finish(23,$result); # exit child
        }
        $pm->wait_all_children;
        # Door met owners
        REMOVE_OWNERS:
        foreach my $id (@{$team->{'docenten'}}){
            my $pid = $pm->start($id) and next REMOVE_OWNERS; # FORK
            # say "Verwijder $id uit $teamid";
            my $result = $group_object->group_removeOwner($id);
            $result->{'type'} = 'owner';
            $pm->finish(23,$result); # exit child
        }
        $pm->wait_all_children;
    }
}

# Vergelijk is klaar, createTeam mag draaien dus pidFile kan weg
end_script(0);
