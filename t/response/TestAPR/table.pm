package TestAPR::table;

use strict;
use warnings FATAL => 'all';

use Apache::Test;

use Apache::Const -compile => 'OK';
use APR::Table ();

my $filter_count;
my $TABLE_SIZE = 20;

sub handler {
    my $r = shift;

    plan $r, tests => 9;

    my $table = APR::Table::make($r->pool, 16);

    ok (UNIVERSAL::isa($table, 'APR::Table'));

    ok $table->set('foo','bar') || 1;

    ok $table->get('foo') eq 'bar';

    ok $table->unset('foo') || 1;

    ok not defined $table->get('foo');

    for (1..$TABLE_SIZE) {
        $table->set(chr($_+97), $_);
    }

    #Simple filtering
    $filter_count = 0;
    $table->do("my_filter");
    ok $filter_count == $TABLE_SIZE;

    #Filtering aborting in the middle
    $filter_count = 0;
    $table->do("my_filter_stop");
    ok $filter_count == int($TABLE_SIZE)/2;

    #Filtering with anon sub
    $filter_count=0;
    $table->do(sub {
        my ($key,$value) = @_;
        $filter_count++;
        unless ($key eq chr($value+97)) {
            die "arguments I recieved are bogus($key,$value)";
        }
        return 1;
    });

    ok $filter_count == $TABLE_SIZE;

    $filter_count = 0;
    $table->do("my_filter", "c", "b", "e");
    ok $filter_count == 3;

    Apache::OK;
}

sub my_filter {
    my ($key,$value) = @_;
    $filter_count++;
    unless ($key eq chr($value+97)) {
        die "arguments I recieved are bogus($key,$value)";
    }
    return 1;
}

sub my_filter_stop {
    my ($key,$value) = @_;
    $filter_count++;
    unless ($key eq chr($value+97)) {
        die "arguments I recieved are bogus($key,$value)";
    }
    return 0 if ($filter_count == int($TABLE_SIZE)/2);
    return 1;
}

1;
