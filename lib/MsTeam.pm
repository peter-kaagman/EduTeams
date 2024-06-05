package MsGroup;

use v5.10;

use Moose;
use LWP::UserAgent;
use JSON;
use Data::Dumper;

extends 'MsGraph';

# Attributes
has 'id' => (
	is => 'ro', 
	isa => 'Str', 
	required => '1',
	reader => '_get_id',
	writer => '_set_id',
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

sub do_fetch {
	my $self = shift;							# get a reference to the object
	my $url = shift;							# get the URL from the function call
	my $found = shift;							# get the array reference which holds the result
	my $result = $self->callAPI($url, 'GET');	# do_fetch calls callAPI to do the HTTP request
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
}

sub fetch_owners {
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
	
}

sub fetch_members {
	my $self = shift;							# get a reference to the object itself
	my @members;								# an array to hold the result
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
	do_fetch($self,$url, \@members); # actual fetch is done in do_fetch()
	return  \@members; # return a reference to the resul
	
}

sub addMember {
	my $self = shift;
	my $member_id = shift;
	my $is_owner = shift;
	say "Adding $member_id, Owner?: $is_owner"; 
	my $payload = {
		'@data.id' => "https://graph.microsoft.com/v1.0/directoryObjects/$member_id"
	};
	my $url = $self->_get_graph_endpoint . "/v1.0/groups/".$self->_get_id.'/members/$ref';
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
	return $result;

}

__PACKAGE__->meta->make_immutable;
42;
# vim: set foldmethod=marker