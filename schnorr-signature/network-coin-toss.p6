use CoinToss::Network;
use CoinToss::Player;

my @players = my ($alice, $bob, $oscar) = <Alice Bob Oscar>.map: {
    CoinToss::Player.new(:name($_))
};

my $network = CoinToss::Network.new(:5delay);

for @players {
    $network.connect-player($_)
}

my @promises = (start $alice.play(:2rounds)), (start $bob.play(:2rounds));

sleep 20;

@promises.push: start $oscar.play(:1rounds);

await @promises;
