//! Deterministic pseudo-random number generator for game state.
//!
//! The C# version uses a seeded System.Random for reproducible game states.
//! This wraps Zig's DefaultPrng with a consistent 64-bit seed.

const std = @import("std");

/// Seeded PRNG for game logic. Deterministic — same seed = same game.
pub const GameRandom = struct {
    prng: std.Random.DefaultPrng,

    pub fn init(seed: u64) GameRandom {
        return .{ .prng = std.Random.DefaultPrng.init(seed) };
    }

    pub fn random(self: *GameRandom) std.Random {
        return self.prng.random();
    }

    /// Returns a random u32 in [0, max).
    pub fn uintLessThan(self: *GameRandom, max: u32) u32 {
        return self.random().uintLessThan(u32, max);
    }

    /// Returns a random u32 in [min, max].
    pub fn uintRange(self: *GameRandom, min: u32, max: u32) u32 {
        return min + self.random().uintLessThan(u32, max - min + 1);
    }

    /// Returns true with given probability (0.0 to 1.0).
    pub fn chance(self: *GameRandom, probability: f64) bool {
        return self.random().float(f64) < probability;
    }

    /// Returns a random index from 0..count-1.
    pub fn index(self: *GameRandom, count: usize) usize {
        return self.random().uintLessThan(usize, @intCast(count));
    }
};

test "GameRandom determinism" {
    var r1 = GameRandom.init(12345);
    var r2 = GameRandom.init(12345);

    try std.testing.expectEqual(r1.uintLessThan(100), r2.uintLessThan(100));
    try std.testing.expectEqual(r1.uintLessThan(100), r2.uintLessThan(100));
    try std.testing.expectEqual(r1.uintLessThan(100), r2.uintLessThan(100));
}

test "GameRandom different seeds differ" {
    var r1 = GameRandom.init(12345);
    var r2 = GameRandom.init(67890);

    // Very unlikely to collide on first call
    const v1 = r1.uintLessThan(10000);
    const v2 = r2.uintLessThan(10000);
    try std.testing.expect(v1 != v2);
}
