use NativeCall;

# YOU WILL NEED OPENSSL INSTALLED FOR THIS TO RUN
# YMMV on windows. If you're desperate to get it to work:
# Look at https://github.com/sergot/openssl

constant SHA256_DIGEST_LENGTH = 32;

sub SHA256(Blob, size_t, Blob) is native('ssl') { ... }
sub sha256(Blob $msg)  {
    my $digest = buf8.allocate(SHA256_DIGEST_LENGTH);
    SHA256($msg, $msg.bytes, $digest);
    return $digest;
}

my &byte-to-hex = &sprintf.assuming('%02x');
# concatenates the $secret and the $move and return the
# sha256 as hex string
sub COMMIT($secret, $move) {
    my @sha256bytes := sha256(($secret ~ $move).encode());
    return @sha256bytes».&byte-to-hex.join;
}

# The possible moves
enum Move <Scissor Paper Rock>;

# Our two players
enum Player <Alice Rob>;
constant \term:<🧑🏻> = Alice;
constant \term:<🧔🏾> = Rob;

# Used to print clearly what is actually being sent between the parties
sub infix:<⟹>($sender, %message) {
    my constant GREEN      = "\e[32m";
    my constant RESET      = "\e[0m";
    my $header =  ">>>=====$sender sends====>>>";
    say GREEN ~ $header ~ RESET;
    say %message.map({ "{.key}: {.value}"}).join("\n");
    say GREEN ~ ('=' x $header.chars) ~ RESET;
}


sub secret-prompt($msg -->Str:D){
    say $msg;
    # Read a line from STDIN
    my $res = $*IN.get();
    # Put n number of Xs over the previous line
    $*OUT.print("\e[A\r" ~ 'X' x 40 ~ ' ' x ($res.chars - 40) ~ "\n");
    return $res;
}

sub CHOOSE-SECRET($player -->Str:D) {
    secret-prompt("$player, give me a random secret (remember it):");
}

# Prompt to choose Scissor, Paper or Rock
sub S-P-R (-->Move:D){
    my $res = secret-prompt('[S]cissor [P]aper [R]ock?').uc;
    if $res eq <S P R>.any {
        return Move::.values.first(*.starts-with($res));
    }
    else {
        say "'$res' is an invalid choice.";
        $res = S-P-R();
    }
    return $res;
}

sub CHOOSE-MOVE(Player:D $player --> Move:D) {
    say "$player, choose a move.";
    my $move =  S-P-R();
    return $move;
}

sub CLAIM(Player:D $player --> List:D) {
    my $secret = secret-prompt("$player, what was your secret?");
    say "$player, what do you claim to have chosen?";
    my $claim = S-P-R();
    return $secret, $claim;
}

sub CHECK-RESULT(Move:D $moveₐ, Move:D $moveᵣ) {
    my $result = do given ($moveₐ, $moveᵣ)
    {
        when $moveₐ eq $moveᵣ     { Nil } # tie
        when ('Rock', 'Scissor')|
             ('Paper','Rock')   |
             ('Scissor', 'Paper') { 🧑🏻 } # alice wins
        default                   { 🧔🏾 } # bob wins
    }

    say "Rob played $moveᵣ, Alice played $moveₐ.";
    say $result ?? "$result wins!" !! 'Alice and Bob tied!';
}

sub MAIN {
    my \𝑐 = do {
        # Prompt alice for her move and secret
        my \𝑠 = CHOOSE-SECRET(🧑🏻);
        my \𝑚 = CHOOSE-MOVE(🧑🏻);
        # Return the resulting commitment
        COMMIT(𝑠, 𝑚);
    };

    # Alice sends her commitment to Rob
    🧑🏻 ⟹ { commitment => 𝑐 };

    # Rob sends his move to Alice
    my \𝑚ᵣ = CHOOSE-MOVE(🧔🏾);
    🧔🏾 ⟹ { move => 𝑚ᵣ };

    # Alice sends what she claims to have originally chosen to Rob
    # along with the secret
    my (\𝑠ʹ, \𝑚ʹ) = CLAIM(🧑🏻);
    🧑🏻 ⟹  { secret => 𝑠ʹ, move => 𝑚ʹ };

    my \𝑐ʹ = COMMIT(𝑠ʹ, 𝑚ʹ);

    say "Alice's claim: {𝑐ʹ}";

    if 𝑐ʹ eq  𝑐 {
        say ‘Alice's claim is the same as her commitment.’;
        CHECK-RESULT(𝑚ʹ, 𝑚ᵣ);
    }
    else {
        say "Alice is lying! Her claim is not the same as her commitment.";
        say "Rob wins by default!";
    }
}
