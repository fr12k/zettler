//! Renderer — OpenGL rendering abstraction.
//!
//! This module provides the rendering interface for the game.
//! In the C# version, rendering is done via OpenTK (OpenGL). The Zig
//! version will use raw OpenGL via GLFW.
//!
//! This is a minimal stub that provides the renderer API surface
//! without implementing the actual OpenGL calls.

const std = @import("std");
const core = @import("core");

const Vec2i = core.Vec2i;
const Vec2f = core.Vec2f;
const Mat4 = core.Mat4;
const Rect = core.Rect;

/// Clear color components.
pub const ClearColor = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,

    pub const black: ClearColor = .{ .r = 0, .g = 0, .b = 0, .a = 1 };
    pub const white: ClearColor = .{ .r = 1, .g = 1, .b = 1, .a = 1 };
    pub const sky: ClearColor = .{ .r = 0.4, .g = 0.6, .b = 0.8, .a = 1 };
};

/// Renderer state and configuration.
pub const Renderer = struct {
    /// Viewport rectangle.
    viewport: Rect = .{ .x = 0, .y = 0, .width = 800, .height = 600 },
    /// Projection matrix.
    projection: Mat4 = Mat4.ortho(0, 800, 600, 0, -1, 1),
    /// Clear color.
    clear_color: ClearColor = .sky,

    /// Initialize the renderer (create shaders, buffers, etc.).
    pub fn init(self: *Renderer) void {
        _ = self;
        // Future: compile shaders, create VAO/VBO, etc.
    }

    /// Begin a new frame.
    pub fn beginFrame(self: *Renderer) void {
        _ = self;
        // Future: glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)
    }

    /// End the current frame (swap buffers).
    pub fn endFrame(self: *Renderer) void {
        _ = self;
        // Future: swap buffers
    }

    /// Set the viewport.
    pub fn setViewport(self: *Renderer, x: i32, y: i32, w: i32, h: i32) void {
        self.viewport = .{
            .x = @floatFromInt(x),
            .y = @floatFromInt(y),
            .width = @floatFromInt(w),
            .height = @floatFromInt(h),
        };
        self.projection = Mat4.ortho(
            @floatFromInt(x),
            @floatFromInt(x + w),
            @floatFromInt(y + h),
            @floatFromInt(y),
            -1, 1,
        );
    }

    /// Draw a filled rectangle.
    pub fn drawRect(_: *Renderer, rect: Rect, color: ClearColor) void {
        _ = rect;
        _ = color;
        // Future: draw a colored quad
    }

    /// Draw a sprite at the given position.
    pub fn drawSprite(_: *Renderer, sprite_index: u16, pos: Vec2i) void {
        _ = sprite_index;
        _ = pos;
        // Future: bind sprite texture, draw textured quad
    }

    /// Draw a sprite with scaling.
    pub fn drawSpriteScaled(_: *Renderer, sprite_index: u16, rect: Rect) void {
        _ = sprite_index;
        _ = rect;
        // Future: textured quad with given rect
    }

    /// Draw text using the bitmap font.
    pub fn drawText(_: *Renderer, text: []const u8, pos: Vec2i, color: ClearColor) void {
        _ = text;
        _ = pos;
        _ = color;
        // Future: render bitmap font glyphs
    }

    /// Shutdown the renderer (free GPU resources).
    pub fn deinit(self: *Renderer) void {
        _ = self;
        // Future: delete shaders, VAOs, VBOs, textures
    }
};
