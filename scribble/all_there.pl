#! /usr/bin/env perl
#
# Dit script doet een snelle check tov SectionUsage of
# team in magister wel bestaan en vice versa.
# SectionUsage gaat snel out of date uiteraard.
#
use v5.11;
use strict;
use warnings;
use Text::CSV qw( csv );
use DBI;
use Data::Dumper;
use Config::Simple;
use FindBin;

my $config;
Config::Simple->import_from("$FindBin::Bin/EduTeams.cfg", $config) or die("No config: $!");


my $driver = "SQLite";
my $db = "$FindBin::Bin/".$config{'CACHE_DIR'}."/teamsync.sqlite";

my $db_user = '';
my $db_pass = '';
my $dsn = "DBI:$driver:dbname=$db";
my $dbh = DBI->connect($dsn, $db_user, $db_pass, { RaiseError => 1 })
    or die $DBI::errstr;

# FF een hash maken van de teams
my $sth = $dbh->prepare('Select rowid,* From team');
$sth->execute;
my $teamsNaam = $sth->fetchall_hashref('naam');
$sth->finish;
#print Dumper $teamsNaam; #Indexed op naam
#exit 0;


my $azureTeams = csv ( 
    in => "$FindBin::Bin/CSV/SectionUsage.csv", 
    headers => "auto",
    sep_char => ";",
    encoding => "UTF-8"
    );

my $azureHash;

say "Controlle of Azure teams in Magister (db) staan";
foreach my $teamAzure (@$azureTeams){
    # In een hash zetten voor vice versa controlle
    $azureHash->{$teamAzure->{'CourseName'}}->{'blaat'} = 1;
    #print Dumper $teamAzure; 
    #say $teamAzure->{'CourseName'};
    if (! $teamsNaam->{$teamAzure->{'CourseName'}}){
        say "Azure team ", $teamAzure->{'CourseName'}, " staat niet in de database.";
    }
}

say "\nControlle of Magister teams in Azure staan";
foreach my $magisterTeam (keys %$teamsNaam){
    #say $magisterTeam;
    if (! $azureHash->{$magisterTeam}->{'blaat'}){
        # Hoeveel docenten?
        my $qry = "Select count(ROWID) From docrooster Where teamid = '";
        $qry .= $teamsNaam->{$magisterTeam}->{'rowid'};
        $qry .= "'";
        my $sth = $dbh->prepare($qry);
        $sth->execute;
        my $res = $sth->fetchrow_hashref();
        $sth->finish;
        say "Magister team ", $magisterTeam, " met ",$res->{'count(ROWID)'}," docenten staat niet in Azure.";
    }
}