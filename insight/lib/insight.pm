package insight;

use v5.11;
use Dancer2;
use Dancer2::Plugin::Auth::OAuth;
use Dancer2::Plugin::Database;
use DateTime;
use Data::Dumper;

our $VERSION = '0.1';

get '/' => sub {
    template 'teamlist' => { 
		'title' => 'insight-teamlist'
	};
};

get '/about' => sub {
    template 'about' => { 'title' => 'about insight' };
};



hook before => sub {
    my $session_data = session->read('oauth');
    my $provider = "azuread"; # Lower case of the authentication plugin used
	 
    my $now = DateTime->now->epoch;
     
    if (
    	(
		!defined $session_data || 
		!defined $session_data->{$provider} || 
		!defined $session_data->{$provider}{id_token}
	) && 
	request->path !~ m{^/auth}
    ) {
    	return forward "/auth/$provider";
    } elsif (
    		defined $session_data->{$provider}{refresh_token} && 
		defined $session_data->{$provider}{expires} && 
		$session_data->{$provider}{expires} < $now && 
		request->path !~ m{^/auth}
    ) {
    	return forward "/auth/$provider/refresh";
    }
	my $appData = session->read('appData');
	&_appInit unless $appData;
};

sub _appInit{
	say "We moeten een init doen";
	session->write('appData', 'dummy');
}

get '/api/getTeamList' => sub {
	my $qry = 'Select azureteam.rowid,azureteam.secureName';
	$qry .= ',(Select count(azureteam_id) From azuredocrooster Where azureteam_id = azureteam.rowid) as docenten ';
	$qry .= ',(Select count(azureteam_id) From azureleerlingrooster Where azureteam_id = azureteam.rowid) as lln ';
	$qry .= 'From azureteam ';
	$qry .= 'Limit 25 ';
	say "Query: $qry";
	my $sth = database->prepare($qry) or die $!;
	$sth->execute();
	my $teams = $sth->fetchall_hashref('secureName');
	print Dumper $teams;
	say "Query: $qry";
	send_as JSON => $teams, { content_type => 'application/json; charset=UTF-8' }
};


true;
