package Net::RabbitMQ::PP::Message;
use Moose;
use namespace::autoclean;

with 'Net::RabbitMQ::PP::Role::FrameIO';

has body => (
    is       => 'ro',
    isa      => 'Any',
    required => 1,
);

has delivery_tag => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has reply_to => (
    is       => 'ro',
    isa      => 'Maybe[Str]',
    required => 1,
);

has correlation_id => (
    is       => 'ro',
    isa      => 'Maybe[Str]',
    required => 1,
);

=head2 ack

Ack a received message

=cut

sub ack {
    my $self = shift;
    my %args = @_;
    
    $self->write_frame(
        $self->channel_nr,
        'Basic::Ack',
        multiple     => 0,
        delivery_tag => $self->delivery_tag,
        %args
    );
}

__PACKAGE__->meta->make_immutable;
1;
