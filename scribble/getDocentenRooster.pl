#! /usr/bin/env perl

use strict;
use warnings;
use v5.11;

use utf8;
use Getopt::Long;
use Data::Dumper;
use Config::Simple;
#use JSON qw(decode_json encode_json);
use FindBin;
use lib "$FindBin::Bin/../../magister-perl/lib";

use Magister;

binmode(STDOUT, ":utf8");

my $stamnr;
GetOptions (
    "stamnr=i" => \$stamnr
);

die "Geef een stamnr op" unless $stamnr;


my %config;
Config::Simple->import_from("$FindBin::Bin/../config/EduTeams.cfg",\%config) or die("No config: $!");

# Magister object om magister dingen mee te doen
my $mag_session= Magister->new(
    'user'          => $config{'MAGISTER_USER'},
    'secret'        => $config{'MAGISTER_SECRET'},
    'endpoint'      => $config{'MAGISTER_URL'},
    'lesperiode'    => $config{'MAGISTER_LESPERIODE'}

);

my $doc_vakken= $mag_session->getRooster($stamnr,"GetPersoneelGroepVakken");

while (my ($vak,$info) = each (%{$doc_vakken})){
        printf("%s %15s %5s %s\n",$stamnr,$vak, $info->{'code'},$info->{'vak'});

}