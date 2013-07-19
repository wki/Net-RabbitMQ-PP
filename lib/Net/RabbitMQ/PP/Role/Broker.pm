package Net::RabbitMQ::PP::Role::Broker;
use Moose::Role;

with 'Net::RabbitMQ::PP::Role::FrameIO';

has broker => (
    is       => 'ro',
    isa      => 'Object',
    required => 1,
    handles  => {
        # ...
    },
);

sub _build_frame_io { $_[0]->broker->frame_io }

no Moose::Role;
1;
