package TestModperl::print_utf8_2;

# testing the utf8-encoded response via direct $r->print, which does the
# right thing without any extra provisions.
# see print_utf8.pm for tied STDOUT/perlio STDOUT, which requires extra work

use strict;
use warnings FATAL => 'all';

use Apache::RequestIO ();
use Apache::RequestRec ();

use Apache::Const -compile => 'OK';

sub handler {
    my $r = shift;

    $r->content_type('text/plain; charset=UTF-8');

    # must be non-$r->print(), so we go through the tied STDOUT
    # \x{263A} == :-)
    $r->print("\$r->print() just works \x{263A}");

    Apache::OK;
}

1;
__DATA__
SetHandler modperl
