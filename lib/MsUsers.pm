package MsUsers;
#
# Do "things" with groups of Azure users
#

use v5.11;
use Moose;
use LWP::UserAgent;
use JSON;
use Data::Dumper;

extends 'MsGraph';

# Attributes {{{1
# }}}

sub users_fetch {
    my $self = shift;
    my @users;
    my @parameters;
    push(@parameters,$self->_get_filter) if ($self->_get_filter);
    push(@parameters,$self->_get_select) if ($self->_get_select);
    push(@parameters,'$count=true');
    
    my $url = $self->_get_graph_endpoint . "/v1.0/users/?". join( '&', @parameters);
    $self->fetch_list($url,\@users);
    return \@users;
}