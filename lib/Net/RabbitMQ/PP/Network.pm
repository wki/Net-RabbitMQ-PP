package Net::RabbitMQ::PP::Network;
use Moose;
use IO::Socket::INET;
use Socket qw(IPPROTO_TCP TCP_NODELAY);
use namespace::autoclean;

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

has socket => (
    is         => 'ro',
    isa        => 'IO::Socket',
    lazy_build => 1,
);

sub _build_socket {
    my $self = shift;

    my $socket;
    {
        $socket = IO::Socket::INET->new(
            PeerAddr => $self->host,
            PeerPort => $self->port,
            Proto    => 'tcp',
            Timeout  => 1,              # FIXME: right?
        );

        if (!defined $socket) {
            my $error = $!;
            if ($error eq 'Interrupted system call') {
                redo;
            }

            die "Could not open socket: $error\n" unless $socket;
        }
    }

    $socket->setsockopt(IPPROTO_TCP, TCP_NODELAY, 1);
    
    ### FIXME: here or in read() call?
    if ($self->timeout) {
        $self->socket->setsockopt(SOL_SOCKET, SO_RCVTIMEO, pack('L!L!', $self->timeout, 0));
    }

    return $socket;
}

sub DEMOLISH {
    my $self = shift;

    $self->socket->close();
}

sub write {
    my $self = shift;
    my $data = shift;

    $self->socket->send($data) or die "Failed in writing data ($!)";
}

sub read {
    my $self      = shift;
    my $read_size = shift
        or die 'network-read: read_size required';

    my $chunk_size;
    my $chunk;

    while (!defined $chunk_size) {
        $chunk_size = $self->socket->sysread($chunk, $read_size);

        if (! defined $chunk_size) {
            my $read_error = $!;
            if ($read_error eq 'Interrupted system call') {
                # A signal interrupted us... just try again
                next;
            }

            if ($read_error eq 'Resource temporarily unavailable') {
                # We assume this is a timeout...
                return;
            }

            die "Error reading from socket: $read_error\n";
        }
    }

    return $chunk;
}

__PACKAGE__->meta->make_immutable;
1;
