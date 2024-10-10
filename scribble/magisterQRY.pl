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

my $blaat = $mag_session->getLayout('EduTeam-Doc-lesgroep','lesperiode=2425');
say Dumper $blaat;