#!/usr/bin/env perl
use strict;
use warnings;
use Net::RabbitMQ::PP;
use Try::Tiny;

# a simple example automatically reconnecting at a timeout.
# to be on the safe side we allways declare our queues
# and repeat the bindings.

while (1) {
    message_loop();
}

sub message_loop {
    my $broker = Net::RabbitMQ::PP->new(
        port => 5673, # forwarded Port on Win7
    );
    
    my $queue = $broker->queue('render');
    $queue->declare;
    $queue->bind(
        exchange    => 'cards',
        routing_key => 'render',
    );
    $queue->bind(
        exchange    => 'cards',
        routing_key => 'import',
    );
    
    try {
        my $channel = $broker->channel(1);
        $channel->consume(queue => 'render', no_ack => 0);

        print "waiting for messages...\n";

        while (my $message = $channel->receive) {
            printf "received key \%s: \%s\n",
                $message->routing_key,
                $message->body;
            
            $message->ack;
        }
    } catch {
        warn "disconnecting...";
        $broker->disconnect;
    };
}
