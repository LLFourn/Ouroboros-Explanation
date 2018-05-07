// Rust version of the game described in:
// https://medium.com/unraveling-the-ouroboros/coin-flipping-with-discrete-logarithms-91c563d38d2
extern crate num_bigint;
extern crate rand;
#[macro_use]
extern crate lazy_static;
#[macro_use]
extern crate num_derive;
extern crate num_traits;
extern crate num_integer;

use num_traits::FromPrimitive;
use num_bigint::{BigUint, ToBigUint, RandBigInt};
use std::io::{self, BufRead};
use std::ops::{Rem};
use num_integer::{Integer};

#[derive(Debug)]
enum Player { Alice, Rob }
#[derive(FromPrimitive, Debug, PartialEq)]
enum Coin { Heads, Tails }

// lazy_static is some hack to set up static references that are
// initialised when they're first needed.
lazy_static! {
    static ref p: BigUint = BigUint::parse_bytes(b"FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA63B139B22514A08798E3404DDEF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7EDEE386BFB5A899FA5AE9F24117C4B1FE649286651ECE45B3DC2007CB8A163BF0598DA48361C55D39A69163FA8FD24CF5F83655D23DCA3AD961C62F356208552BB9ED529077096966D670C354E4ABC9804F1746C08CA237327FFFFFFFFFFFFFFFF", 16).unwrap();

    static ref q: BigUint = &*p / 2.to_biguint().unwrap();
    static ref g: BigUint = 2.to_biguint().unwrap();
}

// How each type of value should be formatted
trait MessageValue {
    fn gist(&self) -> String;
}

impl MessageValue for BigUint {
    fn gist(&self) -> String {
        format!("0x{:x}", self)
    }
}

impl MessageValue for Coin {
    fn gist(&self) -> String {
        format!("{:?}", self)
    }
}

const GREEN : &'static str = "\x1b[32m";
const RESET : &'static str = "\x1b[0m";

// Prints out a nicely formatted message
fn send(sender: Player, message: Vec<(&str, &MessageValue)>) {
    let header = format!(">>>====={:?} sends====>>>", sender);

    println!("{}{}{}", GREEN, header, RESET);
    for &(key, value) in message.iter() {
        println!("{}: {}", key, value.gist());
    }
    println!("{}{}{}", GREEN, "=".repeat(header.chars().count()), RESET);
}

// If a number is below 0
fn floor_zero(number: usize) -> usize {
    if number > 0 { number as usize } else { 0 }
}

// Reads a line and then overwrites the input with XXXXXXs
fn read_line() -> String {
    let stdin = io::stdin();
    let line = stdin.lock().lines().next().unwrap().unwrap();
    let spaces = floor_zero(line.chars().count() as usize - 40);

    println!("\x1b[A\r{}{}", "X".repeat(40), " ".repeat(spaces));
    line
}

// Reads a line from stdin and validates and transforms
// it using parse(). I'm not really sure why this needs to be &Fn.
fn secret_prompt<T>(parse: &Fn(&str) -> Option<T>) -> T {
    let line = read_line();

    match parse(line.as_ref()) {
        Some(v) => v,
        None => {
            println!("Invalid value. Try again.");
            secret_prompt(parse)
        }
    }
}

// Prompts the player for Heads/Tails
fn choose_move(player: Player) -> Coin {
    println!("{:?}, choose an outcome.", player);
    println!("[H]eads or [T]ails?");

    secret_prompt(&|line| {
        match line {
            "H"|"h" => Some(Coin::Heads),
            "t"|"T" => Some(Coin::Tails),
            _       => None
        }
    })
}

// converts a str to Option<BigInt>
fn parse_bigint(string : &str) -> Option<BigUint> {
    match string.parse::<BigUint>() {
        Ok(big) => Some(big),
        _ => None
    }
}

// Prompts the player to choose their randomness
fn choose_randomness(player: Player) -> BigUint {
    println!("{:?}, behave [H]onestly? or enter your own integer:", player);
    secret_prompt(&|line|{
        match line {
            "H"|"h" => {
                let mut rng = rand::thread_rng();
                Some(rng.gen_biguint_below(&*q))
            }
            _ => { parse_bigint(line.as_ref()) }
        }
    })
}

// returns the DLOG based commitment for value
fn commit(value: &BigUint) -> BigUint {
    g.modpow(value, &*p)
}

// Prompts the player (Alice) for what they claim their randomness was
fn claim(player: Player, hint: &BigUint) -> BigUint {
    println!(
        "{:?}, what do you claim your randomness was?\n([H] to use the true value)",
        player
    );

    secret_prompt(&|line| {
        match line {
            // Is clone the right thing to do here? I wonder if
            // there's some way to design secret_prompt to avoid it.
            "H" | "h" => Some(hint.to_owned()),
            _ => { parse_bigint(line.as_ref()) }
        }
    })
}

// Checks whether Alice or Rob won
fn check_result(alice_move: Coin, randomness: &BigUint) {
    let odd = randomness.rem(&*g).is_odd();
    let coin_toss = Coin::from_u32(odd as u32).expect("coin_toss wasn't odd or even O.o");
    let result = alice_move == coin_toss;
    println!(
        "============
The final random number is: {}
Which is {}. So, the coin toss resulted in {:?}
Alice chose {:?}, so {}, wins!",
        randomness.gist(),
        (if odd { "odd"} else {"even"}),
        coin_toss,
        alice_move,
        (if result { "Alice"} else {"Rob"})
    );
}

fn main() {
    let m = choose_move(Player::Alice);
    let s_a = choose_randomness(Player::Alice);
    let c = commit(&s_a);
    // Alice sends her commitment and her move int he clear to Rob
    send(Player::Alice, vec!(("move", &m), ("commitment", &c)));

    // Rob sends his randomness in the clear to Alice
    let s_r = choose_randomness(Player::Rob);
    send(Player::Rob, vec!(("randomness", &s_r)));

    // Alice sends her claim to Rob
    let s_a_prime = claim(Player::Alice, &s_a);
    send(Player::Alice, vec!(("randomness", &s_a_prime)));

    // Calculate what the commitment should be from the claim
    let c_prime = commit(&s_a_prime);

    // Check they're the same
    if c_prime == c {
        println!("Alice's claim is the same as her commitment.");
        let s = s_a_prime ^ s_r;
        check_result(m, &s);
    }
    else {
        println!("Alice's claim: {}", c_prime.gist());
        println!("Alice is lying! Her claim is not the same as her commitment");
        println!("Rob wins by default");
    }
}
