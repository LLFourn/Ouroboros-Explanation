use CoinToss::Protocol;
use CoinToss::DLOG;
use CoinToss::Network;

my class X::CoinToss::Abort is Exception {
    has Str:D $.reason is required;
    has $.player is required;
    has $.type = "unknown type";
    has $.from = "unknown player";

    method gist {
        $!player.log: "aborted processing of {$!type.gist} message from {$!from.gist}: $!reason";
    }
}

# alias bitwise xor to the mathematical symbol
constant &infix:<⊕> := &[+^];

#| private class to store the state of a the current epoch
my class Epoch {

    has Instant:D  $.start is required;
    has Int:D   %.commitments;
    has Coin:D  %.moves;
    has Int:D   %.flips;
    has Int:D   %.scores;
    has Promise:D $!reveal-complete = Promise.new;

    method next-epoch {
        Epoch.new(:%!scores, start => $!start + epoch-length)
    }

    method time-till-end-epoch {
        epoch-length - (now - $!start);
    }

    method time-till-reveal-phase {
        commit-phase-length - (now - $!start);
    }

    method wait-till-reveal-phase {
        Promise.in(self.time-till-reveal-phase);
    }

    method wait-till-reveal-complete { $!reveal-complete }

    method now {
        Epoch.new(start => epoch-id-from-instant(now));
    }

    method reveal($player, Int:D $flip) {
        %.flips{$player} = $flip;
        if %.flips == %.commitments {
            $!reveal-complete.keep(%.flips.values);
        }
    }

    method wait-till-next-epoch {
        Promise.in(self.time-till-end-epoch).then: { self.next-epoch };
    }

    method id { $!start.to-posix[0] }

}

#| Stores a player's view of the system
class CoinToss::Player {

    #| The player's registered public key for other players by their name
    has %.pubkey-registry;
    has $.name is required;
    has $.private-key;
    has $.public-key;
    #| The connection to the outside world
    has CoinToss::Connection $.connection;
    #| The current epoch
    has Epoch $.epoch;

    method TWEAK {
        without $!private-key {
            ($!private-key, $!public-key) = GEN();
        }
    }

    method set-connection($!connection) {}

    #| Play a certain number of rounds
    method play(:$rounds!) {
        self.log: "STARTS PLAYING for $rounds rounds";
        $!epoch = Epoch.now;

        # Whenever a message arrives, process it
        $!connection.receive-message.tap: -> $message {
            self.receive-message($message);
            CATCH {
                when X::CoinToss::Abort { .note }
                default { .note }
            }
        };
        # Register your public key with the other players
        self.register();

        # The game loop
        for ^$rounds {
            self.log: "waiting for next epoch to start";
            $!epoch = await $!epoch.wait-till-next-epoch;

            self.log: "started epoch: {$!epoch.id}";

            # Send our commitment
            self.flip-and-commit();

            await $!epoch.wait-till-reveal-phase();

            if $!epoch.commitments > 1 {
                # if more than just us has committed then we reveal
                self.reveal-flip();

                await Promise.anyof:
                  $!epoch.wait-till-reveal-complete(),
                  $!epoch.wait-till-next-epoch();

                # Everyone has revealed or the epoch is over.
                # Check who won.
                self.process-result();
            }
            else {
                # Not enough players just wait until next epoch
                await $!epoch.wait-till-reveal-phase();
            }
        }
        self.log: "$!name has finished playing";
    }

    method receive-message($message) {
        my (%kv, @signature, $msg-body) := unpack-message($message);

        my ($from, $type) := %kv<FROM TYPE>;

        sub abort($reason) {
            X::CoinToss::Abort.new(
                :$reason,
                player => self,
                :$type,
                :$from,
            ).throw;
        }

        if $type eq 'REGISTER' {
            without %!pubkey-registry{$from} {
                $_ = %kv<PUBKEY>;
                self.register();
                self.log: "registed $from’s public-key";
            }
            # Exit early - REGISTER doesn't have a signature check
            return;
        }

        # Get previously registered public key
        my $pubkey = %.pubkey-registry{$from}
          or abort "don't have $from’s public key";

        # Check the epoch the message was sent in is this Epoch
        %kv<EPOCH> ~~ $!epoch.start
          or abort "message's epoch (%kv<EPOCH>) isn't the current epoch ({$!epoch.start})";

        # Verify the signature
        VERIFY(@signature, $pubkey, $msg-body)
          or abort "signature was invalid";

        given $type {
            when 'COMMIT' {
                my \𝑐 = %kv<COMMITMENT>;
                my \𝑚 = %kv<MOVE>;

                if not $!epoch.moves{$from}:exists {
                    $!epoch.commitments{$from} = 𝑐;
                    $!epoch.moves{$from} = 𝑚;
                    self.log: "received $from’s move ({𝑚.gist}) and commitment";
                }
            }
            when 'REVEAL' {
                with $!epoch.commitments{$from} -> \𝑐 {
                    my \𝜌ʹ = %kv<FLIP>;
                    my \𝑐ʹ = COMMIT(𝜌ʹ);

                    if 𝑐 == 𝑐ʹ {
                        $!epoch.reveal($from, 𝜌ʹ);
                        self.log: "received $from’s revealed coin flip";
                    }
                    else {
                        abort "randomness didn't match commitment";
                    }
                }
                else {
                    abort "No commitment found";
                }
            }
        }
    }

    method register {
        my $msg-body := pack-message (
            type => 'REGISTER',
            from => "$!name",
            pubkey => $!public-key
        );

        $!connection.send-message: $msg-body;
    }

    method flip-and-commit {
        my \𝜌 = $!epoch.flips{$!name}        = pick-ℤ𝑞;
        my \𝑐  = $!epoch.commitments{$!name} = COMMIT(𝜌);
        my \𝑚 = $!epoch.moves{$!name}       = Coin::.values.pick;

        my $msg-body := pack-message (
            type => 'COMMIT',
            from => "$!name",
            epoch => $!epoch.start,
            commitment => 𝑐,
            move => 𝑚,
        );

        my $signature := SIGN($msg-body, $!private-key);
        my $full-msg := append-signature $msg-body, $signature;
        self.log: "broadcasting my commitment and move";
        $!connection.send-message: $full-msg;
    }

    method reveal-flip {
        my $msg-body := pack-message (
            type => 'REVEAL',
            from => "$!name",
            epoch => $!epoch.start,
            flip => $!epoch.flips{$!name}
        );

        my $signature := SIGN($msg-body, $!private-key);
        my $full-msg := append-signature $msg-body, $signature;
        self.log: "broadcasting my coin flip";
        $!connection.send-message($full-msg);
    }

    method process-result {
        my (%flips, %moves, %scores) := (.flips, .moves, .scores given $!epoch);

        my \𝜌 = [⊕] %flips.values;
        my $odd = not 𝜌 %% 2; # Not divisible by two
        my $final-coin-toss = Coin($odd.Int); # 0 = Heads, 1 = Tails

        self.log: "sees the coin flip as {$final-coin-toss.gist}";

        for %moves.kv -> $player, $move {
            if not %flips{$player}:exists {
                %scores{$player} -= 1
            }
            else {
                %scores{$player} += ($move == $final-coin-toss ?? 1 !! -1);
            }
        }

        self.log: "my scores at epoch {$!epoch.id} are: {%scores.map:{ .kv.join(':') }}";
    }

    method log($msg) {
        note "[{sprintf '%5.s', $!name.uc}]: ",  $msg;
    }

}
