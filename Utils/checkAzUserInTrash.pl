#! /usr/bin/env perl

use strict;
use warnings;
use v5.11;

use utf8;
use Text::CSV qw( csv );
use Data::Dumper;
use Config::Simple;
use DBI;
use FindBin;
use lib "$FindBin::Bin/../../msgraph-perl/lib";

use MsUsers;

binmode(STDOUT, ":utf8");

my %config;
Config::Simple->import_from("$FindBin::Bin/../config/EduTeams.cfg",\%config) or die("No config: $!");

my $users_object_trash = MsUsers->new(
	'app_id'        => $config{'APP_ID'},
	'app_secret'    => $config{'APP_PASS'},
	'tenant_id'     => $config{'TENANT_ID'},
	'login_endpoint'=> $config{'LOGIN_ENDPOINT'},
	'graph_endpoint'=> $config{'GRAPH_ENDPOINT'},
    'select'        => '$select=id,displayName,onPremisesUserPrincipalName',
);
my $users_object_live = MsUsers->new(
	'app_id'        => $config{'APP_ID'},
	'app_secret'    => $config{'APP_PASS'},
	'tenant_id'     => $config{'TENANT_ID'},
	'login_endpoint'=> $config{'LOGIN_ENDPOINT'},
	'graph_endpoint'=> $config{'GRAPH_ENDPOINT'},
    'access_tokenn' => $users_object_trash->_get_access_token,
    'token+expires' => $users_object_trash->_get_token_expires,
    'select'        => '$select=id,displayName,userPrincipalName,jobTitle',
);


my $users_aoh = $users_object_live->users_fetch;
my $users;
foreach my $user (@{$users_aoh}){
    if ($user->{'jobTitle'}){
        $users->{lc($user->{'userPrincipalName'})} = $user;
    }
}

my $deleted_users_aoh = $users_object_trash->users_fetch_deleted; # AoH
my $deleted_users;

foreach my $user (@{$deleted_users_aoh}){
    if ($user->{'onPremisesUserPrincipalName'}){
        $deleted_users->{lc($user->{'onPremisesUserPrincipalName'})} = $user;
    }
}

my ($count, @herstellen);
while (my ($upn,$deleted) = each (%{$deleted_users})){
    if ($users->{$upn}){
        $count++;
        push @herstellen, $users->{$upn};
    }
}
csv(
    in => \@herstellen,
    out => './herstellen.csv',
    headers => 'auto',
    sep_char => ';',
    encoding => "UTF-8"
);
say "$count leerlingen ten onrecht verwijderd";