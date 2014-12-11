use strict;
use warnings;

use Test::More tests => 5;

BEGIN {
    use_ok('Finance::Bitcoin::Feed');
}

my $feed = Finance::Bitcoin::Feed->new();
can_ok( $feed, 'run' );

isa_ok( $feed, 'Finance::Bitcoin::Feed' );
isa_ok( $feed, 'Mojo::EventEmitter' );
ok( $feed->has_subscribers('output') );

