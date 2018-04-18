use CoinToss::Network;
use CoinToss::Player;

my @players = my ($alice, $bob, $oscar) = <Alice Bob Oscar>.map: {
    CoinToss::Player.new(:name($_))
};

# Create a network that delays messages up to 3 seconds
my $network = CoinToss::Network.new(max-delay => 3);

# Connect all the players to the network
for @players {
    $network.connect-player($_)
}

# Start Alice and Bob playing
my @promises = (start $alice.play(:2rounds)), (start $bob.play(:2rounds));

sleep 20;

# Oscar joins for one round 20 seconds later
@promises.push: start $oscar.play(:1rounds);

# wait for them all to finish
await @promises;
