#! /usr/bin/env perl

use strict;
use warnings;
use v5.11;

use utf8;
use Config::Simple;
#use JSON qw(decode_json encode_json);
use Time::Piece;
use Time::Seconds;
use FindBin;
use lib "$FindBin::Bin/../../magister-perl/lib";

use Magister;

binmode(STDOUT, ":utf8");


my %config;
Config::Simple->import_from("$FindBin::Bin/../config/EduTeams.cfg",\%config) or die("No config: $!");

# Magister object om magister dingen mee te doen
my $mag_session= Magister->new(
    'user'          => $config{'MAGISTER_USER'},
    'secret'        => $config{'MAGISTER_SECRET'},
    'endpoint'      => $config{'MAGISTER_URL'},
    'lesperiode'    => $config{'MAGISTER_LESPERIODE'}

);
my $docenten = $mag_session->getDocenten(); # $docenten is een HOH indexed op upn


while(my ($upn,$account) = each(%{$docenten})){
    printf("%s %20s %s\n",$account->{'stamnr'},$upn,$account->{'naam'});
}