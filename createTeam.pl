#! /usr/bin/env perl
#
# Als een group gemaakt is moet minimaal 15 minuten gewacht wordne
# voor er een team van gemaakt kan worden.
# Dit script (via cron?) periodiek uitvoeren
#

# TODO@peter-kaagman/issue{1}


use strict;
use warnings;
use v5.11;

use Data::Dumper;
use Config::Simple;
use DBI;
use FindBin;
use JSON;
use Switch;
use Parallel::ForkManager;
use Time::Piece;
use Time::Seconds;
use Proc::Exists qw(pexists);
use lib "$FindBin::Bin/../msgraph-perl/lib";
use lib "$FindBin::Bin/lib";


use MsGroups;
use MsGroup;
use MsUser;
use Logger;
use Shared;

#
# Test config
my %config;
Config::Simple->import_from("$FindBin::Bin/config/EduTeams.cfg",\%config) or die("No config: $!");

my $logger = Logger->new(
    'filename' => "$FindBin::Bin/Log/EduTeams.log",
    'verbose' => $config{'LOG_VERBOSE'}
);
$logger->make_log("$FindBin::Script INFO started.");

# Eerst maar ff checken of er een PID file is
my $pidFile = "$FindBin::Bin/Run/$config{'PID_FILE'}";
if (-e $pidFile){
    open (FH, '<', $pidFile) or die $!;
    my $pid = <FH>;
    if (pexists($pid)){
        $logger->make_log("$FindBin::Script INFO pid file gevonden met PID $pid.");
        exit 1;
    }else{
        $logger->make_log("$FindBin::Script INFO stale pid file gevonden, wordt verwijderd");
        unlink $pidFile; # stale pidFile => verwijderen
    }
}

write_pid("$FindBin::Bin/Run/$config{'PID_FILE'}");  # PID moet wegeschreven zijn

my $driver = $config{'DB_DRIVER'};
my $db = "$FindBin::Bin/".$config{'CACHE_DIR'}."/".$config{'DB_NAME'};
my $db_user = $config{'DB_USER'};
my $db_pass = $config{'DB_PASS'};
my $dsn = "DBI:$driver:dbname=$db";
my $dbh = DBI->connect($dsn, $db_user, $db_pass, { RaiseError => 1 })
    or die $DBI::errstr;    

my $sth_team_gemaakt = $dbh->prepare('Update teamcreated Set team_gemaakt = ? Where rowid = ?'); 
my $sth_general = $dbh->prepare('Update teamcreated Set general_checked = ? Where rowid = ?'); 
my $sth_writeback_members = $dbh->prepare('Update teamcreated Set members = ? Where rowid = ?');

my $groups_object = MsGroups->new(
    'app_id'        => $config{'APP_ID'},
    'app_secret'    => $config{'APP_PASS'},
    'tenant_id'     => $config{'TENANT_ID'},
    'login_endpoint'=> $config{'LOGIN_ENDPOINT'},
    'graph_endpoint'=> $config{'GRAPH_ENDPOINT'},
    'filter'        => '$filter=startswith(mail,\'EduTeam_\')',
    'select'        => '$select=id,displayName,description,mail',
);


#
# Voegt parallel de member toe aan een team;
sub addMembers {
    my $row = shift;
    my $members = decode_json $row->{'members'};
    my $pm = Parallel::ForkManager->new($config{'AZURE_THREADS'}, "$FindBin::Bin/".$config{'CACHE_DIR'}."/");

    # Callback
    $pm->run_on_finish( sub{
        my ($pid,$exit_code,$ident,$exit,$core_dump,$result) = @_;
        if ($result->is_success){
            delete $members->{$ident};
            if ($result->{'role'} eq 'docent'){
                # voeg epoch tijd toe als owner added time
                # dit is nodig om te kunnen wachten met de transitie
                $dbh->do("Update teamcreated Set owner_added = '".localtime->epoch."' Where rowid = $result->{'rowid'}");
            }
        }else{
            # ff de fout analyseren
            my $content = decode_json $result->decoded_content;
            if ($content->{'error'}->{'message'} =~ /.*already exist.*/){
                # Om de een of andere reden is de gebruiker al lid
                delete $members->{$ident};
                if ($result->{'role'} eq 'docent'){
                    $dbh->do("Update teamcreated Set owner_added = 1 Where rowid = $result->{'rowid'}");
                }
            }
        }
    });

    MEMBERS:
    while( my ($member_id,$role) =  each (%{$members})){
        my $pid = $pm->start($member_id) and next MEMBERS; # FORK
        my $group_object = MsGroup->new(
            'app_id'        => $config{'APP_ID'},
            'app_secret'    => $config{'APP_PASS'},
            'tenant_id'     => $config{'TENANT_ID'},
            'access_token'  => $groups_object->_get_access_token, #reuse token
            'token_expires' => $groups_object->_get_token_expires,
            'login_endpoint'=> $config{'LOGIN_ENDPOINT'},
            'graph_endpoint'=> $config{'GRAPH_ENDPOINT'},
            'id'            => $row->{'id'},
        );
        $logger->make_log("$FindBin::Script Member $member_id toevoegen aan $row->{'id'} en is $role");
        my $result;
        if ($role eq 'docent'){
            $result = $group_object->group_add_member($member_id, 1);
        }else{
            $result = $group_object->group_add_member($member_id, 0);
        }
        $result->{'role'} = $role;
        $result->{'rowid'} = $row->{'rowid'};
        $pm->finish(23,$result); # exit child
    }
    $pm->wait_all_children;
    # my $sth_writeback_members = $dbh->prepare('Update teamcreated Set members = ? Where rowid = ?');
    $sth_writeback_members->execute(encode_json($members), $row->{'rowid'}) or warn('wtf');
}

#
# Paralle transitie van group naar team
sub groupsToTeams {
    my $sth = $dbh->prepare('Select ROWID,id,naam,owner_added From teamcreated Where owner_added  And team_gemaakt = 0');
    $sth->execute();
    my $pm = Parallel::ForkManager->new($config{'AZURE_THREADS'}, "$FindBin::Bin/".$config{'CACHE_DIR'}."/"); 
    # Callback
    $pm->run_on_finish( sub{
        my ($pid,$exit_code,$ident,$exit,$core_dump,$result) = @_;
        if ($result->is_success){
            $sth_team_gemaakt->execute(encode_json(localtime->epoch), $ident);
        }elsif($result->{'_rc'} eq 409){
            #say "Is blijkbaar al geprovisioned";
            $sth_team_gemaakt->execute(encode_json(localtime->epoch), $ident);
        }else{
            $logger->make_log("$FindBin::Script ERROR Group transitie: $result->{'naam'} ". $result->decoded_content);
        }
    });
    TRANSITIE:
    while(my $row = $sth->fetchrow_hashref()){
          
        if ( ( (localtime->epoch - $row->{'owner_added'}) )  > 300 ) { # 300 seconden na eigenaar toevoegen
            my $pid = $pm->start($row->{'rowid'}) and next TRANSITIE; # FORK
            my $group_object = MsGroup->new(
                'app_id'        => $config{'APP_ID'},
                'app_secret'    => $config{'APP_PASS'},
                'tenant_id'     => $config{'TENANT_ID'},
                'access_token'  => $groups_object->_get_access_token, #reuse token
                'token_expires' => $groups_object->_get_token_expires,
                'login_endpoint'=> $config{'LOGIN_ENDPOINT'},
                'graph_endpoint'=> $config{'GRAPH_ENDPOINT'},
                'id'            => $row->{'id'},
            );
            $logger->make_log("$FindBin::Script INFO Group transitie: $row->{'naam'}");
            #my $result;
            my $result = $group_object->team_from_group();
            $result->{'naam'} = $row->{'naam'};
            $pm->finish(23,$result); # exit child
        }else{
            $logger->make_log("$FindBin::Script INFO waiting for transition: $row->{'naam'}");
        }
    }
    $pm->wait_all_children;
    $sth->finish;
}

#
# Paralle transitie van group naar team
sub checkGeneral {
    my $sth = $dbh->prepare('Select ROWID,id,naam,team_gemaakt From teamcreated Where team_gemaakt > 1');
    $sth->execute();
    my $pm = Parallel::ForkManager->new($config{'AZURE_THREADS'}, "$FindBin::Bin/".$config{'CACHE_DIR'}."/"); 
    # Callback
    $pm->run_on_finish( sub{
        my ($pid,$exit_code,$ident,$exit,$core_dump,$result) = @_;
        if ($result->is_success){
            $sth_general->execute(encode_json(localtime->epoch), $ident);
        }else{
            $logger->make_log("$FindBin::Script INFO Check general failed: $result->{'naam'} ");
            $sth_general->execute(encode_json(localtime->epoch), $ident);
        }
    });
    GENERAL:
    while(my $row = $sth->fetchrow_hashref()){
        if ( ( (localtime->epoch - $row->{'team_gemaakt'}) )  > 300 ) { # 300 seconden na transitie
            my $pid = $pm->start($row->{'rowid'}) and next GENERAL; # FORK
            my $group_object = MsGroup->new(
                'app_id'        => $config{'APP_ID'},
                'app_secret'    => $config{'APP_PASS'},
                'tenant_id'     => $config{'TENANT_ID'},
                'access_token'  => $groups_object->_get_access_token, #reuse token
                'token_expires' => $groups_object->_get_token_expires,
                'login_endpoint'=> $config{'LOGIN_ENDPOINT'},
                'graph_endpoint'=> $config{'GRAPH_ENDPOINT'},
                'id'            => $row->{'id'},
            );
            $logger->make_log("$FindBin::Script INFO check general: $row->{'naam'}");
            my $result = $group_object->team_check_general;
            $result->{'naam'} = $row->{'naam'};
            $pm->finish(23,$result); # exit child
        }else{
            $logger->make_log("$FindBin::Script INFO Check general delayed: ".(localtime->epoch - $row->{'team_gemaakt'}));
        }
    }
    $pm->wait_all_children;
    $sth->finish;
}

# Deze loop is voor het toevoegen van members
my $sth = $dbh->prepare('Select ROWID,* From teamcreated');
$sth->execute();
while(my $row = $sth->fetchrow_hashref()){
    if (
        ($row->{'general_checked'}) &&
        (! %{decode_json $row->{'members'} }) 
    ){
        $logger->make_log("$FindBin::Script INFO Verwerking team $row->{'naam'} is klaar");
        $dbh->do("Delete From teamcreated Where rowid = $row->{'rowid'}");
    }else{
        if ( ( (localtime->epoch - $row->{'timestamp'}) )  > 900 ){ # 900 seconden =>15 minuten
            $logger->make_log("$FindBin::Script INFO Class $row->{'naam'} en kan verwerkt worden.");
            # Het eerste wat gedaan moet worden is owners en member toevoegen aan de group
            if (scalar %{decode_json $row->{'members'}}){
                #say "We moeten leden toevoegen";
                addMembers($row);
            }
        }else{
            $logger->make_log("$FindBin::Script INFO Deze gaan we niet doen: $row->{'naam'}: ".(localtime->epoch - $row->{'timestamp'}));
        }
    }

}
$sth->finish;

# Kijken of er groepen zijn die klaar zijn voor transitie naar een team
# $row->{'owner_added'} en $row->{'team_created'} zijn de voorwaarden. Die is gezet indien (na 900 sec) en een owner is toegevoegd
groupsToTeams();

# Kijken of er groepen zijn die klaar zijn voor een check van het general channel
# $row->{'team_created'} is de voorwaarde. Die is gezet na de transitie van een group
checkGeneral();

# Verwijderen indien de general check gedaan is
$dbh->do('Delete from teamcreated Where general_checked > 1');


$sth_team_gemaakt->finish;
$sth_writeback_members->finish;
$dbh->disconnect;
unlink "$FindBin::Bin/Run/$config{'PID_FILE'}";
$logger->make_log("$FindBin::Script einde.");
