#! /usr/bin/env perl
#
# De education api heeft alleen app mogelijkheden om (bv) leerlingen op te vragen
# moet dus in een App met eduroster rechten
#
use strict;
use warnings;
use v5.11;

use Data::Dumper;
use Config::Simple;
use DBI;
use FindBin;
use JSON;
use lib "$FindBin::Bin/../../msgraph-perl/lib";

#use MsGroups;
use MsGroup;
#use Logger;
use MsUsers;

#
# Test config
my %config;
Config::Simple->import_from("$FindBin::Bin/../config/EduTeamsTest.cfg",\%config) or die("No config: $!");

my $class_object = MsGroup->new(
	'app_id'        => $config{'APP_ID'},
	'app_secret'    => $config{'APP_PASS'},
	'tenant_id'     => $config{'TENANT_ID'},
	'login_endpoint'=> $config{'LOGIN_ENDPOINT'},
	'graph_endpoint'=> $config{'GRAPH_ENDPOINT'},
#    'id'            => '4b4e5792-0263-44ba-a6ca-1892f814cd86', #xyz
#    'id'            => '5c47eea7-01b4-4842-85ce-c2da718e5793', #jaarlaag
    'id'            => 'e604e9d9-1dfe-4cac-89f1-deddaa571e94', #abc
);

my $payload = {
#            '@odata.id' => 'https://graph.microsoft.com/v1.0/education/users/2d6adf65-a0ce-43d5-a078-bdde1fea563c' #1
#            '@odata.id' => 'https://graph.microsoft.com/v1.0/education/users/ccccb41d-292e-4b2a-90e1-80df05f12dae' #2
#            '@odata.id' => 'https://graph.microsoft.com/v1.0/education/users/2c03712f-c3f3-4169-b3dc-de199398ba3e' #3
            '@odata.id' => 'https://graph.microsoft.com/v1.0/education/users/911e64b1-ee37-4ffd-9ac3-fc6c60fece6d' #4
          };

my $result = $class_object->class_add_student($payload);
print Dumper $result;
say $result->{'_rc'};

# {
#             'businessPhones' => [],
#             'officeLocation' => undef,
#             'showInAddressList' => undef,
#             'userPrincipalName' => 'b234560@ict-atlascollege.nl',
#             'userType' => 'Member',
#             'accountEnabled' => $VAR1->[0]{'passwordProfile'}{'forceChangePasswordNextSignIn'},
#             'usageLocation' => 'NL',
#             'surname' => undef,
#             'mail' => 'b234560@ict-atlascollege.nl',
#             'refreshTokensValidFromDateTime' => '2024-06-03T08:41:20Z',
#             'mailNickname' => 'b234560',
#             'id' => '911e64b1-ee37-4ffd-9ac3-fc6c60fece6d',
#             'displayName' => 'Test Leerling 4',
#             'department' => undef,
#             'givenName' => undef,
#             'onPremisesInfo' => {
#                                   'immutableId' => undef
#                                 },
#             'mobilePhone' => undef,
#             'passwordPolicies' => undef,
#             'preferredLanguage' => undef
#           },