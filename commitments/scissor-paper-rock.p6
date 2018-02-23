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

# Our two players
sub term:<🧑🏻> { 'Alice' }
sub term:<🧔🏾> { 'Rob'  }

# Used to print clearly what is actually being sent between the parties
sub infix:<⟹>($sender, %message) {
    my constant GREEN      = "\e[32m";
    my constant RESET      = "\e[0m";
    my $header =  ">>>=====$sender sends====>>>";
    say GREEN ~ $header ~ RESET;
    say %message.map({ "{.key}: {.value}"}).join("\n");
    say GREEN ~ ('=' x $header.chars) ~ RESET;
}

# The possible moves
constant @moves := <Scissor Paper Rock>;

sub secret-prompt($msg){
    say $msg;
    # Read a line from STDIN
    my $res = $*IN.get();
    # Put n number of Xs over the previous line
    $*OUT.print("\e[A\r" ~ 'X' x $res.chars ~ "\n");
    return $res;
}

sub CHOOSE-SECRET($player) {
    secret-prompt("$player, give me a random secret (remember it):");
}

# Prompt to choose Scissor, Paper or Rock
sub S-P-R {
    my $res = secret-prompt('[S]cissor [P]aper [R]ock?').uc;
    if $res eq <S P R>.any {
        return @moves.first(*.starts-with($res));
    }
    else {
        say "'$res' is an invalid choice.";
        $res = S-P-R();
    }
    return $res;
}

sub CHOOSE-MOVE($player) {
    say "$player, choose a move.";
    my $move =  S-P-R();
    return $move;
}

sub CLAIM($player) {
    my $secret = secret-prompt("$player, what was your secret?");
    say "$player, what do you claim to have chosen?";
    my $claim = S-P-R();
    return $secret, $claim;
}

sub CHECK-RESULT($moveₐ, $moveᵣ) {
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


my \𝒄 = do {
    # Prompt alice for her move and secret
    my \𝒔 = CHOOSE-SECRET(🧑🏻);
    my \𝓶 = CHOOSE-MOVE(🧑🏻);
    # Return the resulting commitment
    COMMIT(𝒔, 𝓶);
};

# Alice sends her commitment to Rob
🧑🏻 ⟹ { commitment => 𝒄 };

# Rob sends his move to Alice
my \𝓶ᵣ = CHOOSE-MOVE(🧔🏾);
🧔🏾 ⟹ { move => 𝓶ᵣ };

# Alice sends what she claims to have originally chosen to Rob
# along with the secret
my (\𝒔ʹ, \𝓶ʹ) = CLAIM(🧑🏻);
🧑🏻 ⟹  { secret => 𝒔ʹ, move => 𝓶ʹ };

my \𝒄ʹ = COMMIT(𝒔ʹ, 𝓶ʹ);

say "Alice's claim: {𝒄ʹ}";

if 𝒄ʹ eq  𝒄 {
    say ‘Alice's claim is the same as her commitment.’;
    CHECK-RESULT(𝓶ʹ, 𝓶ᵣ);
}
else {
    say "Alice is lying! Her claim is not the same as her commitment.";
    say "Rob wins by default!";
}
