#! /usr/bin/env perl

use v5.11;
use strict;
use warnings;
use DBI;
use Data::Dumper;


my $hash = {
        'b234568@ict-atlascollege.nl' => 'Test Leerling 2',
        'b234569@ict-atlascollege.nl' => 'Test Leerling 3',
        'b234567@ict-atlascollege.nl' => 'Test Leerling 1'
};

say "De hash is nu:";
print Dumper $hash;
my ($first) = keys %{$hash};
say "Eerste is: $first";
delete($hash->{$first});
say "De hash is nu:";
print Dumper $hash;