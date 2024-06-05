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

sub add_member {
	my $self = shift;
	my $group_id = shift;
	my $member_id = shift;
	my $member = {
		'@odata.id' => "https://graph.microsoft.com/v1.0/directoryObjects/$member_id"
	};
	my $url = $self->_get_graph_endpoint . '/v1.0/groups/'.$group_id.'/members/$ref';
	my $ua = LWP::UserAgent->new(		# Create a LWP useragnent (beyond my scope, its a CPAN module)
		'timeout' => '180',
	);
	# Create the header
	my $header =	[
		'Accept'        => '*/*',
		'Authorization' => "Bearer ".$self->_get_access_token,
		'Content-Type'  => 'application/json',
	];
	my $data = encode_json($member);
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
	if ($result->is_success){
		sleep(1); #vlgs de doc ff wachten na het toevoegen van een gebruiker
		return "Ok";
	}else{
		return "RC $result->{'_rc'}: $result->{'_content'}";
	}
}
sub add_owner {
	my $self = shift;
	my $group_id = shift;
	my $owner_id = shift;
	# Een owner moet ook member zijn
	my $member_reply = $self->add_member($group_id,$owner_id);
	if ( $member_reply eq 'Ok'){
		my $owner = {
			'@odata.id' => "https://graph.microsoft.com/v1.0/directoryObjects/$owner_id"
		};
		my $url = $self->_get_graph_endpoint . '/v1.0/groups/'.$group_id.'/owners/$ref';
		my $ua = LWP::UserAgent->new(		# Create a LWP useragnent (beyond my scope, its a CPAN module)
			'timeout' => '180',
		);
		# Create the header
		my $header =	[
			'Accept'        => '*/*',
			'Authorization' => "Bearer ".$self->_get_access_token,
			'Content-Type'  => 'application/json',
		];
		my $data = encode_json($owner);
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
		if ($result->is_success){
			sleep(1); #vlgs de doc ff wachten na het toevoegen van een gebruiker
			return "Ok";
		}else{
			return "RC $result->{'_rc'}: $result->{'_content'}";
		}
	}else{
		return "Error adding owner as member RC $member_reply->{'_rc'}: $member_reply->{'_content'}";
	}
}

sub team_from_group{
	my $self = shift;
	my $group_id = shift;
	say "Groep $group_id wordt een team";
	my $payload = {
		'template@odata.bind' => "https://graph.microsoft.com/v1.0/teamsTemplates('educationClass')",
  		'group@odata.bind' => "https://graph.microsoft.com/v1.0/groups('$group_id')"

	};
	my $url = $self->_get_graph_endpoint . '/v1.0/teams';
	my $ua = LWP::UserAgent->new(		# Create a LWP useragnent (beyond my scope, its a CPAN module)
		'timeout' => '180',
	);
	# Create the header
	my $header =	[
		'Accept'        => '*/*',
		'Authorization' => "Bearer ".$self->_get_access_token,
		'Content-Type'  => 'application/json',
	];
	my $data = encode_json($payload);
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
	print Dumper $result;
	if ($result->is_success){
		return "Ok";
	}else{
		return "RC $result->{'_rc'}: $result->{'_content'}";
	}
}


sub create_class {
	my $self = shift;
	my $class_info = shift;
	my $url = $self->_get_graph_endpoint . "/v1.0/education/classes";
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
	my $payload = encode_json($class_info);
	# Create the request
	my $r  = HTTP::Request->new(
		'POST',
		$url,
		$header,
		$payload,
	);	
	print Dumper $r;
	# Let the useragent make the request
	my $result = $ua->request($r);
	return $result;

}

sub archive_class {
	# Om gegevens verlies te voorkomen worden teams niet verwijdert maar gearchiveerd.
	my $self = shift;
	my $team - shift;
	say "$team archiveren";
}


__PACKAGE__->meta->make_immutable;
42;
