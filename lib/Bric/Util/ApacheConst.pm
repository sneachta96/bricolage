package Bric::Util::ApacheConst;

=head1 NAME

Bric::Util::ApacheConst - wrapper around Apache 1 and 2 constants classes

=head1 VERSION

$LastChangedRevision$

=cut

require Bric; our $VERSION = Bric->VERSION;

=head1 DATE

$LastChangedDate: 2006-03-18 02:10:10 +0100 (Sat, 18 Mar 2006) $

=head1 SYNOPSIS

  use Bric::Util::ApacheConst qw(:common);
  use Bric::Util::ApacheConst qw(DECLINED OK);

=head1 DESCRIPTION

This package encapsulates the C<Apache::Constants> and C<Apache2::Const>
classes so that Bricolage doesn't have to care about which version of Apache
is running. It should work as a drop-in replacement for either of those
modules.

=head1 AUTHOR

Scott Lanning <slanning@cpan.org>

=cut

use strict;

use constant DECLINED                   => -1;

use constant HTTP_OK                    => 200;
use constant HTTP_CREATED               => 201;
use constant HTTP_ACCEPTED              => 202;
use constant HTTP_NO_CONTENT            => 204;

use constant HTTP_MOVED_PERMANENTLY     => 301;
use constant HTTP_MOVED_TEMPORARILY     => 302;
use constant HTTP_SEE_OTHER             => 303;
use constant HTTP_NOT_MODIFIED          => 304;

use constant HTTP_BAD_REQUEST           => 400;
use constant HTTP_UNAUTHORIZED          => 401;
use constant HTTP_FORBIDDEN             => 403;
use constant HTTP_NOT_FOUND             => 404;

use constant HTTP_INTERNAL_SERVER_ERROR => 500;
use constant HTTP_NOT_IMPLEMENTED       => 501;
use constant HTTP_BAD_GATEWAY           => 502;
use constant HTTP_SERVICE_UNAVAILABLE   => 503;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(
    DECLINED

    HTTP_OK
    HTTP_CREATED
    HTTP_ACCEPTED
    HTTP_NO_CONTENT

    HTTP_MOVED_TEMPORARILY
    HTTP_MOVED_PERMANENTLY
    HTTP_SEE_OTHER
    HTTP_NOT_MODIFIED

    HTTP_BAD_REQUEST
    HTTP_UNAUTHORIZED
    HTTP_FORBIDDEN
    HTTP_NOT_FOUND

    HTTP_INTERNAL_SERVER_ERROR
    HTTP_NOT_IMPLEMENTED
    HTTP_BAD_GATEWAY
    HTTP_SERVICE_UNAVAILABLE
);

1;