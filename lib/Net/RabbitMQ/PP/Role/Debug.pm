package Net::RabbitMQ::PP::Role::Debug;
use 5.010;
use Moose::Role;

has debug => (
    is      => 'ro',
    isa     => 'Int',
    default => 0,
);

sub print_debug {
    my $self = shift;
    my $level = shift;

    say @_ if $self->debug >= $level;
}

1;
