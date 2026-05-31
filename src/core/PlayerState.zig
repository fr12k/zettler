//! Player state — represents one of up to 6 players.
//!
//! Each player has resources, serfs, buildings, and military statistics.
//! In the C# version this uses dirty-tracking serialization with [Data] attributes.
//! In Zig we track a dirty flags bitset manually.

const std = @import("std");
const serialize = @import("serialize");
const enums = @import("enums.zig");

const Resource = enums.Resource;
const Building = enums.Building;

/// Player state data with dirty-tracking.
pub const PlayerState = struct {
    // --- Resources ---
    resources: [@as(usize, Resource.max_count)]u16 = @splat(0),

    // --- Serfs ---
    serf_count: [@intCast(@intFromEnum(enums.SerfType.count))]u16 = @splat(0),

    // --- Buildings ---
    building_count: [@intCast(Building.count)]u16 = @splat(0),
    active_buildings: u32 = 0,

    // --- Military ---
    knight_count: u16 = 0,
    military_strength: u16 = 0,
    territory_count: u16 = 0,

    // --- Score ---
    score_total: u32 = 0,
    score_serf: u16 = 0,
    score_resource: u16 = 0,
    score_military: u16 = 0,
    score_building: u16 = 0,
    score_territory: u16 = 0,
    score_civilisation: u16 = 0,
    score_time: u16 = 0,

    // --- Flags ---
    inventory_dirty: bool = false,
};

/// Array of player states (max 6 players).
pub const PlayerStates = struct {
    players: [6]PlayerState = @splat(PlayerState{}),
    player_count: u8 = 0,

    pub fn get(self: *PlayerStates, index: usize) *PlayerState {
        return &self.players[index];
    }

    pub fn setPlayerCount(self: *PlayerStates, count: u8) void {
        self.player_count = @min(count, 6);
    }
};
