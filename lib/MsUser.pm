package MsUser;

use v5.11;
use Moose;
use LWP::UserAgent;
use JSON;
use Data::Dumper;

extends 'MsGraph';

# Attributes {{{1
# }}}




# sub do_fetch { # {{{1
# 	my $self = shift;
# 	my $url = shift;
# 	my $user_info = shift;
# 	my $result = $self->callAPI($url, 'GET');
# 	if ($result->is_success){
# 		my $reply =  decode_json($result->decoded_content);
# 		print Dumper $reply;
#         foreach my $key (keys %{$reply->{'value'}[0]}){
#             $$user_info{$key} = $reply->{'value'}[0]{$key};
#         }
# 	}else{
# 		print Dumper $result;
# 		die $result->status_line;
# 	}
# } #	}}}

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