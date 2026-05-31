//! Inventory — resource buffering for buildings and players.
//!
//! Port of the C# Inventory class. Each building has inventory slots
//! for input and output resources. The inventory system manages:
//! - Resource buffering (input queue, output queue)
//! - In/out mode (push vs pull)
//! - Stock level limits
//! - Distribution requests

const std = @import("std");
const enums = @import("enums.zig");
const serialize = @import("serialize");

const Resource = enums.Resource;

/// Maximum number of resource slots in an inventory.
pub const MaxSlots = 8;

/// Direction of resource flow through this inventory.
pub const InventoryMode = enum(u2) {
    /// Resources flow in (building consumes)
    incoming,
    /// Resources flow out (building produces)
    outgoing,
    /// Both directions
    both,
    /// Inactive / no flow
    none,
};

/// A single resource slot in an inventory.
pub const ResourceSlot = struct {
    resource: Resource = .fish,
    count: u16 = 0,
    capacity: u16 = 0,
};

/// Building inventory — handles resource input/output for a building.
pub const Inventory = struct {
    /// Resource slots (input resources, output resources).
    slots: [MaxSlots]ResourceSlot = @splat(ResourceSlot{}),
    /// Number of active slots.
    slot_count: u8 = 0,
    /// Inventory mode.
    mode: InventoryMode = .none,

    /// Find a slot containing the given resource. Returns null if not found.
    pub fn findSlot(self: Inventory, resource: Resource) ?*const ResourceSlot {
        for (0..self.slot_count) |i| {
            if (self.slots[i].resource == resource) return &self.slots[i];
        }
        return null;
    }

    /// Find a mutable slot containing the given resource.
    pub fn findSlotMut(self: *Inventory, resource: Resource) ?*ResourceSlot {
        for (0..self.slot_count) |i| {
            if (self.slots[i].resource == resource) return &self.slots[i];
        }
        return null;
    }

    /// Add a resource slot.
    pub fn addSlot(self: *Inventory, resource: Resource, capacity: u16) !void {
        if (self.slot_count >= MaxSlots) return error.TooManySlots;
        self.slots[self.slot_count] = .{
            .resource = resource,
            .count = 0,
            .capacity = capacity,
        };
        self.slot_count += 1;
    }

    /// Try to add resources to the inventory. Returns the number actually added.
    pub fn addResource(self: *Inventory, resource: Resource, count: u16) u16 {
        const slot = self.findSlotMut(resource) orelse return 0;
        const space = slot.capacity - slot.count;
        const added = @min(count, space);
        slot.count += added;
        return added;
    }

    /// Try to remove resources from the inventory. Returns the number actually removed.
    pub fn removeResource(self: *Inventory, resource: Resource, count: u16) u16 {
        const slot = self.findSlotMut(resource) orelse return 0;
        const removed = @min(count, slot.count);
        slot.count -= removed;
        return removed;
    }

    /// Check if the inventory has at least `count` of the given resource.
    pub fn hasResource(self: Inventory, resource: Resource, count: u16) bool {
        const slot = self.findSlot(resource) orelse return false;
        return slot.count >= count;
    }

    /// Get the fill percentage (0.0 to 1.0) of a given resource slot.
    pub fn fillPercent(self: Inventory, resource: Resource) f32 {
        const slot = self.findSlot(resource) orelse return 0;
        if (slot.capacity == 0) return 0;
        return @as(f32, slot.count) / @as(f32, slot.capacity);
    }

    /// Check if this inventory is full (all slots at capacity).
    pub fn isFull(self: Inventory) bool {
        for (0..self.slot_count) |i| {
            if (self.slots[i].count < self.slots[i].capacity) return false;
        }
        return true;
    }
};

test "Inventory basic operations" {
    var inv = Inventory{};
    try inv.addSlot(.fish, 10);
    try inv.addSlot(.bread, 5);

    try std.testing.expectEqual(@as(u16, 0), inv.slots[0].count);
    try std.testing.expectEqual(@as(u16, 3), inv.addResource(.fish, 3));
    try std.testing.expectEqual(@as(u16, 3), inv.slots[0].count);
    try std.testing.expect(inv.hasResource(.fish, 3));
    try std.testing.expect(!inv.hasResource(.fish, 4));

    try std.testing.expectEqual(@as(u16, 2), inv.removeResource(.fish, 2));
    try std.testing.expectEqual(@as(u16, 1), inv.slots[0].count);
}

test "Inventory full check" {
    var inv = Inventory{};
    try inv.addSlot(.stone, 1);
    try std.testing.expect(!inv.isFull());
    _ = inv.addResource(.stone, 1);
    try std.testing.expect(inv.isFull());
}
