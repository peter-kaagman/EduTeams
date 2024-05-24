package MsGroups;

use v5.10;

use Moose;
use LWP::UserAgent;
use JSON;
use Data::Dumper;
#use Mojo::JSON qw(decode_json encode_json);

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

sub create_group {
	my $self = shift;
	my $group_info = shift;
	# callAPI uit msGraph.pm voldoet in dit geval niet
	# die is niet voorzien om data te sturen
	# wellicht tot een nieuwe generieke methode komen voor dit doel of aanpassen?
	my $url = $self->_get_graph_endpoint . "/v1.0/groups";
	my $ua = LWP::UserAgent->new(		# Create a LWP useragnent (beyond my scope, its a CPAN module)
		'timeout' => '180',
	);
	# Create the header
	my $header =	[
		'Accept'        => '*/*',
		'Authorization' => "Bearer ".$self->_get_access_token,
		'Content-Type'  => 'application/json',
		'Consistencylevel' => $self->_get_consistencylevel
	];
	my $data = encode_json($group_info);
	# Create the request
	my $r  = HTTP::Request->new(
		'POST',
		$url,
		$header,
		$data,
	);	
	#print Dumper $r;
	# Let the useragent make the request
	my $result = $ua->request($r);
	return $result;

}
__PACKAGE__->meta->make_immutable;
42;
# # vim: set foldmethod=marker
# sub callAPI { # {{{1
# 	my $self = shift;					# Get a refence to the object itself
# 	my $url = shift;					# Get the URL from the function call
# 	my $verb = shift;					# Get the method form the function call
# 	my $try = shift || 1;
# 	my $ua = LWP::UserAgent->new(		# Create a LWP useragnent (beyond my scope, its a CPAN module)
# 		'timeout' => '180',
# 	);
# 	# Create the header
# 	my @header =	[
# 		'Accept'        => '*/*',
# 		'Authorization' => "Bearer ".$self->_get_access_token,
# 		'User-Agent'    => 'curl/7.55.1',
# 		'Content-Type'  => 'application/json',
# 		'Consistencylevel' => $self->_get_consistencylevel
# 		];
# 	# Create the request
# 	my $r  = HTTP::Request->new(
# 		$verb => $url,
# 		@header,
# 	);	
# 	# Let the useragent make the request
# 	my $result = $ua->request($r);
# 	# adding error handling
# 	# rc 429 is throttling
# 	if (! $result->{"_rc"} eq "200"){
# 		print Dumper $result;
# 	}
# 	return $result;
# } # }}}
