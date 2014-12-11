package Finance::Bitcoin::Feed::Site::CoinSetter;
use strict;
use Mojo::Base 'Finance::Bitcoin::Feed::Site';
use Mojo::UserAgent;

our $VERSION = '0.01';

# Module implementation here
has ws_url => 'https://plug.coinsetter.com:3000/socket.io/1';
has 'ua';
has 'site' => 'COINSETTER';

# this site need 2 handshakes
# 1. get session id by http GET method
# 2. generate a new url by adding session id to the old url
# 3. connect by socket id
sub go {
    my $self = shift;
    $self->SUPER::go;
    $self->ua( Mojo::UserAgent->new() );
    $self->debug('get handshake information');
    my $tx = $self->ua->get( $self->ws_url );
    unless ( $tx->success ) {
        my $err = $tx->error;
        $self->error("Connection error of Site CoinSetter: $err->{message}");
        $self->set_timeout;
        return;
    }

    # f_P7lQkhkg4JD5Xq0LCl:60:60:websocket,htmlfile,xhr-polling,jsonp-polling
    my ( $sid, $hb_timeout, $con_timeout, $transports ) = split /:/,
      $tx->res->text;

    my $url = $self->ws_url . "/websocket/$sid";
    $url =~ s/https/wss/;

    $self->debug( 'connecting...', $url );

    my $socket = $self->ua->websocket(
        $url => sub {
            my ( $ua, $tx ) = @_;
            $self->debug('connected!');
            unless ( $tx->is_websocket ) {
                $self->error("Site BtcChina WebSocket handshake failed!");

                # set timeout;
                $self->set_timeout;
                return;
            }
            bless $tx, 'Mojo::Transaction::WebSocket::ForCoinSetterSite';
            $tx->configure($self);
        }
    );
}

package Mojo::Transaction::WebSocket::ForCoinSetterSite;
use JSON;
use Scalar::Util qw(weaken);

use Mojo::Base 'Mojo::Transaction::WebSocket';

has 'owner';

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
                    $self->send(
                        { text => qq(5:::{"name":"$channel","args":[""]}) } );
                }
            );
        }
    );
    $self->emit( 'subscribe', 'last room' );
    $self->on(
        last => sub {
            my ( $self, $data ) = @_;
            $self->owner->emit(
                'data_out', $data->[0]{'timeStamp'},
                'BTCUSD',   $data->[0]{price}
            );
        }
    );
}

#socketio v0.9.6
sub parse {

    my ( $tx, $data ) = @_;

    my @packets = (
        'disconnect', 'connect', 'heartbeat', 'message',
        'json',       'event',   'ack',       'error',
        'noop'
    );

    my $regexp = qr/([^:]+):([0-9]+)?(\+)?:([^:]+)?:?([\s\S]*)?/;

    my @pieces = $data =~ $regexp;
    return {} unless @pieces;
    my $id = $pieces[1] || '';
    $data = $pieces[4] || '';
    my $packet = {
        type     => $packets[ $pieces[0] ],
        endpoint => $pieces[3] || '',
    };

    # whether we need to acknowledge the packet
    if ($id) {
        $packet->{id} = $id;
        if ( $pieces[3] ) {
            $packet->{ack} = 'data';
        }
        else {
            $packet->{ack} = 'true';
        }

    }

    # handle different packet types
    if ( $packet->{type} eq 'error' ) {

        # need do nothing now.
    }
    elsif ( $packet->{type} eq 'message' ) {
        $packet->{data} = $data || '';
    }

#"5:::{"name":"last","args":[{"price":367,"size":0.03,"exchangeId":"COINSETTER","timeStamp":1417382915802,"tickId":14667678802537,"volume":14.86,"volume24":102.43}]}"
    elsif ( $packet->{type} eq 'event' ) {
        eval {
            my $opts = decode_json($data);
            $packet->{name} = $opts->{name};
            $packet->{args} = $opts->{args};
        };
        $packet->{args} ||= [];

        $tx->emit( $packet->{name}, $packet->{args} );
    }
    elsif ( $packet->{type} eq 'json' ) {
        evel {
            $packet->{data} = decode_json($data);
        }
    }
    elsif ( $packet->{type} eq 'connect' ) {
        $packet->{qs} = $data || '';
        $tx->emit('setup');
    }
    elsif ( $packet->{type} eq 'ack' ) {

        # nothing to do now
        # because this site seems don't emit this packet.
    }
    elsif ( $packet->{type} eq 'heartbeat' ) {

        #send back the heartbeat
        $tx->send( { text => qq(2:::) } );
    }
    elsif ( $packet->{type} eq 'disconnect' ) {
        $tx->owner->debug('disconnected by server');
        $tx->owner->set_timeout();
    }
}

1;

__END__

=head1 NAME

Finance::Bitcoin::Feed::Site::CoinSetter -- the class that connect and fetch the bitcoin price data from site Coinsetter


=head1 SYNOPSIS

    use Finance::Bitcoin::Feed::Site::CoinSetter;
    use AnyEvent;

    my $obj = Finance::Bitcoin::Feed::Site::BitStamp->new();
    # listen on the event 'output' to get the adata
    $obj->on('output', sub { shift; say @_ });
    $obj->go();

    # dont forget this 
    AnyEvent->condvar->recv;
  
=head1 DESCRIPTION

Connect to site BitStamp by protocol socket.io v 0.9.6 and fetch the bitcoin price data.

=head1 EVENTS

This class inherits all events from L<Finance::Bitcoin::Feed::Site> and add some new ones.
The most important event is 'output'.

=head2 output

It will be emit by its parent class when print out the data. You can listen on this event to get the output.

=head2 subscribe

It will subscribe channel from the source site. You can subscribe more channels in the method L</configure>

=head1 SEE ALSO

L<Finance::Bitcoin::Feed::Site>

L<https://www.coinsetter.com/api>

L<Mojo::UserAgent>

L<socket.io-parser|https://github.com/Automattic/socket.io-parser>

=head1 AUTHOR

Chylli  C<< <chylli@binary.com> >>

