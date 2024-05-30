#! /usr/bin/env perl

use v5.11;
use strict;
use warnings;

use JSON qw(encode_json decode_json);
use File::Slurp qw(read_file write_file);
use Data::Dumper;

my $json = read_file('./jaarlagen.json', { binmode => ':raw'});
my $jaarlagen = decode_json $json;

print Dumper $jaarlagen;
