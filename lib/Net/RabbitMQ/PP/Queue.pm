package Net::RabbitMQ::PP::Queue;
use Moose;
use Try::Tiny;
use namespace::autoclean;

with 'Net::RabbitMQ::PP::Role::Broker';

# TODO: does it make sense to have accessors for message-count, consumer-count

has name => (
    is => 'ro',
    isa => 'Str',
    required => 1,
);

sub message_definition {
    my $self = shift;
    
    return {
        declare => {
            message  => 'Queue::Declare',
            fields   => {
                queue       => $self->name,
                durable     => 1,
                passive     => 0,
                exclusive   => 0, 
                auto_delete => 0, 
                no_wait     => 0,
            },
            response => 'Queue::DeclareOk',
            response_fields => [qw(message_count consumer_count)],
        },
        bind => {
            message => 'Queue::Bind',
            fields  => {
                queue       => $self->name,
                exchange    => '', # must be given as arg
                routing_key => '',
                no_wait     => 0,
            },
            response => 'Queue::BindOk',
        },
        unbind => {
            message => 'Queue::Unbind',
            fields  => {
                queue       => $self->name,
                exchange    => '', # must be given as arg
                routing_key => '',
            },
            response => 'Queue::UnbindOk',
        },
        purge => {
            message => 'Queue::Purge',
            fields  => {
                queue   => $self->name,
                no_wait => 0,
            },
            response => 'Queue::PurgeOk',
        },
        delete => {
            message => 'Queue::Delete',
            fields  => {
                queue     => $self->name,
                if_unused => 0,
                if_empty  => 0,
                no_wait   => 0,
            },
            response => 'Queue::DeleteOk',
        },
    }
}

=head2 declare

declare a queue

=cut

sub declare {
    my $self = shift;
    
    $self->send_message(declare => @_)
}

=head2 bind

bind a queue to an exchange

=cut

sub bind {
    my $self = shift;
    
    $self->send_message(bind => @_);
}

=head2 unbind

unbind a queue from an exchange

=cut

sub unbind {
    my $self = shift;

    $self->send_message(unbind => @_);
}

=head2 purge

remove all messages from the queue

=cut

sub purge {
    my $self = shift;

    $self->send_message(purge => @_);
}

=head2 delete

deletes a queue

=cut

sub delete {
    my $self = shift;

    $self->send_message(delete => @_);
}

__PACKAGE__->meta->make_immutable;
1;
