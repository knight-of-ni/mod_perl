package TestAPI::server_rec;

use Apache::Test;

sub handler {
    my $r = shift;

    my $s = $r->server;

    plan $r, tests => 17;

    ok $s;

    ok $s->process;

    ok $s->next || 1;

    ok $s->server_admin;

    ok $s->server_hostname;

    ok $s->port || 1;

    ok $s->error_fname;

    #error_log;

    ok $s->loglevel;

    ok $s->is_virtual || 1;

    #module_config

    #lookup_defaults

    ok $s->addrs;

    ok $s->timeout;

    #keep_alive_timeout
    #keep_alive_max
    #keep_alive

    ok $s->path || 1;

    ok $s->names || 1;

    ok $s->wild_names || 1;

    ok $s->limit_req_line;

    ok $s->limit_req_fieldsize;

    ok $s->limit_req_fields;

    0;
}

1;
