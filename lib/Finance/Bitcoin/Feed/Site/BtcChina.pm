package Finance::Bitcoin::Feed::Site::BtcChina;
use strict;
use Mojo::Base 'Finance::Bitcoin::Feed::Site';
use Mojo::UserAgent;

our $VERSION = '0.02';

has ws_url => 'wss://websocket.btcchina.com/socket.io/?transport=websocket';
has 'ua';
has 'site' => 'BTCCHINA';

sub go {
    my $self = shift;
    $self->SUPER::go;

    $self->ua( Mojo::UserAgent->new() );
    $self->debug( 'connecting...', $self->ws_url );
    $self->ua->websocket(
        $self->ws_url => sub {
            my ( $ua, $tx ) = @_;
            $self->debug('connected!');
            unless ( $tx->is_websocket ) {
                $self->error("Site BtcChina WebSocket handshake failed!");

                # set timeout;
                $self->set_timeout;
                return;
            }

            bless $tx, 'Mojo::Transaction::WebSocket::ForBtcChina';
            $tx->configure($self);
        }
    );

}

package
	Mojo::Transaction::WebSocket::ForBtcChina;    # hidden from PAUSE

use JSON;
use Mojo::Base 'Mojo::Transaction::WebSocket';
use Scalar::Util qw(weaken);
has 'owner';
has 'ping_interval';
has 'ping_timeout';
has 'last_ping_at';
has 'last_pong_at';
has 'timer';

sub configure {
    my $self  = shift;
    my $owner = shift;
    $self->owner($owner);
    weaken( $self->{owner} );

    # call parse when receive text event
    $self->on(
        text => sub {
            my ( $self, $message ) = @_;
            $self->parse($message);
        }
    );

    ################################################
    # setup events
    $self->on(
        subscribe => sub {
            my ( $self, $channel ) = @_;
            $self->on(
                'setup',
                sub {
                    $self->send( { text => qq(42["subscribe","$channel"]) } );
                }
            );
        }
    );
    $self->emit( 'subscribe', 'marketdata_cnybtc' );
    $self->emit( 'subscribe', 'marketdata_cnyltc' );
    $self->emit( 'subscribe', 'marketdata_btcltc' );

    #receive trade vent
    $self->on(
        trade => sub {
            my ( $self, $data ) = @_;
            $self->owner->emit(
                'data_out',
                $data->{date} * 1000,    # the unit of timestamp is ms
                uc( $data->{market} ),
                $data->{price}
            );

        }
    );

    $self->on(
        'ping',
        sub {
            $self->send( { text => '2' } );
        }
    );

    # ping ping!
    my $timer = AnyEvent->timer(
        after    => 10,
        interval => 1,
        cb       => sub {
            if ( time() - $self->last_ping_at > $self->ping_interval / 1000 ) {
                $self->emit('ping');
                $self->last_ping_at( time() );
            }
        }
    );
    $self->timer($timer);

}

#socket.io v2.2.2
sub parse {
    my ( $self, $data ) = @_;
    $self->owner->last_activity_at( time() );
    return unless $data =~ /^\d+/;
    my ( $code, $body ) = $data =~ /^(\d+)(.*)$/;

    # connect, setup
    if ( $code == 0 ) {
        my $json_data = decode_json($body);

        #session_id useless ?

        $self->ping_interval( $json_data->{pingInterval} )
          if $json_data->{pingInterval};
        $self->ping_timeout( $json_data->{pingTimeout} )
          if $json_data->{pingTimeout};
        $self->last_pong_at( time() );
        $self->last_ping_at( time() );
        $self->emit('setup');
    }

    # pong
    elsif ( $code == 3 ) {
        $self->last_pong_at( time() );
    }

    #disconnect ? reconnect!
    elsif ( $code == 41 ) {
        $self->owner->debug('disconnected by server');

        #set timeout
        $self->owner->set_timeout();
    }
    elsif ( $code == 42 ) {
        my $json_data = decode_json($body);
        $self->emit( $json_data->[0], $json_data->[1] );
    }

}

1;

__END__

=head1 NAME

Finance::Bitcoin::Feed::Site::BtcChina -- the class that connect and fetch the bitcoin price data from site btcchina

=head1 SYNOPSIS

    use Finance::Bitcoin::Feed::Site::BtcChina;
    use AnyEvent;

    my $obj = Finance::Bitcoin::Feed::Site::BtcChina->new();
    # listen on the event 'output' to get the adata
    $obj->on('output', sub { shift; say @_ });
    $obj->go();

    # dont forget this
    AnyEvent->condvar->recv;

=head1 DESCRIPTION

Connect to site BitStamp by protocol socket.io v2.2.2 and fetch the bitcoin price data.

=head1 EVENTS

This class inherits all events from L<Finance::Bitcoin::Feed::Site> and add some new ones.
The most important event is 'output'.

=head2 output

It will be emit by its parent class when print out the data. You can listen on this event to get the output.

=head2 subscribe

It will subscribe channel from the source site. You can subscribe more channels in the method L</configure>

=head1 SEE ALSO

L<Finance::Bitcoin::Feed::Site>

L<btcchina api|http://btcchina.org/websocket-api-market-data-documentation-en>

L<socket.io-parse|https://github.com/Automattic/socket.io-parser>

L<Mojo::UserAgent>

=head1 AUTHOR

Chylli  C<< <chylli@binary.com> >>

