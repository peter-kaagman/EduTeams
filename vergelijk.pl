#! /usr/bin/env perl
#
# Dit script maakt hashes van de Magister en Azure teams en vergelijkt deze tov elkaar
# 
use v5.11;
use strict;
use warnings;
use DBI;
use Data::Dumper;
use FindBin;
use Config::Simple;
use lib "$FindBin::Bin/lib";

use Logger; # Om te loggen

my $logger = Logger->new(
    'filename' => "$FindBin::Bin/Log/EduTeams.log",
    'verbose' => 0
);
$logger->make_log("$FindBin::Bin/$FindBin::Script started.");

my %config;
Config::Simple->import_from("$FindBin::Bin/EduTeams.cfg", \%config) or die("No config: $!");
#print Dumper \%config; exit 0;

my $driver = $config{'DB_DRIVER'};
my $db = "$FindBin::Bin/db/".$config{'DB_NAME'};
my $db_user = $config{'DB_USER'};
my $db_pass = $config{'DB_PASS'};
my $dsn = "DBI:$driver:dbname=$db";
my $dbh = DBI->connect($dsn, $db_user, $db_pass, { RaiseError => 1 })
    or die $DBI::errstr;

# Azure hash
$logger->make_log("$FindBin::Bin/$FindBin::Script Azure hash maken.");

my $Azure;
my $qry = << "END_QRY";
Select
    azureteam.*,
    azuredocent.upn As 'docent_upn',
    azuredocent.naam As 'docent_naam',
    azureleerling.upn As 'leerling_upn',
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
        $Azure->{$row->{'description'}}->{'docenten'}->{$row->{'docent_upn'}} = $row->{'docent_naam'};
    #}else{
    #    $logger->make_log("$FindBin::Bin/$FindBin::Script ". $row->{'description'}. " heeft geen docenten");
    }
    if ($row->{'leerling_naam'}){
        $Azure->{$row->{'description'}}->{'leerlingen'}->{$row->{'leerling_upn'}} = $row->{'leerling_naam'};
    #}else{
    #    $logger->make_log("$FindBin::Bin/$FindBin::Script ". $row->{'description'}. " heeft geen leerlingen");
    }
}
$sth->finish;
#print Dumper $Azure;
$logger->make_log("Aantal Azure teams: " . scalar keys %$Azure);
$logger->make_log("$FindBin::Bin/$FindBin::Script Azure hash gemaakt.");

# Magister hash
$logger->make_log("$FindBin::Bin/$FindBin::Script Magister hash maken.");

my $Magister;
$qry = << "END_QRY";
Select
    magisterteam.*,
    magisterdocent.upn As 'docent_upn',
    magisterdocent.naam As 'docent_naam',
    magisterleerling.upn As 'leerling_upn',
    magisterleerling.naam As 'leerling_naam'
From magisterteam
Left Join magisterdocentenrooster   On magisterdocentenrooster.teamid = magisterteam.ROWID
Left Join magisterdocent            On magisterdocentenrooster.docentid = magisterdocent.ROWID
Left Join magisterleerlingenrooster On magisterleerlingenrooster.teamid = magisterteam.ROWID
Left Join magisterleerling          On magisterleerlingenrooster.leerlingid = magisterleerling.ROWID
END_QRY
$sth = $dbh->prepare($qry);
$sth->execute();
while (my $row = $sth->fetchrow_hashref()){
    if ($row->{'docent_naam'}){
        $Magister->{$row->{'naam'}}->{'docenten'}->{$row->{'docent_upn'}} = $row->{'docent_naam'};
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

# Vergelijk Magister met Azure
$logger->make_log("$FindBin::Bin/$FindBin::Script Magister vergelijken met Azure.");

my $ToDo;
while (my ($magisternaam, $magisterteam) = each( %$Magister)){
    #say $naam;
    #print Dumper $magisterteam;

    # Een magister team moet een docent en leerlingen hebben
    if ( ! $magisterteam->{'docenten'} ||  ! $magisterteam->{'leerlingen'} ){
        # Dit team heeft geen leerlingen
        # Zou dus niet mogen bestaan in Azure
        if ($Azure->{$magisternaam}){
            # Geen leerlingen of docent, maar er is wel een Azure team
            # Hier iets doen met Azure
            push (@{$ToDo->{'Archiveren'}}, $magisternaam)
        # }else{
        #     # Hier niets doen
        #     say "Team $magisternaam heeft geen leerlingen bestaat niet in Azure";
        }
    }else{
        # Dit team heeft leerlingen
        # en zou dus moeten bestaan in Azure;
        if (! $Azure->{$magisternaam}){
            # Azure team bestaat niet
            # Hier iets doen met Azure
            push (@{$ToDo->{'Maken'}}, $magisternaam)
        }else{
            # Azure bestaat 
            # Eigenaren en leden controleren
            # Eigenaren
            foreach my $magister_upn (keys %{$magisterteam->{'docenten'}}){
                if (! $Azure->{$magisternaam}->{'docenten'}->{$magister_upn}){
                    push(@{$ToDo->{'DocentToevoegen'}->{$magisternaam}}, $magister_upn);
                }
            }
            # Leerlingen
            foreach my $magister_upn (keys %{$magisterteam->{'leerlingen'}}){
                if (! $Azure->{$magisternaam}->{'leerlingen'}->{$magister_upn}){
                    push(@{$ToDo->{'LeerlingToevoegen'}->{$magisternaam}}, $magister_upn);
                }
            }
        }
    }

}

print Dumper $ToDo;

$logger->make_log("$FindBin::Bin/$FindBin::Script Magister vergelijken klaar.");



$logger->make_log("$FindBin::Bin/$FindBin::Script Beeindigd.");

