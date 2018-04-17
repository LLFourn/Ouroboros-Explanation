use CoinToss::Protocol;

unit module CoinToss;

class Connection {...}

class Network {
    has @.players;
    has $!max-delay = 5;
    has %!suppliers;
    has $.rounds = 3;
    has $.loss-prob = 0;

    method run {
        await @!players.map: { start .start(self, $!rounds) };
    }

    method TWEAK {
        for @!players {
            %!suppliers{$_} = Supplier.new;
        }
    }

    method send-message($sender, $message) {
        for @.players.grep(none($sender))  -> $player {
            if 1.rand > $!loss-prob {
                Promise.in((0..$!max-delay).pick).then: {
                    %!suppliers{$player}.emit: $message;
                }
            }
        }
    }

    method receive-message($player) {
        %!suppliers{$player}.?Supply
    }

    method connect($player) {
        Connection.new(:$player, network => self);
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
