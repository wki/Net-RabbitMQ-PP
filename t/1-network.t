use strict;
use warnings;
use IO::Socket::INET;
use Test::More;
use Test::TCP;

use ok 'Net::RabbitMQ::PP::Network';

my $server  = start_server();
my $network = construct_client();

$network->write("Hello\n");
is $network->read(3), "Hel", 'write-read loop works';

done_testing;


sub start_server {
    return Test::TCP->new(
        code => sub {
            my $port = shift;

            TestServer->run(
                port      => $port,
                host      => '127.0.0.1',
                log_level => 0,
            );
        },
    );
}

sub construct_client {
    return Net::RabbitMQ::PP::Network->new(
        host => '127.0.0.1',
        port => $server->port,
    );
}

{
    package TestServer;
    use base 'Net::Server';

    sub process_request {
        my $self = shift;

        while (my $line = <STDIN>) {
            print $line;
        }
    }
}
