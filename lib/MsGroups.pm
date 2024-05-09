package MsGroups;

use v5.10;

use Moose;
use LWP::UserAgent;
use JSON;
use Data::Dumper;

extends 'MsGraph';

# Attributes {{{1
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
	my $self = shift;
	my $url = shift;
	my $groups = shift;
	my $result = $self->callAPI($url, 'GET');
	if ($result->is_success){
		my $reply =  decode_json($result->decoded_content);
		while (my ($i, $el) = each @{$$reply{'value'}}) {
			push @{$groups}, $el;
		}
		if ($$reply{'@odata.nextLink'}){
			do_fetch($self,$$reply{'@odata.nextLink'}, $groups);
		}
		#print Dumper $$reply{'value'};
	}else{
		print Dumper $result;
		die $result->status_line;
	}
} #	}}}

sub fetch_groups { #	{{{1
	my $self = shift;
	my @groups;
	my $url = $self->_get_graph_endpoint . "/v1.0/groups/?";
	if ($self->_get_filter){
		$url .= $self->_get_filter."&";
	}
	if ($self->_get_select){
		$url .= $self->_get_select."&";
		# Fetch only 5 tops for debugging
		#$url .= "&\$top=5";
	}
	#$url .= '$count=true';
	#say "Fetching $url";
	do_fetch($self,$url, \@groups);
	return  \@groups;
	
}#	}}}

__PACKAGE__->meta->make_immutable;
42;
# vim: set foldmethod=marker