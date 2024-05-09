package MsGraph;


use v5.11;

use Moose;
use LWP::UserAgent;
use JSON;
use Data::Dumper;

# Attributes {{{1
has 'access_token'   => ( # {{{2
	is => 'rw', 
	isa => 'Str',
	reader => '_get_access_token',
	writer => '_set_access_token',
); #}}}
has 'app_id'         => ( # {{{2
	is => 'ro', 
	isa => 'Str', 
	required => '1',
	reader => '_get_app_id',
	writer => '_set_app_id',
); #}}}
has 'app_secret'     => ( # {{{2
	is => 'ro', 
	isa => 'Str', 
	required => '1',
	reader => '_get_app_secret',
	writer => '_set_app_secret',
); #}}}
has 'tenant_id'      => ( # {{{2
	is => 'ro', 
	isa => 'Str', 
	required => '1',
	reader => '_get_tenant_id',
	writer => '_set_tenant_id',
); #}}}
has 'login_endpoint' => ( # {{{2
	is => 'ro', 
	isa => 'Str', 
	required => '1',
	reader => '_get_login_endpoint',
	writer => '_set_login_endpoint',
); #}}}
has 'graph_endpoint' => ( # {{{2
	is => 'ro', 
	isa => 'Str', 
	required => '1',
	reader => '_get_graph_endpoint',
	writer => '_set_graph_endpoint',
); #}}}
has 'access_token'   => ( # {{{2
	is => 'rw', 
	isa => 'Str',
	reader => '_get_access_token',
	writer => '_set_access_token',
); #}}}
has 'consistencylevel'   => ( # {{{2
	is => 'rw', 
	isa => 'Str',
	default => "",
	reader => '_get_consistencylevel',
	writer => '_set_consistencylevel',
); #}}}
# }}}


sub BUILD{ #	{{{1
	my $self = shift;

	my $url = $self->_get_login_endpoint."/".$self->_get_tenant_id."/oauth2/token";
	my $ua = LWP::UserAgent->new(
		'send_te' => '0',
	);
	my $r = HTTP::Request->new(
		POST => $url,
		[
			'Accept'		=>	'*/*',
			'User-Agent'	=>	'Perl LWP',
			'Content-Type'	=>	'application/x-www-form-urlencoded'
		],
		"grant_type=client_credentials&".
		"client_id="     .$self->_get_app_id . 
		"&client_secret=". $self->_get_app_secret . 
		"&scope="        . $self->_get_graph_endpoint . "/.default" .
		"&resource="     . $self->_get_graph_endpoint,
	);

	my $result = $ua->request($r);

	if ($result->is_success){
		my $reply = decode_json($result->decoded_content);
		$self->_set_access_token($$reply{access_token});
	}else{
		#print Dumper $result;
		die $result->status_line;
	}
	#say "token: " . $self->_get_access_token;
	
	
}#	}}}

sub callAPI { # {{{1
	my $self = shift;					# Get a refence to the object itself
	my $url = shift;					# Get the URL from the function call
	my $verb = shift;					# Get the method form the function call
	my $ua = LWP::UserAgent->new(		# Create a LWP useragnent (beyond my scope, its a CPAN module)
		'send_te' => '0',	# not really sure what this does
	);
	# Create the header
	my @header =	[
		'Accept'        => '*/*',
		'Authorization' => "Bearer ".$self->_get_access_token,
		'User-Agent'    => 'curl/7.55.1',
		'Content-Type'  => 'application/json',
		'Consistencylevel' => $self->_get_consistencylevel
		];
	# Create the request
	my $r  = HTTP::Request->new(
		$verb => $url,
		@header,
	);	
	# Let the useragent make the request
	my $result = $ua->request($r);
	# return a reference to the result
	return $result;
} # }}}

__PACKAGE__->meta->make_immutable;
42;