#! /usr/bin/env perl

use v5.11;
use strict;
use warnings;
use Data::Dumper;
use FindBin;
use JSON;
use Config::Simple;
use Time::Piece;
use lib "$FindBin::Bin/../../magister-perl/lib";


use Magister; # Diverse magister functies

my %config;
Config::Simple->import_from("$FindBin::Bin/../config/EduTeams.cfg", \%config) or die("No config: $!");

# Magister object om magister dingen mee te doen
my $mag_session= Magister->new(
    'user'          => $config{'MAGISTER_USER'},
    'secret'        => $config{'MAGISTER_SECRET'},
    'endpoint'      => $config{'MAGISTER_URL'},
    'lesperiode'    => $config{'MAGISTER_LESPERIODE'}

);
#{
#            'KlasGroep' => '0v6.in1',
#            'email' => 'f.vonck@atlascollege.nl',
#            "\x{feff}stamnummer" => '126089',
#            'LocatieCode' => 'OSG'
#},

my $groepen = $mag_session->getLayout('EduTeam-Doc-lesgroep','lesperiode=2425');
my $groepen_uniek;
foreach my $groep (@{$groepen}){
	$groepen_uniek->{$groep->{'KlasGroep'}}++;
}
print Dumper $groepen_uniek;
