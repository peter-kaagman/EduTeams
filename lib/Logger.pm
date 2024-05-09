#! /usr/bin/perl -W

package Logger;

use strict;
use warnings;
use v5.11;

use Moose;
use POSIX qw(strftime);

has 'filename' => (is => 'ro', isa => 'Str');
has 'verbose' => (is => 'ro', isa=> 'Bool', 'default' => '0');

sub make_log{
	my $self = shift;
	my $entry = shift;
	my $now = time();
	my $ts = strftime('%Y-%m-%dT%H:%M:%S', localtime($now));
	open(FH, '>>', $self->filename) or die("Could not open logfile ".$self->filename.": $!");
	print FH "$ts: $entry\n";
	close(FH);
	if ($self->verbose){
		print "$entry\n";
	}

}

__PACKAGE__->meta->make_immutable;
42;