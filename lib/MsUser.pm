package MsUser;

use v5.11;
use Moose;
use LWP::UserAgent;
use JSON;
use Data::Dumper;

extends 'MsGraph';

# Attributes {{{1
# }}}




sub do_fetch { # {{{1
	my $self = shift;
	my $url = shift;
	my $user_info = shift;
	my $result = $self->callAPI($url, 'GET');
	if ($result->is_success){
	my $reply =  decode_json($result->decoded_content);
        foreach my $key (keys %{$reply->{'value'}[0]}){
            $$user_info{$key} = $reply->{'value'}[0]{$key};
        }
	}else{
		print Dumper $result;
		die $result->status_line;
	}
} #	}}}

sub fetch_upn_by_samAccountName { #	{{{1
	my $self = shift;
	my $user = shift;

	# ConsistencyLevel is required for filtering on samAccountName
	$self->_set_consistencylevel("eventual"); 
	my %user_info;
	my $url = $self->_get_graph_endpoint . "/v1.0/users";
	$url .= "?\$filter=onPremisesSamAccountName eq '".$user."'&\$count=true";
	do_fetch($self,$url, \%user_info);
	# Reset ConsistencyLevel
	$self->_set_consistencylevel(""); 
	return  $user_info{'userPrincipalName'};
	
}#	}}}

__PACKAGE__->meta->make_immutable;
42;
# vim: set foldmethod=marker