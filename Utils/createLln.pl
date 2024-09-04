#! /usr/bin/env perl
#
# Dit script normaliseert de gedwonloade docent- en leerling gegevens vanuit Magister.
# Ze worden toegevoegd aan de database indien voor de locatie teams gemaakt worden.
# 
# #32 
# Pre rebuild
# docenten => 167 seconden
# leerlinge => 33' 23"
#
# Post rebuild
# INFO Start docenten rooster @ Tue Jul  9 23:07:02 2024
# INFO Einde docenten rooster @ Tue Jul  9 23:08:03 2024 duurde 61 seconden
# Start leerlingen rooster @ Tue Jul  9 23:08:03 2024
# INFO Einde leerlingen rooster @ Tue Jul  9 23:15:18 2024 duurde 435 seconden

use v5.11;
use strict;
use warnings;
use Encode qw(encode decode);
#use Text::CSV qw( csv ); # CSV afhandeling in Magister.pm
use DBI;
use Data::Dumper;
use FindBin;
use JSON;
use Config::Simple;
use Time::Piece;
use lib "$FindBin::Bin/../../magister-perl/lib";
use lib "$FindBin::Bin/../../msgraph-perl/lib";
use lib "$FindBin::Bin/../lib";

use Magister; # Diverse magister functies

binmode(STDOUT, ":utf8");

my %config;
Config::Simple->import_from("$FindBin::Bin/../config/EduTeams.cfg", \%config) or die("No config: $!");

my $driver = $config{'DB_DRIVER'};
my $db = "$FindBin::Bin/../".$config{'CACHE_DIR'}."/".$config{'DB_NAME'};
my $db_user = $config{'DB_USER'};
my $db_pass = $config{'DB_PASS'};
my $dsn = "DBI:$driver:dbname=$db";
my $dbh = DBI->connect($dsn, $db_user, $db_pass, { RaiseError => 1 })
    or die $DBI::errstr;

# Ga uit van accounts in de database (door getUsers.pl opgehaald)
# Users
# Users dient als zoek hash 
my $sth_users = $dbh->prepare("Select azureid,upn,ROWID From users");
$sth_users->execute();
my $usersByUpn = $sth_users->fetchall_hashref('upn');

say scalar keys %{$usersByUpn}," accounts in de database";

# En haal een lijst met lln voor het huidige schooljaar uit Magister
# Magister object om magister dingen mee te doen
my $mag_session= Magister->new(
    'user'          => $config{'MAGISTER_USER'},
    'secret'        => $config{'MAGISTER_SECRET'},
    'endpoint'      => $config{'MAGISTER_URL'},
    'lesperiode'    => $config{'MAGISTER_LESPERIODE'}

);
my $leerlingen = $mag_session->getLeerlingen(); # $leerlingen is een HOH indexed op upn

say scalar keys %{$leerlingen}, " leerlingen in Magister";

my $new = 0;
while( my ($upn, $lln) = each %{$leerlingen}){
    if (! $usersByUpn->{$upn}){
        $new++;
        say $upn, " => ", decode('UTF-8', $lln->{'naam'}), " => ", $lln->{'klas'};
    }
}
say "$new nieuwe leerlingen";
