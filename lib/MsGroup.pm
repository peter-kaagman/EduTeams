# Group, team or class methods
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


#
# Group related
#
sub group_delete {
	my $self = shift;
	my $url = $self->_get_graph_endpoint . "/v1.0/groups/".$self->_get_id;
	my $result = $self->callAPI($url,'DELETE');
	if ($result->is_success){
		return "deleted: " . $self->_get_id;
	}else{
		return $result;
	}
}

sub group_fetch_owners {
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
	$self->fetch_list($url, \@owners);
	return  \@owners;
	
}

sub group_fetch_members {
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
	$self->fetch_list($url, \@members); 
	return  \@members; # return a reference to the resul
	
}

sub group_addMember {
	my $self = shift;
	my $member_id = shift;
	my $is_owner = shift;
	say "Adding $member_id, Owner?: $is_owner"; 
	my $payload = {
		'@data.id' => "https://graph.microsoft.com/v1.0/directoryObjects/$member_id"
	};
	my $url = $self->_get_graph_endpoint . "/v1.0/groups/".$self->_get_id.'/members/$ref';
	my $result = $self->callAPI($url,'POST', $payload);
	return $result;
}

sub group_removeMember {
	my $self = shift;
	my $member_id = shift;
	my $payload = {	};
	my $url = $self->_get_graph_endpoint . '/v1.0/groups/'.$self->_get_id.'/members/'.$member_id.'/$ref';
	my $result = $self->callAPI($url, 'DELETE',$payload);
	return $result;
}

sub group_removeOwner {
	my $self = shift;
	my $owner_id = shift;
	my $payload = {	};
	my $url = $self->_get_graph_endpoint . '/v1.0/groups/'.$self->_get_id.'/owners/'.$owner_id.'/$ref';
	my $result = $self->callAPI($url, 'DELETE',$payload);
	# if ($result->is_success){
	# 	#cascade to member
	# 	$result = $self->removeMember($owner_id);
	# }
	return $result;
}

sub group_patch {
	my $self = shift;
	my $payload = shift;
	my $url = $self->_get_graph_endpoint . '/v1.0/groups/'.$self->_get_id;
	my $result = $self->callAPI($url, 'PATCH',$payload);
	if ($result->is_success){
		return "Ok";
	}else{
		return $result;
	}
}


#
# Team related
#
sub  team_members{
	my $self = shift;
	my @members;
	my $url = $self->_get_graph_endpoint . "/v1.0/teams/".$self->_get_id."/members/";
	#$url .= '?$Select=id,roles,'; # Ik kan geen select maken op userId, hoort niet bij het objecttype maar staat wel in het resultaat
	$self->fetch_list($url, \@members);

	return  \@members;
}

sub team_bulk_add_members {
	my $self = shift;
	my $payload = shift;
	my $url = $self->_get_graph_endpoint . "/v1.0/teams/".$self->_get_id."/members/add";
	say $url;
	my $result = $self->callAPI($url, 'POST', $payload);
	return $result;
}

sub  team_info{
	my $self = shift;
	my $info;
	my $url = $self->_get_graph_endpoint . "/v1.0/teams/".$self->_get_id;
	# add a selectif needed, have in fact a select => see object creation
	if ($self->_get_select){
		$url .= '?' . $self->_get_select;
	}
	#say "Fetching $url";
	$info = $self->callAPI($url, 'GET');
	return  decode_json($info->{'_content'});
}

sub team_channel_id {
	my $self = shift;
	my $name = shift;
	my $url = $self->_get_graph_endpoint . "/v1.0/teams/".$self->_get_id.'/channels';
	$url .= '/?$select=id,displayName';
	$url .= '&$filter=displayName eq \'General\'';
	#say $url;
	my $result = $self->callAPI($url, 'GET');
	return $result;
}

sub team_check_general {
	my $self = shift;
	# Het kan voorkomen dat er een probleem met SOP site voor het team.
	# Dit kun je na 5 minuten herstellen door een GetFilesFolder van General op te vragen.
	# Om dit te kunnen doen heb je wel het ID van het kanaal general nodig
	my $general_id = $self->team_channel_id('General');
	if ($general_id->is_success){
		my $url = $self->_get_graph_endpoint . "/v1.0/teams/".$self->_get_id;
		$url .= "/channels/".(decode_json($general_id->decoded_content))->{'value'}[0]->{'id'}."/filesFolder";
		my $result = $self->callAPI($url, 'GET');
		print Dumper $result;
		return $result;
	}else{
		return $general_id;
	}
}

sub team_remove_member{
	my $self = shift;
	my $id_2_remove = shift;
	my $url = $self->_get_graph_endpoint . "/v1.0/teams/".$self->_get_id."/members/$id_2_remove";
	say $url;
	my $result = $self->callAPI($url, 'DELETE');
	return $result;	
}
#
# Class related
#


__PACKAGE__->meta->make_immutable;
42;
# vim: set foldmethod=marker