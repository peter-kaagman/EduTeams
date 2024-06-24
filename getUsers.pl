#! /usr/bin/env perl

use strict;
use warnings;
use v5.11;

use Data::Dumper;
use Config::Simple;
use DBI;
use FindBin;
use lib "$FindBin::Bin/lib";

use MsUsers;
use Logger;

my $logger = Logger->new(
    'filename' => "$FindBin::Bin/Log/EduTeams.log",
    'verbose' => 1
);
$logger->make_log("$FindBin::Bin/$FindBin::Script INFO started.");

my %config;
Config::Simple->import_from("$FindBin::Bin/config/EduTeamsTest.cfg",\%config) or die("No config: $!");


my $driver = $config{'DB_DRIVER'};
my $db = "$FindBin::Bin/db/".$config{'DB_NAME'};
my $db_user = $config{'DB_USER'};
my $db_pass = $config{'DB_PASS'};
my $dsn = "DBI:$driver:dbname=$db";
my $dbh = DBI->connect($dsn, $db_user, $db_pass, { RaiseError => 1 })
    or die $DBI::errstr;

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
	'filter'        => '$filter=userType eq \'Member\'', 
    'select'        => '$select=id,displayName,userPrincipalName',
	#'consistencylevel' => 'eventual',
);

my $users = $users_object->users_fetch;
$logger->make_log("$FindBin::Bin/$FindBin::Script ".@{$users}." users");
foreach my $user (@{$users}){
	#say $user->{'id'}," => ", $user->{'userPrincipalName'}," => ", $user->{'displayName'};
	
	# Geen onmicrosoft gebruikers toevoegen
	if ($user->{'userPrincipalName'} !~ /.*onmicrosoft.*/i){
	#my $qry = "Insert Into users (upn, azureid, naam) values (?,?,?) ";
		$sth_users_add->execute(
		lc($user->{'userPrincipalName'}),
		$user->{'id'},
		$user->{'displayName'}
	);
	}else{
		say "skipping $user->{'userPrincipalName'}";
	}
}
$logger->make_log("$FindBin::Bin/$FindBin::Script INFO einde");
