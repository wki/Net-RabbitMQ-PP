package Net::RabbitMQ::PP;
use Moose;
use Net::RabbitMQ::PP::Network;
use Net::RabbitMQ::PP::FrameIO;
use Net::RabbitMQ::PP::Channel;
use Net::RabbitMQ::PP::Queue;
use Net::RabbitMQ::PP::Exchange;
use Try::Tiny;
use Carp;
use namespace::autoclean;

with 'Net::RabbitMQ::PP::Role::FrameIO',
     'Net::RabbitMQ::PP::Role::Debug';

# cat share/amqp0-9-1.xml  | egrep '<(class|method|field)' | less

=head1 NAME

Net::RabbitMQ::PP - a pure perl RabbitMQ binding

=head1 SYNOPSIS

    use Net::RabbitMQ::PP;
    
    my $broker = Net::RabbitMQ::PP->new(
        # default values; omit if you do not need changes
        host         => 'localhost',
        port         => 5672,
        timeout      => 0,
        virtual_host => '/',
        user         => 'guest',
        password     => 'guest',
        debug        => 0,
    );
    
    # work with exchanges
    my $exchange = $broker->exchange('thumbnail');
    $exchange->declare;
    $exchange->delete
    
    # work with queues
    my $queue = $broker->queue('thumbnail');
    $queue->declare;
    $queue->bind(exchange => 'thumbnail', routing_key => '#.render');
    $queue->unbind(exchange => 'thumbnail', routing_key => '#.render');
    $queue->purge;
    $queue->delete;
    
    # open a channel for further operations; returns a Channel object
    my $channel = $broker->channel(1);
    
    # a producer
    $channel->publish(
        exchange    => 'send_mail',
        routing_key => 'foo.bar',
        data        => 'Dear Reader, ...',
    );
    
    # a consumer
    $channel->consume(queue => 'send_mail', no_ack => 0);
    while (my $message = $channel->receive) {
        say 'received:', $message->body;
        
        $message->ack;
    }
    
    # peek if a message is available. immediately returns, maybe undef
    my $message = $channel->get;
    
    $broker->disconnect;

=head1 DESCRIPTION

TODO: write something

=head1 ATTRIBUTES

=cut

=head1 ATTRIBUTES

=cut

has host => (
    is      => 'ro',
    isa     => 'Str',
    default => 'localhost',
);

has port => (
    is      => 'ro',
    isa     => 'Int',
    default => 5672,
);

has timeout => (
    is      => 'ro',
    isa     => 'Int',
    default => 0,
);

has virtual_host => (
    is      => 'ro',
    isa     => 'Str',
    default => '/',
);

has user => (
    is      => 'ro',
    isa     => 'Str',
    default => 'guest',
);

has password => (
    is      => 'ro',
    isa     => 'Str',
    default => 'guest',
);

has is_connected => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
);

has network => (
    is         => 'ro',
    isa        => 'Net::RabbitMQ::PP::Network',
    lazy_build => 1,
);

sub _build_network {
    my $self = shift;
    
    return Net::RabbitMQ::PP::Network->new(
        host    => $self->host,
        port    => $self->port,
        timeout => $self->timeout,
        debug   => $self->debug,
    );
}

# frame_io defined by role FrameIO
sub _build_frame_io {
    my $self = shift;
    
    return Net::RabbitMQ::PP::FrameIO->new(
        network => $self->network,
        debug   => $self->debug,
    );
}

has _opened_channels => (
    traits  => ['Hash'],
    is      => 'rw',
    isa     => 'HashRef',
    default => sub { +{} },
    handles => {
        _clear_opened_channels => 'clear',
        _mark_channel_closed   => 'delete',
    }
);

has frame_max => (
    is        => 'rw',
    isa       => 'Int',
    predicate => 'has_frame_max',
);

# sub DEMOLISH {}

=head2 connect

connect with the RabbitMQ server

=cut

sub connect {
    my $self = shift;
    
    $self->write_greeting;

    $self->read_frame(0, 'Connection::Start');
    $self->write_frame(
        0, 'Connection::StartOk',
        client_properties => {
            platform    => 'Perl',
            product     => 'Net-RabbitMQ-PP',
            version     => '0.01',
        },
        mechanism => 'AMQPLAIN',
        response => {
            LOGIN    => $self->user,
            PASSWORD => $self->password,
        },
        locale => 'en_US',
    );

    my $tune_info = $self->read_frame(0, 'Connection::Tune');
    
    $self->print_debug(1, 'Tune: channel_max = ', $tune_info->method_frame->channel_max);
    $self->print_debug(1, 'Tune: frame_max   = ', $tune_info->method_frame->frame_max);
    $self->print_debug(1, 'Tune: heartbeat   = ', $tune_info->method_frame->heartbeat);
    
    if ($self->has_frame_max) {
        $self->frame_max($tune_info->method_frame->frame_max)
            if $self->frame_max > $tune_info->method_frame->frame_max;
    } else {
        $self->frame_max($tune_info->method_frame->frame_max);
    }
    
    $self->write_frame(
        0, 'Connection::TuneOk',
        channel_max => $tune_info->method_frame->channel_max,
        frame_max   => $tune_info->method_frame->frame_max,
        heartbeat   => $tune_info->method_frame->heartbeat,
    );

    my $connection_open = $self->write_frame(
        0, 'Connection::Open',
        virtual_host => $self->virtual_host,
        capabilities => '',
        insist       => 1,
    );
    $self->read_frame(0, 'Connection::OpenOk');
    
    $self->is_connected(1);
}

=head2 ensure_connected

connect unless already done

=cut

sub ensure_connected {
    my $self = shift;
    
    $self->connect if !$self->is_connected;
}

before [qw(
    channel
    queue exchange
)] => sub { $_[0]->ensure_connected };

=head2 disconnect

disconnect from the RabbitMQ server

=cut

sub disconnect {
    my $self = shift;
    
    try {
        $self->write_frame(0, 'Connection::Close');
        $self->read_frame(0, 'Connection::CloseOk');
    };
    
    $self->clear_frame_io;
    $self->clear_network;
    $self->_clear_opened_channels;
    
    $self->is_connected(0);
}

=head2 channel ( $nr )

opens a channel unless already open and returns the Channel object for the
given channel_nr

=cut

sub channel {
    my $self = shift;
    my $channel_nr = shift
        or croak 'need channel nr to open';
    
    return $self->_opened_channels->{$channel_nr} //= $self->_open_channel($channel_nr);
}

sub _open_channel {
    my $self = shift;
    my $channel_nr = shift
        or croak 'need channel nr to open';
    
    $self->write_frame($channel_nr, 'Channel::Open');
    $self->read_frame($channel_nr, 'Channel::OpenOk');
    
    return Net::RabbitMQ::PP::Channel->new(
        broker     => $self,
        channel_nr => $channel_nr,
    );
}

=head2 queue ( $name, %opts )

returns a Net::RabbitMQ::PP::Queue object for further operations with the
given queue.

=cut

sub queue {
    my $self = shift;
    my $name = shift
        or croak 'queue name needed for accessing a queue';
    
    return Net::RabbitMQ::PP::Queue->new(
        broker     => $self,
        channel_nr => $self->channel(1)->channel_nr, # ensures channel is open
        name       => $name,
        @_
    );
}

=head2 exchange ( $name, %opts )

returns a Net::RabbitMQ::PP::Exchange object for further operations with the
given exchange.

=cut

sub exchange {
    my $self = shift;
    my $name = shift
        or croak 'exchange name needed for accessing an exchange';

    return Net::RabbitMQ::PP::Exchange->new(
        broker     => $self,
        channel_nr => $self->channel(1)->channel_nr, # ensures channel is open
        name       => $name,
        @_
    );
}

=head1 AUTHOR

Wolfgang Kinkeldei, E<lt>wolfgang@kinkeldei.deE<gt>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;
1;
