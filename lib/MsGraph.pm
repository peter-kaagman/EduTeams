package MsGraph;


use v5.11;

use Moose;
use LWP::UserAgent;
use JSON;
use Time::Piece;
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
has 'filter'         => (
	is => 'rw', 
	isa => 'Maybe[Str]', 
	required => '0',
	reader => '_get_filter',
	writer => '_set_filter',
);
has 'select'         => ( 
	is => 'rw', 
	isa => 'Maybe[Str]', 
	required => '0',
	reader => '_get_select',
	writer => '_set_select',
); 
# issue involved: https://github.com/peter-kaagman/EduTeams/issues/3
has 'token_expires'   => ( # {{{2
	is => 'rw', 
	isa => 'Str',
	reader => '_get_token_expires',
	writer => '_set_token_expires',
); #}}}
has 'consistencylevel'   => ( # {{{2
	is => 'rw', 
	isa => 'Str',
	default => "",
	reader => '_get_consistencylevel',
	writer => '_set_consistencylevel',
); #}}}
# }}}

sub  getToken {
	my $self = shift;
	#say "Token ophalen";
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
		#"&scope="        .  "offline_access" . # Dit zou een refresh token op moeten leveren in de reply maar werkt niet
		"&resource="     . $self->_get_graph_endpoint,
	);

	my $result = $ua->request($r);

	if ($result->is_success){
		my $reply = decode_json($result->decoded_content);
		#print Dumper $reply;
		$self->_set_access_token($reply->{'access_token'});
		$self->_set_token_expires($reply->{'expires_on'});
	}else{
		print Dumper $result;
		die $result->status_line;
	}
	#print Dumper $self;
	#say "Token is nu: ". $self->_get_access_token;
}


sub BUILD{ #	{{{1
	my $self = shift;
	# Alleen een token ophalen als die er nog niet is
	if (! $self->_get_access_token){
		$self->getToken;
	}
	#say "token: " . $self->_get_access_token;
	
	
}#	}}}

sub callAPI { # {{{1
	my $self = shift;					# Get a refence to the object itself
	my $url = shift;					# Get the URL from the function call
	my $verb = shift;					# Get the method form the function call
	my $payload = shift;

	# Moeten we het token refreshen?
	# Token is default een uur geldig, na 30 minuten verversen
	if ( ($self->_get_token_expires - localtime->epoch) < 1800){
		$self->getToken;
	}

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
	# Create the request
	my $r;
	# Als het een POST/PATCH/PUT/DELETE is dan moet er payload zijn
	if ( 
		(uc($verb) eq 'POST' ) || 
		(uc($verb) eq 'PATCH' ) || 
		(uc($verb) eq 'PUT' ) || 
		(uc($verb) eq 'DELETE' ) 
	){
		my $data;
		if ($payload){
			$data = encode_json($payload);
		}else{
			$data = '{}';
		}
		$r = HTTP::Request->new(
			$verb => $url,
			$header,
			$data
		);
	}else{  
		$r = HTTP::Request->new(
			$verb => $url,
			$header,
		);	
	}
	# Let the useragent make the request
	#print Dumper $r;
	my $result = $ua->request($r);
	#print Dumper $result;
	#return $result->decoded_content;
	return $result;
} # }}}

sub fetch_list {
	my $self = shift;							# get a reference to the object
	my $url = shift;							# get the URL from the function call
	my $found = shift;							# get the array reference which holds the result
	my $result = $self->callAPI($url, 'GET');	# do_fetch calls callAPI to do the HTTP request
	#print Dumper $result;
	# Process if rc = 200
	if ($result->is_success){
		my $reply =  decode_json($result->decoded_content);
		while (my ($i, $el) = each @{$$reply{'value'}}) {
			push @{$found}, $el;
		}
		# do a recursive call if @odata.nextlink is there
		if ($$reply{'@odata.nextLink'}){
			$self->fetch_list($$reply{'@odata.nextLink'}, $found);
		}
		#print Dumper $$reply{'value'};
		#say "returning";
	}else{
		# Error handling
		print Dumper $result;
		return $result->status_line;
	}
	#print Dumper $found;
}


__PACKAGE__->meta->make_immutable;
42;