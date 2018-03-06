[]# The players
sub term:<🧑🏻> { 'Alice' }
sub term:<🧔🏾> { 'Rob'  }
constant &print-hex := '0x' ~ *.base(16).lc;
# Used to print clearly what is actually being sent between the parties
sub infix:<⟹>($sender, %message) {
    my constant GREEN      = "\e[32m";
    my constant RESET      = "\e[0m";
    my $header =  ">>>=====$sender sends====>>>";
    say GREEN ~ $header ~ RESET;
    say %message.map({ "{.key}: {.value ~~ Int ?? .value.&print-hex !! .value}"}).join("\n");
    say GREEN ~ ('=' x $header.chars) ~ RESET;
}
constant @moves := <Tails Heads>;

# Taken from https://tools.ietf.org/html/rfc3526#page-3
constant \𝒑 = 0xFFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA63B139B22514A08798E3404DDEF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7EDEE386BFB5A899FA5AE9F24117C4B1FE649286651ECE45B3DC2007CB8A163BF0598DA48361C55D39A69163FA8FD24CF5F83655D23DCA3AD961C62F356208552BB9ED529077096966D670C354E4ABC9804F1746C08CA237327FFFFFFFFFFFFFFFF;
constant \𝒒 = (𝒑 - 1) div 2;
constant \𝒈 = 2;
# The ranges
constant $ℤ𝒑 = 1..𝒑;
constant $ℤ𝒒 = 1..𝒒;
# The types derived from the ranges
subset ℤ𝒑 of Int:D  where $ℤ𝒑;
subset ℤ𝒒 of Int:D  where $ℤ𝒒;
# The multiplicative group of order 𝒒 ( generated by 𝒈 )
subset 𝔾 of ℤ𝒑 where *.&expmod(𝒒, 𝒑) == 1;
# define new operator ⊕ as bitwise xor
constant &infix:<⊕> := &[+^];

sub read-line {
    my $res = $*IN.get();
    $*OUT.print("\e[A\r" ~ 'X' x 40 ~ ' ' x ($res.chars - 40) ~ "\n");
    return $res;
}

sub secret-prompt($msg, :$validity-check = True){
    say $msg;
    my $res = read-line();
    # Read a line from STDIN
    until $res ~~ $validity-check {
        say "invalid value - must match {$validity-check.gist}. Try again.";
        $res = read-line();
    }
    # Put n number of Xs over the previous line
    return $res;
}

sub CHOOSE-MOVE($player) {
    say "$player, choose an outcome.";
    my $res = secret-prompt('[H]eads or [T]ails?', validity-check => rx:i/H|T/).uc;
    my $move = @moves.first: *.starts-with($res);
    return $move;
}

sub CHOOSE-RANDOMNESS($player --> ℤ𝒒) {
    my $randomness = secret-prompt(
        "$player, behave [H]onestly? or enter your own integer:",
        validity-check => /^ H | (.+) <?{ quietly try $/.Int ~~ ℤ𝒒 }> $/,
    );

    return do given $randomness {
        when 'H' { $ℤ𝒒.pick() }
        default { .Int }
    }
}

sub COMMIT(ℤ𝒒 \𝒙 --> 𝔾) { expmod(𝒈, 𝒙, 𝒑) }

sub CLAIM($player) {
    # cheating
    my $randomness = secret-prompt(
        "$player, what do you claim your randomness was?" ~
        "\n([H] to use the true value)",
        validity-check => /^ H | .+ <?{ quietly try $/.Int ~~ $ℤ𝒒 }> $/
    );
    given $randomness {
        when 'H' { $randomness = $*HINT }
        default  { .Int }
    }
    return $randomness;
}

sub CHECK-RESULT($alice-move, $random-number) {
    my $even = $random-number %% 2;
    my $coin-toss = @moves[$even];
    my $result = $alice-move eq $coin-toss;

    say "============";
    say "The final random number is:\n{$random-number.&print-hex}";
    say "Which is { $even ?? 'even' !! 'odd' }. So, the coin-toss resulted in $coin-toss.";
    say "Alice chose $alice-move, so { $result ?? 🧑🏻 !! 🧔🏾} wins!", ;
}

# Entrypoint
sub MAIN {
    # Keep a hint around so Alice doesn't have to remember her number
    my $*HINT;
    # Prompt alice for heads or tails;
    my \𝑚 = CHOOSE-MOVE(🧑🏻);

    my 𝔾 \𝒄 = do {
        # Prompt alice for her randomness
        $*HINT = my ℤ𝒒 \𝒔ₐ = CHOOSE-RANDOMNESS(🧑🏻);
        # Return the resulting commitment
        COMMIT(𝒔ₐ);
    }

    # Send the commitment and the move in the clear to Rob
    🧑🏻 ⟹  { commitment => 𝒄, move => 𝑚 };

    # Rob doesn't have to choose a move, his move is just the opposite of Alice's
    my ℤ𝒒 \𝒔ᵣ = CHOOSE-RANDOMNESS(🧔🏾);
    🧔🏾 ⟹ { randomness => 𝒔ᵣ };

    my ℤ𝒒 \𝒔ₐʹ = CLAIM(🧑🏻);
    🧑🏻 ⟹  { randomness => 𝒔ₐʹ };

    my 𝔾 \𝒄ʹ = COMMIT(𝒔ₐʹ);

    if 𝒄ʹ eq  𝒄 {
        say "{🧑🏻}'s claim is the same as her commitment.";
        my \𝒔 = 𝒔ᵣ ⊕ 𝒔ₐʹ;
        CHECK-RESULT(𝑚, 𝒔);
    }
    else {
        say "{🧑🏻}'s claim: {𝒄ʹ.&print-hex}";
        say "{🧑🏻} is lying! Her claim is not the same as her commitment.";
        say "{🧔🏾} wins by default!";
    }
}
