package Magister;


use v5.11;

use Moose;
use LWP::UserAgent;
use JSON;
use Data::Dumper;
use Text::CSV qw( csv );
use Switch;

# Attributes {{{1
has 'access_token'   => ( # {{{2
	is => 'rw', 
	isa => 'Str',
	reader => '_get_access_token',
	writer => '_set_access_token',
); #}}}
has 'user'         => ( # {{{2
	is => 'ro', 
	isa => 'Str', 
	required => '1',
	reader => '_get_user',
	writer => '_set_user',
); #}}}
has 'secret'     => ( # {{{2
	is => 'ro', 
	isa => 'Str', 
	required => '1',
	reader => '_get_secret',
	writer => '_set_secret',
); #}}}
has 'endpoint' => ( # {{{2
	is => 'ro', 
	isa => 'Str', 
	required => '1',
	reader => '_get_endpoint',
	writer => '_set_endpoint',
); #}}}
has 'lesperiode' => ( # {{{2
	is => 'ro', 
	isa => 'Str', 
	required => '1',
	reader => '_get_lesperiode',
	writer => '_set_lesperiode',
); #}}}
# }}}


sub BUILD{ #	{{{1
	my $self = shift;
	my $url = $self->_get_endpoint;
    $url .= "/?Library=Algemeen&Function=Login";
    $url .= '&Username='.$self->_get_user;
    $url .= '&Password='.$self->_get_secret;

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
	);

	my $result = $ua->request($r);
	#print Dumper $result;
	if ($result->is_success){
		if ($result->content =~ /.+SessionToken">(.+)<\/td>.+/) {
			$self->_set_access_token($1);
		}else{
			$result->content =~  /.+ResultMessage">(.+)<\/td>.+/;
			die "Error getting token: $1";
		}
	}else{
		die $result->status_line;
	}
}#	}}}

sub callAPI { # {{{1
	#my $self = shift;
	my $url = shift;
	my $ua = LWP::UserAgent->new(
		'send_te' => '0',
	);
	my @header =	[
		'Accept'        => '*/*',
		'User-Agent'    => 'Perl LWP',
		];
	my $r  = HTTP::Request->new(
		GET => $url,
		@header,
	);	
	my $result = $ua->request($r);
	return $result;
} # }}}

#https://[url]/?library=ADFuncties&function=GetActiveEmpoyees&SessionToken=[SessionToken] &Type=[HTML/XML/CSV/TAB] <= niet langer in gebruik
#
# GetActiveEmpoyees (staat daar nu echt een tikfout in?) is niet geschikt voor het ophalen van docenten. Hierin ontbreekt informatie om een koppeling met Azure te kunnen maken.
# In plaats daarvan wordt gebruik gemaakt van een query "SDS-Medewerker". Hierin staat het werk email adres wat gebruikt kan worden als UPN.
#
#https://[url]/?library=Data&function=GetData&SessionToken=[SessionToken]&Layout=[Layout]&Parameters=[Parameters] &Type=[HTML/XML/CSV/TAB]
sub getDocenten {
	my $self = shift;
	my $url = $self->_get_endpoint;
	#$url .= "/?library=ADFuncties&function=GetActiveEmpoyees&Type=CSV&SessionToken=".$self->_get_access_token;
	$url .= "/?library=Data&function=GetData&Layout=SDS-Medewerker&Type=CSV&SessionToken=".$self->_get_access_token;
	my $result = callAPI($url);
	if ($result->is_success){
		my $docenten = csv(
			in => \$result->content,
			headers => "auto",
			sep_char => ";",
			encoding => "UTF-8"
		);
		my $reply;
		foreach my $docent (@$docenten){
			#print Dumper $docent;
			#13 hash omgeboud naar index op upn
			# Uit dienst wordt aangegeven door een sterrje voor de 3-letter code
			# Email_werk zou de UPN moeten zijn
			my $upn = lc($docent->{'Email_werk'});
			$reply->{$upn}->{'naam'}	= $docent->{'Volledige_naam'};
			$reply->{$upn}->{'stamnr'}	= $docent->{"\x{feff}Stamnr"};
		};	
		return $reply;
	}else{
		print Dumper $result;
	}
}

#https://[url]/?library=ADFuncties&function=GetActiveStudents&SessionToken=[SessionToken]&LesPeriode=[LesPeriode] &Type=[HTML/XML/CSV/TAB]
#ToDo Hier wordt het koppelveld gemaakt tussen Magister en Azure, deze met de tijd configureerbaar maken
sub getLeerlingen {
	my $self = shift;
	my $url = $self->_get_endpoint;
	$url .= "/?library=ADFuncties&function=GetActiveStudents&Type=CSV&SessionToken=".$self->_get_access_token;
	$url .= "&LesPeriode=".$self->_get_lesperiode;
	my $result = callAPI($url);
	my $leerlingen = csv(
		in => \$result->content,
		headers => "auto",
		sep_char => ";",
		encoding => "UTF-8"
	);
	my $reply;
	foreach my $lln (@$leerlingen){
		#print Dumper $lln;
		# Fabriceer een UPN, deze kan best ongeldig zijn.
		my $upn = lc($lln->{'Loginaccount.Naam'}).'@atlascollege.nl';
		$reply->{$upn}->{'naam'}	= $lln->{'Volledige_naam'};
		$reply->{$upn}->{'studie'}	= $lln->{'Studie'};
		$reply->{$upn}->{'stamnr'}	= $lln->{"\x{feff}stamnr_str"};
		$reply->{$upn}->{'klas'}	= $lln->{'Klas'};
		# Rest van de data wordt nergens gebruikt
		#$reply->{$lln->{"\x{feff}stamnr_str"}}->{'naam'} 		= $lln->{'Volledige_naam'};
		#$reply->{$lln->{"\x{feff}stamnr_str"}}->{'studie'} 	= $lln->{'Studie'};
		#$reply->{$lln->{"\x{feff}stamnr_str"}}->{'b_nummer'} 	= lc($lln->{'Loginaccount.Naam'});
		#$reply->{$lln->{"\x{feff}stamnr_str"}}->{'locatie'} 	= $lln->{'Administratieve_eenheid.Omschrijving'};
		# $reply->{$docent->{"\x{feff}stamnr_str"}}->{'inlogcode'} 	= lc($docent->{'Code'});
		# $reply->{$docent->{"\x{feff}stamnr_str"}}->{'locatie'}		= $docent->{'Administratieve_eenheid.Omschrijving'};
		# $reply->{$docent->{"\x{feff}stamnr_str"}}->{'rol'} 			= $docent->{'Functie.Omschr'};
	};	
	return $reply;
}

#https://[url]/?library=ADFuncties&function=GetPersoneelGroepVakken&SessionToken=[SessionToken]&LesPeriode=[LesPeriode]&StamNr=[StamNr] &Type=[HTML/XML/CSV/TAB]
#https://[url]/?library=ADFuncties&function=GetLeerlingGroepen&SessionToken=[SessionToken]&LesPeriode=[LesPeriode]&StamNr=[StamNr] &Type=[HTML/XML/CSV/TAB]
#https://[url]/?library=ADFuncties&function=GetLeerlingVakken&SessionToken=[SessionToken]&LesPeriode=[LesPeriode]&StamNr=[StamNr] &Type=[HTML/XML/CSV/TAB]
sub getRooster{
	my $self = shift;
	my $stamnr = shift;
	my $function = shift;
	my $url = $self->_get_endpoint;
	$url .= "/?library=ADFuncties";
	$url .= "&function=".$function;
	$url .= "&Type=CSV&SessionToken=".$self->_get_access_token;
	$url .= "&LesPeriode=".$self->_get_lesperiode;
	$url .= "&StamNr=".$stamnr;
	my $result = callAPI($url);
	my $groepvakken = csv(
		in => \$result->content,
		headers => "auto",
		sep_char => ";",
		encoding => "UTF-8"
	);
	my $reply;
	foreach my $vak (@$groepvakken){
		# Structuur is afhankelijk van de vraag
		switch($function){
			case "GetLeerlingGroepen" {
				$reply->{$vak->{'groep'}}->{'groepid'}	=  $vak->{'Lesgroep'};
			}
			case "GetLeerlingVakken" {
				#print Dumper $vak;
				$reply->{$vak->{'Vak'}}	=  'blaat';
			}
			case  "GetPersoneelGroepVakken" {
				$reply->{$vak->{'Klas'}}->{'vak'} 	=  $vak->{'Vak.Omschrijving'};
				$reply->{$vak->{'Klas'}}->{'code'}	=  $vak->{'Vak.Vakcode'};
			}
		}
	}
	return $reply;
}


__PACKAGE__->meta->make_immutable;
42;