package MsUser;

use v5.11;
use Moose;
use LWP::UserAgent;
use JSON;
use Data::Dumper;

extends 'MsGraph';

# Attributes {{{1
# }}}

sub fetch_id_by_upn { #	{{{1
	my $self = shift;
	my $upn = shift;
	my %user_info;
	my $url = $self->_get_graph_endpoint . "/v1.0/users/$upn". '?$select=id';
	#say "Fetching id for $url";
	my $result = $self->callAPI($url, 'GET');
	if ($result->is_success){
		my $content = decode_json($result->{'_content'});
		return $content->{'id'};
	}else{
		#print Dumper $result;
		return 'onbekend';
	}
}#	}}}

__PACKAGE__->meta->make_immutable;
42;
# vim: set foldmethod=marker