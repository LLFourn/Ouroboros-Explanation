use CoinToss::Protocol;

unit module CoinToss;

class Connection {...}

class Network {
    has @!players;
    has $.max-delay = 0;
    has %!suppliers;
    has $.rounds = 3;
    has $.loss-prob = 0;

    method send-message($sender, $message) {
        for @!players.grep(none($sender))  -> $player {
            # Drop the message with probability
            if 1.rand > $!loss-prob {
                # Delay the delivery some value less than the max delay
                Promise.in((0..$!max-delay).pick).then: {
                    %!suppliers{$player}.emit: $message;
                }
            }
        }
    }

    method connect-player($player) {
        $player.set-connection: Connection.new(:$player, network => self);
        %!suppliers{$player} = Supplier.new;
        @!players.push: $player;
    }

    method receive-message($player) {
        %!suppliers{$player}.?Supply
    }

}

class Connection {
    has CoinToss::Network:D $.network is required;
    has $.player is required;


    method send-message($message) {
        $!network.send-message($!player, $message)
    }

    method receive-message(-->Supply:D) {
        $!network.receive-message($!player);
    }
}
