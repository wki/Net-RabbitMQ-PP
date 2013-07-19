package Net::RabbitMQ::PP::FrameIO;
use 5.010;
use Moose;
use Net::AMQP;
use Net::RabbitMQ::PP::Network;
use File::ShareDir ':ALL';
use Path::Class;
use Try::Tiny;
use Data::Dumper;
use namespace::autoclean;

has network => (
    is       => 'ro',
    isa      => 'Object', # typically ::Network
    required => 1,
);

has debug => (
    is      => 'ro',
    isa     => 'Int',
    default => 0,
);

has _pre_read_data => (
    is      => 'rw',
    isa     => 'Str',
    default => '',
);

# { channel => [ ... ], ... }
has _cached_frames_for_channel => (
    is      => 'rw',
    isa     => 'HashRef',
    default => sub { +{} },
);

sub cache_frame {
    my $self    = shift;
    my $channel = shift // 0;
    
    push @{$self->_cached_frames_for_channel->{$channel}}, @_;
}

sub has_cached_frames {
    my $self    = shift;
    my $channel = shift // 0;
    
    return scalar @{$self->_cached_frames_for_channel->{$channel} //= []};
}

sub get_cached_frame {
    my $self    = shift;
    my $channel = shift // 0;
    
    return shift @{$self->_cached_frames_for_channel->{$channel}};
}

sub BUILD {
    my $self = shift;
    state $spec_loaded = 0;

    if (!$spec_loaded) {
        my $dist_dir;
        try {
            $dist_dir = dir(dist_dir('MessageQ'));
        } catch {
            $dist_dir = file(__FILE__)->absolute->resolve->dir->parent->parent->parent->parent->subdir('share');
        };

        my $spec_file = $dist_dir->file('amqp0-9-1.xml');
        my $spec = scalar $spec_file->slurp; # ??? (iomode => '<:encoding(UTF-8)')

        Net::AMQP::Protocol->load_xml_spec(undef, \$spec);

        $spec_loaded++;
    }
}

sub print_debug {
    my $self = shift;
    my $level = shift;

    say @_ if $self->debug >= $level;
}

=head2 write ( $channel, $frame_type [, %args ] )

construct and write a frame

    # FIXME: is channel.declare allowed ???
    # FIXME: do we rewrite no_ack => 1 to 'no-ack' => 1 ???
    #
    $xxx->write('Channel::Declare', ...)

=cut

sub write {
    my $self       = shift;
    my $channel    = shift;
    my $frame_type = shift;

    my $frame = "Net::AMQP::Protocol::$frame_type"->new(@_);

    # what is the meaning of this?
    if ($frame->isa('Net::AMQP::Protocol::Base')) {
        $frame = $frame->frame_wrap;
    }

    $frame->channel($channel);
    $self->_write_frame($frame);
}

sub _write_frame {
    my $self  = shift;
    my $frame = shift;

    $self->print_debug(1, 'Writing Frame (' . $frame->channel . ') ',
        $frame->can('method_frame')
            ? ref $frame->method_frame
            : ref $frame
        );
    $self->print_debug(2, 'Frame:', Dumper $frame);
    $self->network->write($frame->to_raw_frame);
}

=head2 write_greeting

writes a greeting frame for the start of a connection

=cut

sub write_greeting {
    my $self = shift;

    $self->network->write(Net::AMQP::Protocol->header);
}

=head2 write_header ( $channel, $frame)

write a header frame

=cut

sub write_header {
    my $self    = shift;
    my $channel = shift;
    my %args    = @_;

    my $body_size = delete $args{body_size} // 0;
    
    my $header = Net::AMQP::Frame::Header->new(
        weight       => 0,
        body_size    => $body_size,
        header_frame => Net::AMQP::Protocol::Basic::ContentHeader->new(
            content_type     => 'application/octet-stream',
            content_encoding => undef,
            headers          => {},
            delivery_mode    => 1,
            priority         => 1,
            correlation_id   => undef,
            expiration       => undef,
            message_id       => undef,
            timestamp        => time,
            type             => undef,
            user_id          => undef,
            app_id           => undef,
            cluster_id       => undef,
            %{$args{header}},
        ),
    );

    $header->channel($channel);
    $self->_write_frame($header);
}

=head2 write_body

write a body frame with some payload

=cut

sub write_body {
    my $self    = shift;
    my $channel = shift;
    my $payload = shift;

    my $body = Net::AMQP::Frame::Body->new(payload => $payload);
    $body->channel($channel);
    $self->_write_frame($body);
}

=head2 read ( $channel [ , $expected_frame_type ] )

read a frame optionally expecting a certain type

=cut

sub read {
    my $self                = shift;
    my $channel             = shift;
    my $expected_frame_type = shift;

    $self->_read_frames_into_cache($channel);

    my $frame = $self->get_cached_frame($channel)
        or die "Could not read a frame - cache ($channel) is empty";

    if ($expected_frame_type) {
        if (!$self->frame_is($frame, $expected_frame_type)) {
            my $got = $frame->can('method_frame')
                ? $frame->method_frame
                : ref $frame;
            die "Expected '$expected_frame_type' but got '$got'";
        }
    }

    return $frame;
}

sub _read_frames_into_cache {
    my $self    = shift;
    my $channel = shift;

    ### Could this be harmful?
    return if $self->has_cached_frames($channel);

    my $data = $self->_read_data
        or return;
    my @frames = Net::AMQP->parse_raw_frames(\$data);
    
    foreach my $frame (@frames) {
        $self->print_debug(1, "Caching Frame (${\$frame->channel}):",
            $frame->can('method_frame')
                ? ref $frame->method_frame
                : ref $frame
        );
        $self->print_debug(2, "Frame:", Dumper $frame);
        
        $self->cache_frame($frame->channel, $frame);
    }
}

=head2 next_frame_is

checks next frame against a type and returns a boolean reflecting the type check

=cut

sub next_frame_is {
    my $self = shift;
    my $channel = shift;
    my $expected_frame_type = shift
        or return 1;

    $self->_read_frames_into_cache($channel);

    return 0 if !$self->has_cached_frames($channel);

    return $self->frame_is($self->_cached_frames_for_channel->{$channel}->[0], $expected_frame_type);
}

sub frame_is {
    my $self = shift;
    my $frame = shift;
    my $expected_frame_type = shift
        or return 1;

    my $got = $frame->can('method_frame')
        ? ref $frame->method_frame
        : ref $frame;

    $self->print_debug(2, "testing '$got' against '$expected_frame_type'...");

    return $got =~ m{\Q$expected_frame_type\E \z}xms;
}


# Header: 7 Bytes:  tt cc cc ss ss ss ss     type, channel, size
# Body:   s Bytes
# Footer: 1 Byte    0xce

# read raw data, keep superfluous data in _pre_read_data,
# return data for one frame
sub _read_data {
    my $self = shift;

    my $data = $self->_pre_read_data;

    # If we have less than 7 bytes of data, we need to read more so we at least get the header
    if (length $data < 7) {
        $data .= $self->network->read(1024) // '';
    }

    # Read header
    my $header = substr $data, 0, 7, '';

    return unless $header;

    my ($type_id, $channel, $size) = unpack 'CnN', $header;

    # Read body
    my $body = substr $data, 0, $size, '';

    # If we haven't got the full body and the footer, we have more to read
    if (length $body < $size || length $data == 0) {
        # Add 1 to the size to make sure we get the footer
        my $size_remaining = $size+1 - length $body;

        while ($size_remaining > 0) {
            my $chunk = $self->network->read($size_remaining);

            $size_remaining -= length $chunk;
            $data .= $chunk;
        }

        $body .= substr($data, 0, $size-length($body), '');
    }

    # Read footer
    my $footer = substr $data, 0, 1, '';
    my $footer_octet = unpack 'C', $footer;

    die "Invalid footer: $footer_octet\n" unless $footer_octet == 206;

    $self->_pre_read_data($data);

    return $header . $body . $footer;
}

__PACKAGE__->meta->make_immutable;
1;
