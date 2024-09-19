#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";


# use this block if you don't need middleware, and only have a single target Dancer app to run here
use insight;

insight->to_app;

=begin comment
# use this block if you want to include middleware such as Plack::Middleware::Deflater

use insight;
use Plack::Builder;

builder {
    enable 'Deflater';
    insight->to_app;
}

=end comment

=cut

=begin comment
# use this block if you want to mount several applications on different path

use insight;
use insight_admin;

use Plack::Builder;

builder {
    mount '/'      => insight->to_app;
    mount '/admin'      => insight_admin->to_app;
}

=end comment

=cut

