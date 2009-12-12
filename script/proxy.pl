#!/usr/bin/env perl

use strict;
use warnings;

use CGI::Util qw(unescape);
use FindBin;
use HTTP::Proxy qw(:log);
use HTTP::Proxy::HeaderFilter::simple;

my $LOGFH;
#open($LOGFH, '>', "$FindBin::Bin/../tmp/proxy.log") or die;

main: {
    my $request_filter = HTTP::Proxy::HeaderFilter::simple->new(
        sub {
            my ( $self, $headers, $req ) = @_;
            my $logfh = $self->{_hphf_proxy}->logfh;
            print $logfh join(" ", $req->method, "($$)", $req->uri), "\n";
        }
    );

    my $proxy = HTTP::Proxy->new();
    $proxy->logmask( PROCESS | HEADERS | DATA );
    $proxy->push_filter( request => $request_filter );
    $proxy->logfh($LOGFH) if $LOGFH;
    $proxy->start;
}
