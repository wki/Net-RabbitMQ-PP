package Net::RabbitMQ::PP::Role::FrameIO;
use Moose::Role;
use Carp;

has frame_io => (
    is         => 'ro',
    isa        => 'Net::RabbitMQ::PP::FrameIO',
    lazy_build => 1,
    handles    => {
        write_frame    => 'write',
        write_greeting => 'write_greeting',
        write_header   => 'write_header',
        write_body     => 'write_body',
        read_frame     => 'read',
        next_frame_is  => 'next_frame_is',
    }
);

has channel_nr => (
    is      => 'ro',
    isa     => 'Int',
    default => 1,
);

sub send_message {
    my $self    = shift;
    my $message = shift;
    
    my $message_definition = $self->message_definition->{$message}
        or croak "Unable to send message '$message': not defined";
    
    my %args = ( %{$message_definition->{fields}}, @_ );
    
    $self->write_frame(
        $self->channel_nr,
        $message_definition->{message},
        %args,
    );
    
    return if exists $message_definition->{fields}->{no_wait} && $args{no_wait};
    
    my $response = $self->read_frame(
        $self->channel_nr,
        $message_definition->{response}
    );
    
    my $response_fields = $message_definition->{response_fields} // [];
    return if !scalar @$response_fields;
    
    return {
        map { ($_ => $response->method_frame->$_) } 
        @$response_fields
    };
}

no Moose::Role;
1;
