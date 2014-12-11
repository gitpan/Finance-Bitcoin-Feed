package Finance::Bitcoin::Feed;

use strict;
use Mojo::Base 'Mojo::EventEmitter';
use AnyEvent;
use Finance::Bitcoin::Feed::Site::Hitbtc;
use Finance::Bitcoin::Feed::Site::BtcChina;
use Finance::Bitcoin::Feed::Site::CoinSetter;

our $VERSION = '0.01';

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new();
    $self->on( 'output', sub { shift; say join " ", @_ } );
    return $self;
}

sub run {
    my $self = shift;
    my @sites;

    for my $site_class (
        qw(Finance::Bitcoin::Feed::Site::Hitbtc Finance::Bitcoin::Feed::Site::BtcChina Finance::Bitcoin::Feed::Site::CoinSetter)
      )
    {
        my $site = $site_class->new();
        $site->on( 'output', sub { shift, $self->emit( 'output', @_ ) } );
        $site->go;
        push @sites, $site;
    }

    AnyEvent->condvar->recv;
}

1;

__END__

=head1 NAME

Finance::Bitcoin::Feed - Collect bitcoin real-time price from many sites' streaming data source

=head1 SYNOPSIS

    use Finance::Bitcoin::Feed;

    #default output is to print to the stdout
    Finance::Bitcoin::Feed->new->run();
    # will print output to the stdout:
    # COINSETTER BTCUSD 123.00
    

    #or custom your stdout
    my $feed = Finance::Bitcoin::Feed->new;
    #first unsubscribe the event 'output'
    $feed->unsubscribe('output');
    #then listen on 'output' by your callback
    open  my $fh, ">out.txt";
    $fh->autoflush();
    $feed->on('output', sub{
       my ($self, $site, $currency, $price) = @_;
       print $fh "the price currency $currency on site $site is $price\n";
    });
    # let's go!
    $feed->run();

=head1 DESCRIPTION

L<Finance::Bitcoin::Feed> is a bitcoin realtime data source which collect real time data source from these sites:

=over 4

=item * L<HitBtc|https://hitbtc.com/api#socketio>

=item * L<BtcChina|http://btcchina.org/websocket-api-market-data-documentation-en>

=item * L<CoinSetter|https://www.coinsetter.com/api/websockets/last>

=back

The default output format to the stdout by this format:

   site_name TIMESTAMP CURRENCY price

For example:

   COINSETTER 1418173081724 BTCUSD 123.00

The unit of timestamp is ms.

You can custom your output by listen on the event L<output> and modify the data it received.

=head1 METHODS

This class inherits all methods from L<Mojo::EventEmitter>

=head1 EVENTS

This class inherits all events from L<Mojo::EventEmitter> and add the following new ones:

=head2 output

   #output to the stdout, the default action:
   $feed->on('output', sub { shift; say join " ", @_ } );

   #or you can clear this default action and add yours:
   $feed->unsubscribe('output');
   open  my $fh, ">out.txt";
   $feed->on('output', sub{
      my ($self, $site, $currency, $price) = @_;
      say $fh "the price of $site of currency $currency is $price"
   });


=head1 DEBUGGING

You can set the FINANCE_BITCOIN_FEED_DEBUG environment variable to get some advanced diagnostics information printed to STDERR.
And these modules use L<Mojo::UserAgent>, you can also open the MOJO_USERAGENT_DEBUG environment variable:

   FINANCE_BITCOIN_FEED_DEBUG=1
   MOJO_USERAGENT_DEBUG=1

=head1 SEE ALSO

L<Mojo::EventEmitter>

L<Finance::Bitcoin::Feed::Site::Hitbtc>

L<Finance::Bitcoin::Feed::Site::BtcChina>

L<Finance::Bitcoin::Feed::Site::CoinSetter>

=head1 AUTHOR

Chylli  C<< <chylli@binary.com> >>

=head1 COPYRIGHT

Copyright 2014- Binary.com
