use CoinToss::DLOG;

enum Coin <Heads Tails>;

grammar CoinToss::Protocol::Grammar {
    token TOP {
        $<body>=[
            | <message('REGISTER')>
            | <message('COMMIT')>
            | <message('REVEAL')>
        ]
        <signature>?
        {
            make {
                kv => $<message>.ast,
                signature => $<signature>.ast // [],
                body => $<body>.Str
            }
        }
    }

    token key-value($key, $value){
        [$<key>=$key || \w+ { die "Wrong key. Expected $key, got {$/.Str}" }]
        <sep>
        [ $<value>=<::($value)> || <[!\n]>+ {die "Invalid value for $key: {$/.Str}"} ]
        "\n"
        {
            make $<key>.Str => $<value>.ast
        }
    }

    token type($type) {
        ['TYPE' || { die "TYPE wasn't the first key in message" }]
         <sep> $type "\n"
    }

    token message:REGISTER {
        <type('REGISTER')>
        <key-value('FROM',   'string')>
        <key-value('PUBKEY', 'pubkey')>
    }

    token message:COMMIT {
        <type('COMMIT')>
        <key-value('FROM', 'string')>
        <key-value('EPOCH', 'epoch')>
        <key-value('COMMITMENT', 'hexint')>
        <key-value('MOVE', 'coin')>
    }

    token message:REVEAL {
        <type('REVEAL')>
        <key-value('FROM', 'string')>
        <key-value('EPOCH', 'epoch')>
        <key-value('FLIP', 'hexint')>
    }

    token message($type) {
        $<message>=<::("message:$type")>
        {
            make (TYPE => $type, |$<message><key-value>.map(*.ast)).Map
        }
    }

    token sep { \s* ':' \s*  }

    token signature {
        '---' "\n"
        ['SIGNATURE' <sep> $<𝒄>=<.hexint> '|' $<𝑠>=<.hexint> || { die "Badly formatted signature" }]
        { make ($<𝒄>.ast, $<𝑠>.ast) }
    }

    token epoch {
        <[0..9]>+
        { make Instant.from-posix($/.Str.Int) }
    }

    token pubkey {
        <hexint>
        {
            VALID-PUBKEY($<hexint>.ast) or
              die "Invalid public key";
            make $<hexint>.ast;
        }
    }

    token string {
        \S+
        { make $/.Str }
    }

    token coin {
        @(Coin::.values)
        { make Coin::{ $/.Str } }
    }

    token hexint {
        <[0..9a..f]>+
        { make $/.Str.parse-base(16) }
    }
}

sub pack-message(*@kv) is export
{
    join '', @kv.map: {
        .key.uc ~ ': ' ~ (given .value {
            when Instant { .to-posix[0] }
            when Coin { .gist }
            when Int { .base(16).lc }
            default  { $_ }
        }) ~ "\n";
    }
}

sub append-signature($message, SchnorrSig $signature) is export
{
    join '',
      $message,
      "---\n",
      "SIGNATURE: { $signature.map(*.base(16).lc).join('|') }"
}


sub unpack-message(Str:D $message) is export
{
    my $match  = CoinToss::Protocol::Grammar.parse($message)
      or die "Couldn't parse message:\n$message";

    return $match.made<kv signature body>;
}


constant \epoch-length is export       = 20;
constant \commit-phase-length is export = 20 div 2;

sub epoch-id-from-instant(Instant:D $i) is export
{
    my $posix = $i.to-posix()[0];
    # Truncate the posix time to the start time of the epoch for $i
    return Instant.from-posix($posix - ( $posix % epoch-length));
}
