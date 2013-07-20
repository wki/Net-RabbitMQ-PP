package Net::RabbitMQ::PP::Channel;
use Moose;
use Data::Dumper;
use Net::RabbitMQ::PP::Message;
use namespace::autoclean;

with 'Net::RabbitMQ::PP::Role::Broker';

has consumer_tag => (
    is        => 'rw',
    isa       => 'Any',
    predicate => 'is_consuming',
    clearer   => 'finished_consuming',
);

sub message_definition {
    my $self = shift;
    
    return {
        consume => {
            message  => 'Basic::Consume',
            fields   => {
                consumer_tag => '',
                no_local     => 0,
                no_ack       => 0,
                exclusive    => 0,
                no_wait      => 0,
            },
            response => 'Basic::ConsumeOk',
            response_fields => ['consumer_tag'],
        },
        qos => {
            message => 'Basic::Qos',
            fields  => {
                prefetch_size  => '',
                prefetch_count => 0,
                global         => 1,
            },
            response => 'Basic::QosOk',
        },
        cancel => {
            message => 'Basic::Cancel',
            fields  => {
                consumer_tag => '',
                no_wait      => 0,
            },
            response => 'Basic::CancelOk',
        },
        return => {
            message => 'Basic::Return',
            fields => {
                reply_code  => '',
                reply_text  => '',
                exchange    => '',
                routing_key => '',
            },
            response => 'Basic::ReturnOk'
        },
        # deliver => {
        #     message => 'Basic::Deliver',
        #     fields => {
        #         consumer_tag => '',
        #         delivery_tag => '',
        #         redelivered  => '',
        #         exchange     => '',
        #         routing_key  => '',
        #     },
        #     # no response => 'Basic::DeliverOk'
        # },
        # recover => {
        #     message => 'Basic::Recover',
        #     fields => {
        #         requeue => 0,
        #     },
        #     response => 'Basic::RecoverOk'
        # },
    };
}

=head2 publish ( exchange => 'foo', data => ..., other_fields => ..., header => { ... } )

publish a message

data must be a string, header fields are added to ContentHeader

=cut

sub publish {
    my $self = shift;
    my %args = @_;
    
    my $data   = delete $args{data}
        or die 'no data to publish';
    my $header = delete $args{header};
    
    $self->write_frame(
        $self->channel_nr,
        'Basic::Publish',
        mandatory => 0,
        immediate => 0,
        %args,
    );
    
    $self->write_header(
        $self->channel_nr,
        body_size => length $data,
        header    => $header // {},
    );
    
    # We split the body into frames of frame_max octets
    my @chunks = unpack "(a${\$self->broker->frame_max})*", $data;
    $self->write_body($self->channel_nr, $_) for @chunks;
}

=head2 get ( queue => 'queue', ... )

Get a message from $queue. Return a hashref with the message details, or undef
if there is no message. This is essentially a poll of a given queue. %params is
an optional hash containing parameters to the Get request.

=cut

sub get {
    my $self = shift;
    my %args = @_;
    
    $self->write_frame(
        $self->channel_nr,
        'Basic::Get',
        no_ack => 0,
        %args,
    );
    
    if ($self->next_frame_is($self->channel_nr, 'Basic::GetEmpty')) {
        $self->read_frame($self->channel_nr);
        return;
    }
    
    my $get_ok = $self->read_frame($self->channel_nr, 'Basic::GetOk');
    return $self->_read_response($get_ok);
}

sub _read_response {
    my $self = shift;
    my $deliver_frame = shift // $self->read_frame($self->channel_nr, 'Basic::Deliver');

    my $header  = $self->read_frame($self->channel_nr, 'Frame::Header');
    
    my $body = '';
    while (length $body < $header->body_size) {
        my $frame = $self->read_frame($self->channel_nr, 'Frame::Body');
        
        $body .= $frame->payload;
    }
    
    return Net::RabbitMQ::PP::Message->new(
        channel_nr     => $self->channel_nr,
        frame_io       => $self->frame_io,
        body           => $body,
        delivery_tag   => $deliver_frame->method_frame->delivery_tag,
        reply_to       => $header->header_frame->headers->{reply_to},
        correlation_id => $header->header_frame->headers->{correlation_id},
    );
}

=head2 consume ( queue => 'queue', ... )

Indicate that a given queue should be consumed from. %params contains 
params to be passed to the Consume request.

Returns the consumer tag. Once the client is consuming from a queue,
receive() can be called to get any messages.

=cut

sub consume {
    my $self = shift;
    
    my $reply = $self->send_message(consume => @_);
    
    $self->consumer_tag($reply->{consumer_tag});
    
    return $reply->{consumer_tag};
}

=head2 receive

Receive a message from a queue that has previously been consumed from.

The message returned is of the same format as that returned from get()

=cut

sub receive {
    my $self = shift;
    
    die 'receive called without consuming a queue'
        if !$self->is_consuming;

    return $self->_read_response;
}

=head2 qos

specify quality of service

=cut

sub qos {
    my $self = shift;
    
    $self->send_message(qos => @_);
}

=head2 cancel

cancel a consumer

=cut

sub cancel {
    my $self = shift;
    
    $self->send_message(cancel => consumer_tag => $self->consumer_tag, @_);
    
    $self->finished_consuming;
}

# TODO: flow(active)
# TODO: close(reply-code, reply-text, class-id, method-id)

sub close {
    my $self = shift;
    
    # ... do more.
    
    $self->broker->_mark_channel_closed($self->channel_nr);
}

__PACKAGE__->meta->make_immutable;
1;
