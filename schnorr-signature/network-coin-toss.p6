use CoinToss::Network;
use CoinToss::Player;

my ($alice, $bob, $oscar) = <Alice Bob Oscar>.map: {
    CoinToss::Player.new(:name($_))
};

my $network = CoinToss::Network.new(players => ($alice, $bob, $oscar));

$network.run;
