use NativeCall;

# use openSSL for SHA256
# Derived from https://github.com/sergot/openssl
constant SHA256_DIGEST_LENGTH = 32;

sub SHA256( Blob, size_t, Blob ) is native('ssl') { ... }
sub sha256(Blob $msg)  {
    my $digest = buf8.allocate(SHA256_DIGEST_LENGTH);
    SHA256($msg, $msg.bytes, $digest);
    $digest;

}

# concatenates the $secret and the $move and sha256 it
sub sha256-commitment($secret, $move) {
    my @sha256bytes := sha256(($secret ~ $move).encode());
    return @sha256bytes.map(*.base(16).Str).join;
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

# Prompt to choose Scissor, Paper or Rock
sub S-P-R {
    my $res = secret-prompt('[S]cissor [P]aper [R]ock?');
    if $res ~~ m:i/ <[spr]> /  {
        $res .= uc;
        return @moves.first(*.starts-with($res));
    }
    else {
        say "'$res' is an invalid choice.";
        $res = S-P-R();
    }
    return $res;
}

sub TURN($player) {
    say "$player, choose a move.";
    my $move =  S-P-R();
    return $move;
}

# commitment stage
sub COMMIT($player) {
    my $secret = secret-prompt("$player, give me a random secret (remember it):");
    my $move = TURN($player);
    return sha256-commitment($secret, $move);
}

sub CLAIM($player) {
    my $secret = secret-prompt("$player, what was your secret?");
    say "$player, what do you claim to have chosen?";
    my $claim = S-P-R();
    return $secret, $claim;
}

# verify
sub VERIFY($secret, $claim, $commitment) {
    my $claim-commitment = sha256-commitment($secret, $claim);
    say "claim:      ", $claim-commitment;
    say "commitment: ", $commitment;
    return $commitment eq $claim-commitment;
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

    if $result {
        say "$result wins!";
    }
    else {
        say 'Alice and Bob tied!';
    }
}

# Alice sends her commitment to Scissor, Paper or Rock to Rob
my $commitmentₐ = COMMIT(🧑🏻);
🧑🏻 ⟹ { :$commitmentₐ };

# Rob sends his move to Alice
my $moveᵣ = TURN(🧔🏾);
🧔🏾 ⟹ { :$moveᵣ };

# Alice sends what she claims to have originally chosen to Rob
# along with the secret
my ($secretₐ, $move-claimₐ) = CLAIM(🧑🏻);
🧑🏻 ⟹  { :$secretₐ, :$move-claimₐ };

# Rob (and any observers) verify Alice's claim
if VERIFY($secretₐ, $move-claimₐ, $commitmentₐ) {
    # see who won
    CHECK-RESULT($move-claimₐ, $moveᵣ);
}
else {
    say "Alice is lying! Her claim is not the same as her commitment.";
    say "Rob wins by default!";
}
