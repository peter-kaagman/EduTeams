#! /usr/bin/env perl

use strict;
use warnings;
use v5.11;

use Data::Dumper;
use Config::Simple;
use DBI;
use FindBin;
use lib "$FindBin::Bin/../msgraph-perl/lib";
use lib "$FindBin::Bin/lib";

use Shared;

use MsUsers;
use Logger;


my %config;
Config::Simple->import_from("$FindBin::Bin/config/EduTeams.cfg",\%config) or die("No config: $!");

my $logger = Logger->new(
    'filename' => "$FindBin::Bin/Log/EduTeams.log",
    'verbose' => $config{'LOG_VERBOSE'}
);

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

# users
$dbh->do('Delete From users'); # Truncate the table 
my $qry = "Insert Into users (upn, azureid, naam) values (?,?,?) ";
my $sth_users_add = $dbh->prepare($qry);

my $users_object = MsUsers->new(
	'app_id'        => $config{'APP_ID'},
	'app_secret'    => $config{'APP_PASS'},
	'tenant_id'     => $config{'TENANT_ID'},
	'login_endpoint'=> $config{'LOGIN_ENDPOINT'},
	'graph_endpoint'=> $config{'GRAPH_ENDPOINT'},
	#'filter'        => '$filter=endswith(mail,\'atlascollege.nl\')', 
	#'filter'        => '$filter=userType eq \'Member\'', 
    'select'        => '$select=id,displayName,userPrincipalName',
	#'consistencylevel' => 'eventual',
);


my $users = $users_object->users_fetch;
$logger->make_log("$FindBin::Script ".@{$users}." users");
foreach my $user (@{$users}){
	#say $user->{'id'}," => ", $user->{'userPrincipalName'}," => ", $user->{'displayName'};
	
	# Geen onmicrosoft gebruikers toevoegen
	#56 Kwam er achter dat in de life omgeving gasten soms lid zijn van teams
	# moet deze gebruikers dus wel toevoegen
	# if ($user->{'userPrincipalName'} !~ /.*onmicrosoft.*/i){
	#my $qry = "Insert Into users (upn, azureid, naam) values (?,?,?) ";
		$sth_users_add->execute(
		lc($user->{'userPrincipalName'}),
		$user->{'id'},
		$user->{'displayName'}
	);
	# }else{
		# $logger->make_log("$FindBin::Script INFO skipping $user->{'userPrincipalName'}");
	# }
}
$logger->make_log("$FindBin::Script INFO einde");