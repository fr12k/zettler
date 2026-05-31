//! Serialization module — re-exports all serialization types.

pub const State = @import("State.zig").State;
pub const DirtyFlags = @import("State.zig").DirtyFlags;
pub const Serializer = @import("Serializer.zig").Serializer;
pub const Deserializer = @import("Deserializer.zig").Deserializer;
pub const Savegame = @import("Savegame.zig").Savegame;
