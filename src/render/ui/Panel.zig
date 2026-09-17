//! Panel — in-game HUD overlay with resource counts, building menu, and info panel.
//!
//! Draws a semi-transparent bar at the top of the screen showing:
//! - Resource counts (wood, stone, planks, fish, bread, iron, coal, beer, gold)
//! - Building construction menu (F1-F9 categories)
//! - Selected building info
//! - Tool mode indicator

const std = @import("std");
const core = @import("core");
const Font = @import("../Font.zig").Font;
const SpriteBatcher = @import("../sprite_batcher.zig").SpriteBatcher;
const Shader = @import("../Shader.zig").Shader;
const Camera = @import("../Camera.zig").Camera;
const Texture = @import("../Texture.zig");
const Event = @import("Event.zig");
const Rect = Event.Rect;

const Resource = core.Resource;
const Building = core.Building;
const Game = core.game.Game;
const PlayerState = core.PlayerState;
const MapPos = core.types.MapPos;

/// Colours for each resource type in the HUD.
pub const ResourceColors = struct {
    pub fn get(r: Resource) [4]f32 {
        return switch (r) {
            .fish => .{ 0.3, 0.6, 1.0, 1.0 },
            .grain => .{ 0.9, 0.8, 0.2, 1.0 },
            .flour => .{ 0.9, 0.9, 0.8, 1.0 },
            .bread => .{ 0.9, 0.6, 0.2, 1.0 },
            .meat => .{ 0.8, 0.3, 0.3, 1.0 },
            .fruit => .{ 1.0, 0.5, 0.8, 1.0 },
            .beer => .{ 0.8, 0.7, 0.1, 1.0 },
            .wine => .{ 0.6, 0.1, 0.4, 1.0 },
            .gold => .{ 1.0, 0.8, 0.1, 1.0 },
            .iron_ore => .{ 0.5, 0.4, 0.3, 1.0 },
            .iron => .{ 0.6, 0.6, 0.6, 1.0 },
            .coal => .{ 0.2, 0.2, 0.2, 1.0 },
            .stone => .{ 0.5, 0.5, 0.5, 1.0 },
            .wood => .{ 0.4, 0.7, 0.3, 1.0 },
            .planks => .{ 0.6, 0.5, 0.3, 1.0 },
            else => .{ 1.0, 1.0, 1.0, 1.0 },
        };
    }
};

/// Resources shown in the main HUD row (top bar).
const hud_resources = [_]Resource{
    .wood, .planks, .stone, .fish, .bread, .iron, .coal, .beer, .gold,
};

/// Building types shown in the build menu, laid out as a grid of icons that
/// can be clicked with the mouse (F1-F9 still select the first nine as
/// shortcuts). Order roughly follows the original freeserf construction popups
/// (basic → food → advanced → mines → military). Only buildings that have a
/// sprite are listed.
pub const BUILD_MENU = [_]Building{
    .lumberjack,    .forester,   .stonecutter,  .fisher,
    .farm,          .mill,       .bakery,       .pig_farm,
    .slaughterhouse, .sawmill,   .iron_smelter, .gold_smelter,
    .toolmaker,     .armory,     .boatbuilder,  .stock,
    .coal_mine,     .iron_mine,  .gold_mine,    .granite_mine,
    .tower,         .fortress,
};

/// Number of icon columns in the build-menu grid.
pub const MENU_COLS: usize = 4;

/// Building names for the build menu.
pub fn buildingName(b: Building) []const u8 {
    return switch (b) {
        .lumberjack => "Lumberjack",
        .stonecutter => "Stonecutter",
        .fisher => "Fisher",
        .forester => "Forester",
        .sawmill => "Sawmill",
        .farm => "Farm",
        .mill => "Mill",
        .tower => "Tower",
        .stock => "Stock",
        .bakery => "Bakery",
        .slaughterhouse => "Slaughterhouse",
        .pig_farm => "Pig Farm",
        .iron_smelter => "Smelter",
        .gold_smelter => "Gold Smelter",
        .toolmaker => "Toolmaker",
        .armory => "Armory",
        .boatbuilder => "Boatbuilder",
        .coal_mine => "Coal Mine",
        .iron_mine => "Iron Mine",
        .gold_mine => "Gold Mine",
        .granite_mine => "Granite Mine",
        .fortress => "Fortress",
        else => "Unknown",
    };
}

/// HUD top bar height in pixels.
pub const TOP_BAR_H: f32 = 36.0;
/// HUD left panel width in pixels.
pub const LEFT_PANEL_W: f32 = 180.0;
/// Building menu icon size.
pub const ICON_SIZE: f32 = 28.0;
/// Padding between HUD elements.
pub const PAD: f32 = 4.0;

/// The in-game HUD panel.
pub const Panel = struct {
    /// Screen dimensions (set on resize).
    screen_w: f32 = 1024,
    screen_h: f32 = 768,
    /// Selected building type for placement.
    selected_building: Building = .none,
    /// Current tool mode.
    tool_mode: Event.ToolMode = .none,
    /// Mouse position (screen coords).
    mouse_x: f32 = 0,
    mouse_y: f32 = 0,
    /// Building menu regions for click detection (one per BUILD_MENU entry).
    menu_regions: [BUILD_MENU.len]Event.PanelRegion = undefined,
    /// Whether the panel is visible.
    visible: bool = true,

    pub fn init() Panel {
        var p = Panel{};
        p.layoutMenuRegions();
        return p;
    }

    fn layoutMenuRegions(self: *Panel) void {
        const start_x = 4.0;
        const start_y = TOP_BAR_H + PAD;
        const cell = ICON_SIZE + PAD;
        for (&self.menu_regions, 0..) |*region, i| {
            const col = i % MENU_COLS;
            const row = i / MENU_COLS;
            region.* = .{
                .rect = .{
                    .x = start_x + @as(f32, @floatFromInt(col)) * cell,
                    .y = start_y + @as(f32, @floatFromInt(row)) * cell,
                    .width = ICON_SIZE,
                    .height = ICON_SIZE,
                },
                .id = @intCast(i),
                .tooltip = buildingName(BUILD_MENU[i]),
            };
        }
    }

    /// Hit-test the build-menu icons. Returns the building under (mx,my) without
    /// changing state — the caller selects it and activates the placer.
    pub fn menuHit(self: *const Panel, mx: f32, my: f32) ?Building {
        if (!self.visible) return null;
        for (self.menu_regions, 0..) |region, i| {
            if (region.contains(mx, my)) return BUILD_MENU[i];
        }
        return null;
    }

    /// Update screen dimensions (call on window resize).
    pub fn setScreenSize(self: *Panel, w: f32, h: f32) void {
        self.screen_w = w;
        self.screen_h = h;
    }

    /// Handle a mouse click. Returns the building type to place, or .none.
    pub fn handleClick(self: *Panel, mx: f32, my: f32, button: Event.MouseButton) ?Building {
        if (!self.visible) return null;
        if (button != .left) return null;

        // Check building menu clicks
        for (&self.menu_regions, 0..) |region, i| {
            if (region.contains(mx, my)) {
                self.selected_building = BUILD_MENU[i];
                self.tool_mode = .place_building;
                return self.selected_building;
            }
        }

        // Click outside panel = place building at map position (handled by app.zig)
        if (my > TOP_BAR_H + ICON_SIZE + PAD * 2) {
            if (self.tool_mode == .place_building) {
                return self.selected_building;
            }
        }

        return null;
    }

    /// Handle right-click — cancel current tool.
    pub fn handleRightClick(self: *Panel) void {
        self.tool_mode = .none;
        self.selected_building = .none;
    }

    /// Draw the HUD overlay — background only (semi-transparent top bar).
    /// No colored chips — the resource display is text-only.
    /// These use the fallback white 1x1 texture and must be flushed before
    /// `drawText` (which uses the font atlas texture).
    pub fn drawBackground(self: *Panel, batcher: *SpriteBatcher, font: *Font, game: *Game) void {
        _ = game; // game state is only needed for text (resource counts)
        if (!self.visible) return;

        const sw = self.screen_w;

        // ── Top bar background (semi-transparent black) ──
        batcher.add(.{
            .x = 0, .y = 0,
            .width = sw, .height = TOP_BAR_H,
            .u = 0, .v = 0, .uw = 0, .vh = 0,
            .r = 0.0, .g = 0.0, .b = 0.0, .a = 0.6,
        });

        // ── Building menu grid ──
        // Cell backgrounds + selection highlight here (white-texture batch);
        // the building-sprite icon itself is drawn by app.zig over the top with
        // the atlas texture bound. Hover tooltips are drawn last so they sit on
        // top of neighbouring cells.
        for (&self.menu_regions, 0..) |region, i| {
            const bx = region.rect.x;
            const by = region.rect.y;
            const is_selected = self.selected_building == BUILD_MENU[i];
            const hovered = region.contains(self.mouse_x, self.mouse_y);

            const bg: [4]f32 = if (is_selected)
                .{ 0.3, 0.65, 0.3, 0.9 }
            else if (hovered)
                .{ 0.35, 0.35, 0.35, 0.8 }
            else
                .{ 0.15, 0.15, 0.15, 0.7 };
            batcher.add(.{
                .x = bx, .y = by,
                .width = ICON_SIZE, .height = ICON_SIZE,
                .u = 0, .v = 0, .uw = 0, .vh = 0,
                .r = bg[0], .g = bg[1], .b = bg[2], .a = bg[3],
            });
        }

        // Tooltips (drawn after all cells so they overlay neighbours).
        for (&self.menu_regions) |region| {
            if (region.contains(self.mouse_x, self.mouse_y)) {
                const bx = region.rect.x;
                const by = region.rect.y;
                const tip_w = font.textWidth(region.tooltip, 0.6) + 8;
                batcher.add(.{
                    .x = bx, .y = by - 14,
                    .width = tip_w, .height = 12,
                    .u = 0, .v = 0, .uw = 0, .vh = 0,
                    .r = 0.0, .g = 0.0, .b = 0.0, .a = 0.8,
                });
            }
        }
    }

    /// Draw the HUD overlay — text only (resource counts, tooltip text,
    /// building info, tool mode indicator). Must be called after
    /// `drawBackground` and flushed with the font atlas texture bound.
    pub fn drawText(self: *Panel, batcher: *SpriteBatcher, font: *Font, game: *Game) void {
        if (!self.visible) return;

        const sw = self.screen_w;
        const menu_y = TOP_BAR_H + PAD;

        // ── Resource count text (text-only, no colored chips) ──
        // Format: "Wood: 20" with full resource name + count.
        // Font scale 1.5 for readability (4×6 bitmap → 6×9 on screen).
        // Spacing 112px fits all 9 resources in a 1024px-wide window
        // with room for 3-digit counts (e.g. "Planks: 999" = 99px).
        const player = &game.state.players.players[0];
        var rx: f32 = 8.0;
        const ry: f32 = 9.0; // vertically centered in 36px bar
        const text_scale: f32 = 1.5;
        const col_w: f32 = 112.0; // spacing per resource entry
        for (hud_resources) |res| {
            const val = player.resources[@intFromEnum(res)];
            font.drawFmt(batcher, "{s}: {}", .{ res.name(), val }, rx, ry, .{ 1, 1, 1, 1 }, text_scale);
            rx += col_w;
            if (rx > sw - 50) break;
        }

        // ── Tooltip text ──
        for (&self.menu_regions) |region| {
            if (region.contains(self.mouse_x, self.mouse_y)) {
                const bx = region.rect.x;
                const by = region.rect.y;
                font.drawText(batcher, region.tooltip, bx + 4, by - 13, .{ 1, 1, 1, 1 }, 0.6);
            }
        }

        // ── Selected building info (right side) ──
        if (self.selected_building != .none) {
            const info_x = sw - 160;
            const info_y = menu_y;
            const name = buildingName(self.selected_building);
            font.drawText(batcher, name, info_x, info_y, .{ 1, 1, 0.6, 1 }, 0.8);
            font.drawText(batcher, "[Click map to place]", info_x, info_y + 14, .{ 0.7, 0.7, 0.7, 1 }, 0.5);

            // Construction cost
            var ci: f32 = 0;
            const costs = BuildingManager.getConstructionCost(self.selected_building);
            if (costs.wood > 0) {
                font.drawFmt(batcher, "W:{}", .{costs.wood}, info_x, info_y + 26 + ci * 12, .{ 0.4, 0.7, 0.3, 1 }, 0.5);
                ci += 1;
            }
            if (costs.stone > 0) {
                font.drawFmt(batcher, "S:{}", .{costs.stone}, info_x, info_y + 26 + ci * 12, .{ 0.5, 0.5, 0.5, 1 }, 0.5);
                ci += 1;
            }
            if (costs.planks > 0) {
                font.drawFmt(batcher, "P:{}", .{costs.planks}, info_x, info_y + 26 + ci * 12, .{ 0.6, 0.5, 0.3, 1 }, 0.5);
            }
        }

        // ── Tool mode indicator ──
        if (self.tool_mode == .place_building and self.selected_building != .none) {
            const mode_text = std.fmt.allocPrint(std.heap.page_allocator, "Building: {s} — Click map to place (Right-click cancel)", .{buildingName(self.selected_building)}) catch "";
            defer if (mode_text.len > 0) std.heap.page_allocator.free(mode_text);
            const tw = font.textWidth(mode_text, 0.6);
            font.drawText(batcher, mode_text, (sw - tw) / 2.0, self.screen_h - 16, .{ 1, 1, 0.6, 0.9 }, 0.6);
        }

        // ── Road building mode indicator ──
        if (self.tool_mode == .build_road) {
            const tw = font.textWidth("Road mode: click two flags (Right-click cancel)", 0.6);
            font.drawText(batcher, "Road mode: click two flags (Right-click cancel)", (sw - tw) / 2.0, self.screen_h - 16, .{ 1, 1, 0.6, 0.9 }, 0.6);
        }
    }
};

// Import for construction costs:
const BuildingManager = struct {
    pub fn getConstructionCost(b: Building) struct { wood: u16, stone: u16, planks: u16 } {
        return switch (b) {
            .stonecutter => .{ .wood = 1, .stone = 0, .planks = 1 },
            .lumberjack => .{ .wood = 1, .stone = 0, .planks = 1 },
            .boatbuilder => .{ .wood = 2, .stone = 0, .planks = 2 },
            .sawmill => .{ .wood = 2, .stone = 0, .planks = 2 },
            .forester => .{ .wood = 1, .stone = 0, .planks = 1 },
            .fisher => .{ .wood = 2, .stone = 0, .planks = 1 },
            .farm => .{ .wood = 2, .stone = 0, .planks = 2 },
            .mill => .{ .wood = 2, .stone = 1, .planks = 2 },
            .bakery => .{ .wood = 2, .stone = 1, .planks = 2 },
            .slaughterhouse => .{ .wood = 1, .stone = 0, .planks = 2 },
            .pig_farm => .{ .wood = 2, .stone = 0, .planks = 2 },
            .iron_smelter => .{ .wood = 2, .stone = 1, .planks = 2 },
            .gold_smelter => .{ .wood = 2, .stone = 1, .planks = 2 },
            .toolmaker => .{ .wood = 2, .stone = 1, .planks = 2 },
            .armory => .{ .wood = 2, .stone = 1, .planks = 2 },
            .brewery => .{ .wood = 2, .stone = 1, .planks = 2 },
            .winery => .{ .wood = 2, .stone = 1, .planks = 2 },
            .coal_mine => .{ .wood = 2, .stone = 0, .planks = 2 },
            .iron_mine => .{ .wood = 2, .stone = 0, .planks = 2 },
            .gold_mine => .{ .wood = 2, .stone = 0, .planks = 2 },
            .granite_mine => .{ .wood = 2, .stone = 0, .planks = 2 },
            .tower => .{ .wood = 3, .stone = 2, .planks = 2 },
            .fortress => .{ .wood = 5, .stone = 5, .planks = 4 },
            .stock => .{ .wood = 3, .stone = 2, .planks = 3 },
            else => .{ .wood = 1, .stone = 0, .planks = 1 },
        };
    }
};