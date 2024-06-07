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
#use MsGroup;
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


# Eens kijken of er iets te doen is
my $sth = $dbh->prepare('Select ROWID,* From groupcreated');
$sth->execute();
while(my $row = $sth->fetchrow_hashref()){
    my $groups_object = MsGroups->new(
        'app_id'        => $config{'APP_ID'},
        'app_secret'    => $config{'APP_PASS'},
        'tenant_id'     => $config{'TENANT_ID'},
        'login_endpoint'=> $config{'LOGIN_ENDPOINT'},
        'graph_endpoint'=> $config{'GRAPH_ENDPOINT'},
        'filter'        => '$filter=startswith(mail,\'Section_\')',
        'select'        => '$select=id,displayName,description,mail',
    );
    my $users_object = MsUser->new(
        'app_id'        => $config{'APP_ID'},
        'app_secret'    => $config{'APP_PASS'},
        'tenant_id'     => $config{'TENANT_ID'},
        'login_endpoint'=> $config{'LOGIN_ENDPOINT'},
        'graph_endpoint'=> $config{'GRAPH_ENDPOINT'},
        'filter'        => '$filter=startswith(mail,\'Section_\')',
        'select'        => '$select=id,displayName,description,mail',
    );
    # print Dumper $row;
    # Vlgs https://learn.microsoft.com/en-us/graph/teams-create-group-and-team
    # - Group maken (wat dus al gedaan is)
    # - daarna via de groups interface gebruikers toevoegen
    # - 15 minuten wachten
    # - teams transitie
    #
    # Owners moeten toegevoegd zijn voor de transitie
    if ($row->{'owners_added'} eq '0'){
        # Owners moeten nog toegevoegd worden
        my $owners = decode_json($row->{'owners'});
        # print Dumper $owners;
        foreach my $id (keys %{$owners}){
            my $result = $groups_object->add_owner($row->{'id'},$id);
            if ($result eq 'Ok'){
            }else{
                $logger->make_log("$FindBin::Bin/$FindBin::Script $row->{'naam'} $row->{'id'} kan owner $id niet toevoegen");
            }
        }
        $dbh->do("Update groupcreated Set owners_added = \'1\' Where ROWID = $row->{'rowid'}");
    }
    if ($row->{'members_added'} eq '0'){
        # Gebruikers moeten nog toegevoegd worden
        my $members = decode_json($row->{'members'});
        # print Dumper $members;
        foreach my $upn (keys %{$members}){
            # Van leerlingen is alleen de UPN bekend vanuit Magister
            my $member_id = $users_object->fetch_id_by_upn($upn);
            #say "$upn => $member_id";
            if ($member_id ne 'onbekend'){
                my $result = $groups_object->add_member($row->{'id'},$member_id);
                if ($result eq 'Ok'){
                }else{
                    $logger->make_log("$FindBin::Bin/$FindBin::Script ERROR AddUser $upn, $member_id: $result");
                }
            }else{
                $logger->make_log("$FindBin::Bin/$FindBin::Script Geen AddUser AzureID bekend voor $upn");
            }
        }
        $dbh->do("Update groupcreated Set members_added = \'1\' Where ROWID = $row->{'rowid'}");
    }
    my $now = localtime->epoch;
    my $date = $row->{'timestamp'};
    #  say "Nu    : " . $now;
    #  say "Team  : " . $date;
      say "Delta : " . ($now-$date)/60;
    if ( (($now-$date)/60)  > 15 ){
        $logger->make_log("$FindBin::Bin/$FindBin::Script Group transitie: $row->{'naam'}");
        my $result = $groups_object->team_from_group($row->{'id'});
        if ($result eq 'Ok'){
        }else{
            $logger->make_log("$FindBin::Bin/$FindBin::Script ERROR Group transitie: $result");
        }
    }else{
        $logger->make_log("$FindBin::Bin/$FindBin::Script Deze gaan we nietdoen: $row->{'naam'}: $now => $row->{'timestamp'}");
    }
    # Na de transitie naar team moet er nog een controle komen dat er een SPO general gemaakt is
    # dit schijnt soms niet te gebeuren.
}
$logger->make_log("$FindBin::Bin/$FindBin::Script einde.");
