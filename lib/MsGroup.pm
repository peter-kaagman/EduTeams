package MsGroup;

use v5.10;

use Moose;
use LWP::UserAgent;
use JSON;
use Data::Dumper;

extends 'MsGraph';

# Attributes {{{1
has 'id' => ( # {{{2
	is => 'ro', 
	isa => 'Str', 
	required => '1',
	reader => '_get_id',
	writer => '_set_id',
); #}}}
has 'filter'         => ( # {{{2
	is => 'rw', 
	isa => 'Maybe[Str]', 
	required => '0',
	reader => '_get_filter',
	writer => '_set_filter',
); #}}}
has 'select'         => ( # {{{2
	is => 'rw', 
	isa => 'Maybe[Str]', 
	required => '0',
	reader => '_get_select',
	writer => '_set_select',
); #}}}
# }}}

sub do_fetch { # {{{1
	my $self = shift;							# get a reference to the object
	my $url = shift;							# get the URL from the function call
	my $found = shift;							# get the array reference which holds the result
	my $result = $self->callAPI($url, 'GET');	# do_getch calls callAPI to do the HTTP request
	# # debug problemen met members
	# say "\n\n\nZoeken naar: $url";
	# print Dumper $result;						# Dump the complete result
	# # end debug
	# Process if rc = 200
	if ($result->is_success){
		my $reply =  decode_json($result->decoded_content);
		while (my ($i, $el) = each @{$$reply{'value'}}) {
			push @{$found}, $el;
		}
		# do a recursive call if @odata.nextlink is there
		if ($$reply{'@odata.nextLink'}){
			do_fetch($self,$$reply{'@odata.nextLink'}, $found);
		}
		#print Dumper $$reply{'value'};
	}else{
		# Error handling
		print Dumper $result;
		die $result->status_line;
	}
} #	}}}

sub fetch_owners { #	{{{1
	my $self = shift;
	my @owners;
	my $url = $self->_get_graph_endpoint . "/v1.0/groups/".$self->_get_id."/owners/?";
	if ($self->_get_filter){
		$url .= $self->_get_filter."&";
	}
	if ($self->_get_select){
		$url .= $self->_get_select;
	}
	#say "Fetching $url";
	do_fetch($self,$url, \@owners);
	return  \@owners;
	
}#	}}}
sub fetch_members { #	{{{1
	my $self = shift;							# get a reference to the object itself
	my @members;								# an array to hold the result
	$self->_set_consistencylevel('eventual');	# setting consistencylevel (did this for debugging)
	# compose an URL
	my $url = $self->_get_graph_endpoint . "/v1.0/groups/".$self->_get_id."/members/?";
	# add a filter if needed (not doing any  filtering though)
	if ($self->_get_filter){
		$url .= $self->_get_filter."&";
	}
	# add a selectif needed, have in fact a select => see object creation
	if ($self->_get_select){
		$url .= $self->_get_select;
	}
	$url .= '&$count=true';		# adding $count just to be sure
	#say "Fetching $url";
	do_fetch($self,$url, \@members); # actual fetch is done in do_fetch()
	#print Dumper \@members; # dump the result for debugging
	return  \@members; # return a reference to the resul
	
}#	}}}

__PACKAGE__->meta->make_immutable;
42;
# vim: set foldmethod=marker