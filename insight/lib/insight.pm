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

get '/teamDetail/:teamnaam' => sub {
	my $teamNaam = route_parameters->get('teamnaam');
	# General info
	my $sth = database->prepare("Select rowid,* From magisterteam Where naam = '$teamNaam'");
	$sth->execute();
	my $teamInfo->{'magister'} = $sth->fetchrow_hashref();
	$sth->finish();
	#Azure
	my $qry = "Select rowid,* From azureteam Where secureName = '".$teamNaam."'";
	say $qry;
	$sth = database->prepare($qry);
	$sth->execute();
	$teamInfo->{'azure'} = $sth->fetchrow_hashref();
	$sth->finish();
	print Dumper $teamInfo;
	# Teachers
	$qry = 'Select users.* From magisterdocentenrooster ';
	$qry .= 'Left Join users On magisterdocentenrooster.docentid = users.rowid ';
	$qry .= "Where magisterdocentenrooster.teamid = $teamInfo->{'magister'}->{'rowid'}";
	$sth = database->prepare($qry);
	$sth->execute();
	$teamInfo->{'docenten'} = $sth->fetchall_hashref('naam');
	$sth->finish();
	# lEERLINGEN
	$qry = 'Select users.* From magisterleerlingenrooster ';
	$qry .= 'Left Join users On magisterleerlingenrooster.leerlingid = users.rowid ';
	$qry .= "Where magisterleerlingenrooster.teamid = $teamInfo->{'magister'}->{'rowid'}";
	$sth = database->prepare($qry);
	$sth->execute();
	$teamInfo->{'leerlingen'} = $sth->fetchall_hashref('naam');
	$sth->finish();

	print Dumper $teamInfo;

    template 'teamdetail' => { 
		'title' => "Insight: $teamNaam",
		'teamInfo' => $teamInfo 
	};
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

get '/api/getTeamList/:start/:page/:search' => sub {
	my $start = route_parameters->get('start');# || 0;
	my $page = route_parameters->get('page');# || 25;
	my $search = route_parameters->get('search');
	say "Route parameter $start $page $search";

	# Need an unpages rowCount;
	my $sth = database->prepare('Select count(rowid) as count From magisterteam');
	$sth->execute();
	my $rowCount = $sth->fetchrow_hashref();
	$rowCount->{'start'} = $start;
	my $reply->{'rowCount'} = $rowCount;
	$sth->finish;

	my $qry = 'Select magisterteam.rowid,magisterteam.naam';
	$qry .= "\n,(Select count(teamid) From magisterdocentenrooster Where teamid = magisterteam.rowid) as docenten ";
	$qry .= "\n,(Select count(teamid) From magisterleerlingenrooster Where teamid = magisterteam.rowid) as lln ";
	$qry .= "\nFrom magisterteam ";
	if ($search ne 'undefined'){
		$qry .= "\nWhere magisterteam.naam Like '%$search%'"
	}
	$qry .= "\nOrder By magisterteam.naam ";
	$qry .= "\nLimit $page Offset $start";
	say $qry;
	$sth = database->prepare($qry) or die $!;
	$sth->execute();
	my $teams = $sth->fetchall_hashref('naam');
	$reply->{'teams'} = $teams;
	$sth->finish();
	#print Dumper $reply;
	send_as JSON => $reply, { content_type => 'application/json; charset=UTF-8' }
};


true;
