package Net::RabbitMQ::PP::Exchange;
use Moose;
use Try::Tiny;
use namespace::autoclean;

with 'Net::RabbitMQ::PP::Role::Broker';

has name => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

sub message_definition {
    my $self = shift;
    
    return {
        declare => {
            message  => 'Exchange::Declare',
            fields   => {
                exchange => $self->name,
                type     => 'direct',
                passive  => 0,
                durable  => 1,
            },
            response => 'Exchange::DeclareOk',
            response_fields => [],
        },
        delete => {
            message  => 'Exchange::Delete',
            fields   => {
                exchange  => $self->name,
                if_unused => 0,
                no_wait   => 0,
            },
            response => 'Exchange::DeleteOk',
            response_fields => [],
        }
    }
}

=head2 declare

declare an exchange

=cut

sub declare {
    my $self = shift;
    
    $self->send_message(declare => @_);
}

=head2 delete

deletes an exchange

=cut

sub delete {
    my $self = shift;

    $self->send_message(delete => @_);
}

__PACKAGE__->meta->make_immutable;
1;
