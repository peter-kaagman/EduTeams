#! /usr/bin/env perl
#
# Als een group gemaakt is moet minimaal 15 minuten gewacht wordne
# voor er een team van gemaakt kan worden.
# Dit script (via cron?) periodiek uitvoeren
#
use strict;
use warnings;
use v5.11;

use Data::Dumper;
use Config::Simple;
use DBI;
use FindBin;
use JSON;
use Time::Piece;
use Time::Seconds;
use lib "$FindBin::Bin/lib";

use MsGroups;
use MsGroup;
use MsUser;
use Logger;

#
# Test config
my %config;
Config::Simple->import_from("$FindBin::Bin/config/EduTeamsTest.cfg",\%config) or die("No config: $!");

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

my $sth_azureleerling = $dbh->prepare("Insert Into azureleerling  (upn, azureid, naam) values (?,?,'van create team')");
# Een hash om lln id's te bewaren, indexed op UPN
# Er is een tabel AzureLeerlingen, daar kunnen al gegevens in staan, scheelt weer requests
my $sth = $dbh->prepare("Select upn,azureid From azureleerling");
$sth->execute;
my $lln_by_upn = $sth->fetchall_hashref('upn');
$sth->execute;
my $lln_by_id = $sth->fetchall_hashref('azureid');

my $groups_object = MsGroups->new(
    'app_id'        => $config{'APP_ID'},
    'app_secret'    => $config{'APP_PASS'},
    'tenant_id'     => $config{'TENANT_ID'},
    'login_endpoint'=> $config{'LOGIN_ENDPOINT'},
    'graph_endpoint'=> $config{'GRAPH_ENDPOINT'},
    'filter'        => '$filter=startswith(mail,\'Section_\')',
    'select'        => '$select=id,displayName,description,mail',
);

my $user_object = MsUser->new(
    'app_id'        => $config{'APP_ID'},
    'app_secret'    => $config{'APP_PASS'},
    'tenant_id'     => $config{'TENANT_ID'},
    'login_endpoint'=> $config{'LOGIN_ENDPOINT'},
    'graph_endpoint'=> $config{'GRAPH_ENDPOINT'},
    'filter'        => '$filter=startswith(mail,\'Section_\')',
    'access_token'  => $groups_object->_get_access_token, # resuse token
    'token_expires' => $groups_object->_get_token_expires,
    'select'        => '$select=id,displayName,description,mail',
);


# Eens kijken of er iets te doen is
$sth = $dbh->prepare('Select ROWID,* From teamcreated');
$sth->execute();


while(my $row = $sth->fetchrow_hashref()){
    #my $now = localtime->epoch;
    #print Dumper $row;
    # Verwijder het record als  alles al gedaan is
    if (
        ($row->{'naam_hersteld'} eq 0) ||
        ($row->{'general_checked'} eq 0) ||
        ( %{decode_json($row->{'owners'})} > 0) || 
        ( %{decode_json($row->{'members'})} > 0) 
    ){
        if ( ( (localtime->epoch - $row->{'timestamp'}) )  > 900 ){ # 900 seconden =>15 minuten
            $logger->make_log("$FindBin::Bin/$FindBin::Script Group transitie: $row->{'naam'}");
            # Kan zijn dat het een 2e run is en de id al bekend is
            my $team_id;
            if ($row->{'id'}){
                $team_id = $row->{'id'}
            }else{
                # Niet in de database dus ff opzoeken via de mailNickname, deze is immutable en heeft Section_ als prefix
                $team_id = $groups_object->group_find_id("Section_".$row->{'naam'});
            }
            if ($team_id){
                 $logger->make_log("$FindBin::Bin/$FindBin::Script INFO Id bekend: $team_id");
                # Udate de database, waarschijnlijk alleen handig tijdens debuggen
                $dbh->do("Update teamcreated Set id = '$team_id' Where ROWID = $row->{'rowid'}");
                my $group_object = MsGroup->new(
                    'app_id'        => $config{'APP_ID'},
                    'app_secret'    => $config{'APP_PASS'},
                    'tenant_id'     => $config{'TENANT_ID'},
                    'access_token'  => $groups_object->_get_access_token, #reuse token
                    'token_expires' => $groups_object->_get_token_expires,
                    'login_endpoint'=> $config{'LOGIN_ENDPOINT'},
                    'graph_endpoint'=> $config{'GRAPH_ENDPOINT'},
                    'select'        => '$select=id,displayName,userPrincipalName',
                    'id'            => $team_id,
                );
                
                # Naam herstellen
                if ($row->{'naam_hersteld'} eq 0 ){
                    say "displayName en description herstellen";
                    my $namechange = {
                        "displayName" => $row->{'naam'},
                        "description" => $row->{'naam'},
                    };
                    my $result = $group_object->group_patch($namechange);
                    if ($result eq 'Ok'){
                        #say "Naamsverandering uitgevoerd.";
                        $dbh->do("Update teamcreated Set naam_hersteld = 1 Where ROWID = $row->{'rowid'}");
                    }else{
                        $logger->make_log("$FindBin::Bin/$FindBin::Script ERRORFout met naamsverandering.".encode_json($result));
                        #print Dumper $result;
                    }
                }

                # Owners toevoegen
                my $owners = decode_json($row->{'owners'});
                if (%{$owners}){
                    # Members toevoegen met conversationMember: add (bulbk)
                    # Voordeel: members toevoegen met UPN of ID
                    # Nadeel: maximaal 200 member
                    my $members;
                    #say "Eigenaren toevoegen";
                    foreach my $id (keys %{$owners}){
                        last if ( ($members->{'values'}) && (@{$members->{'values'}} eq 200) ); # nooit meer dan 200 members toevoegen
                        my $user = {
                            '@odata.type'=> '#microsoft.graph.aadUserConversationMember',
                            'user@odata.bind' => "https://graph.microsoft.com/v1.0/users(\'$id\')"
                        };
                        push(@{$user->{'roles'}}, 'owner');
                        push(@{$members->{'values'}}, $user);
                    }
                    #print Dumper $members;
                    if (%{$members}){
                        #say encode_json($members);
                        my $result = $group_object->team_bulk_add_members($members);
                        if ($result->is_success){
                            my $reply =  decode_json($result->{'_content'});
                            #print Dumper $reply;
                            foreach my $report (@{$reply->{'value'}}){
                                print Dumper $report;
                                if ($report->{'error'}){
                                    say "error"
                                }else{
                                    #say "geen error, docent $report->{'userId'} is toegevoegd";
                                    # Success => verwijderen uit de todo hash
                                    delete($owners->{$report->{'userId'}})
                                }
                            }
                            # Schrijf de todo hash terug naar de database, kan dus ook leeg zijn
                            my $qry = "Update teamcreated Set owners = '".encode_json($owners)."' Where ROWID = $row->{'rowid'}";
                            $dbh->do($qry);
                        }else{
                            $logger->make_log("$FindBin::Bin/$FindBin::Script ERROR Fout bij het toevoegen van gebruikers aan $row->{'naam'}");
                        }
                    }
                }

                # Leden toevoegen
                my $leden = decode_json($row->{'members'});
                if (%{$leden}){
                    # Members toevoegen met conversationMember: add (bulbk)
                    # Voordeel: members toevoegen met UPN of ID, niet echt een voordeel => rapport komt op id
                    # Nadeel: maximaal 200 member
                    print Dumper $leden;
                    my $members;
                    say "Leden toevoegen";
                    foreach my $upn (keys %{$leden}){
                        last if ( ($members->{'values'}) && (@{$members->{'values'}} eq 200) ); # nooit meer dan 200 members toevoegen
                        # Leden (lln) staan met een UPN in de hash, 
                        # toevoegen kan ook met een UPN, maar de terugkoppeling komt op ID
                        my $lln_id;
                        # Een hoop gedoe om van de UPN een ID te krijgen en ook vice versa op te kunnen zoeken
                        if ($lln_by_upn->{$upn}->{'azureid'}){
                            $lln_id = $lln_by_upn->{$upn}->{'azureid'};
                            $lln_by_id->{$lln_id}->{'upn'} = $upn;
                        }else{
                            $lln_id = $user_object->fetch_id_by_upn($upn);
                            $lln_by_upn->{$upn}->{'azureid'} = $lln_id;
                            $lln_by_id->{$lln_id}->{'upn'} = $upn;
                            # ook ff terugschrijven naar azureleerling
                            if ($lln_id ne 'onbekend'){
                                say "$upn => $lln_id";
                                $sth_azureleerling->execute($upn,$lln_id);
                            }
                        }                    
                        if ($lln_id ne 'onbekend'){ # het is mogelijk dat een lln in Magister niet in Azure staat
                            my $user = {
                                '@odata.type'=> '#microsoft.graph.aadUserConversationMember',
                                'user@odata.bind' => "https://graph.microsoft.com/v1.0/users(\'$lln_id\')"
                            };
                            push(@{$members->{'values'}}, $user);
                        }else{
                            $logger->make_log("$FindBin::Bin/$FindBin::Script ERROR LLN $upn heeft geen Azure account");
                        }
                    }
                    #print Dumper $members;
                    if (%{$members}){
                        #say encode_json($members);
                        my $result = $group_object->team_bulk_add_members($members);
                        if ($result->is_success){
                            my $reply =  decode_json($result->{'_content'});
                            #print Dumper $reply;
                            foreach my $report (@{$reply->{'value'}}){
                                print Dumper $report;
                                if ($report->{'error'}){
                                    say "error"
                                }else{
                                    #say "geen error, lln $lln_by_id->{$report->{'userId'}}  is toegevoegd";
                                    # Succes => verwijderen uit de todo hash
                                    delete($leden->{$lln_by_id->{$report->{'userId'}}->{'upn'}});
                                }
                            }
                            # schrijf de todo hash terug naar de database (kan dus ook leeg zijn)
                            my $qry = "Update teamcreated Set members = '".encode_json($leden)."' Where ROWID = $row->{'rowid'}";
                            #say $qry;
                            $dbh->do($qry);
                        }else{
                            $logger->make_log("$FindBin::Bin/$FindBin::Script ERROR Fout bij het toevoegen van gebruikers aan $row->{'naam'}");
                        }
                    }
                }
                say "General channel controleren";
                # Het kan voorkomen dat er een probleem met SOP site voor het team.
                # Dit kun je na 5 minuten herstellen door een GetFilesFolder van General op te vragen.
                my $result = $group_object->team_check_general;
                if ($result->is_success){
                    $logger->make_log("$FindBin::Bin/$FindBin::Script INFO General channel van $row->{'naam'} is gecontroleerd en ok");
                    $dbh->do("Update teamcreated Set general_checked = 1 Where ROWID = $row->{'rowid'}");
                }else{
                    $logger->make_log("$FindBin::Bin/$FindBin::Script WARNING Probleem met general channel van $row->{'naam'}".encode_json($result));
                }
            }else{
                $logger->make_log("$FindBin::Bin/$FindBin::Script  WARNING Kan geen ID ophalen voor $row->{'naam'}");
            }
        }else{
            $logger->make_log("$FindBin::Bin/$FindBin::Script Deze gaan we niet doen: $row->{'naam'}: ".(localtime->epoch - $row->{'timestamp'}));
        }
    }else{
        say "Alles is gedaan => verwijderen";
        $dbh->do("Delete From teamcreated Where ROWID = $row->{'rowid'}");
    }
}
$logger->make_log("$FindBin::Bin/$FindBin::Script einde.");
