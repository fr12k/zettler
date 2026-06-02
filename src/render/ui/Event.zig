//! Event — UI input event types and hit-testing utilities.
//!
//! Defines the event model for interactive UI panels:
//! mouse clicks, drags, key presses, and panel regions.

const std = @import("std");

/// A rectangular region for hit-testing UI elements.
pub const Rect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,

    pub fn contains(self: Rect, px: f32, py: f32) bool {
        return px >= self.x and px < self.x + self.width and
            py >= self.y and py < self.y + self.height;
    }
};

/// Mouse button identifiers.
pub const MouseButton = enum(u3) {
    left = 0,
    right = 1,
    middle = 2,
};

/// Mouse event data.
pub const MouseEvent = struct {
    button: MouseButton,
    x: f64,
    y: f64,
    pressed: bool,
};

/// Key event data.
pub const KeyEvent = struct {
    key: c_int,
    scancode: c_int,
    pressed: bool,
    mods: c_int,
};

/// A UI panel region with optional label and callback type tag.
pub const PanelRegion = struct {
    rect: Rect,
    id: u32 = 0,
    tooltip: []const u8 = "",

    pub fn contains(self: PanelRegion, px: f32, py: f32) bool {
        return self.rect.contains(px, py);
    }
};

/// Tool mode — what the user is currently doing.
pub const ToolMode = enum(u3) {
    none,             // no tool active
    place_building,   // placing a building
    build_road,       // building a road
    demolish,         // demolishing a building
};

/// Screen-space helpers for camera-independent UI layout.
pub const Screen = struct {
    width: f32,
    height: f32,

    pub fn centerX(self: Screen) f32 { return self.width / 2.0; }
    pub fn centerY(self: Screen) f32 { return self.height / 2.0; }
    pub fn center(self: Screen) [2]f32 { return .{ self.centerX(), self.centerY() }; }
    pub fn right(self: Screen) f32 { return self.width; }
    pub fn bottom(self: Screen) f32 { return self.height; }
};