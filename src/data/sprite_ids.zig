//! Sprite IDs — known sprite indices in the SPAE.PA archive.
//!
//! These IDs are based on the original Settlers (1993) data format
//! and the C# Freeserf sprite definitions. The actual IDs may vary
//! slightly between language versions (SPAE=English, SPAD=German, etc.).

/// Terrain map tiles (0-199).
pub const Terrain = struct {
    pub const first: u16 = 0;
    pub const grass_0: u16 = 0;
    pub const grass_1: u16 = 1;
    pub const grass_2: u16 = 2;
    pub const water_0: u16 = 10;
    pub const water_1: u16 = 11;
    pub const mountain_0: u16 = 20;
    pub const mountain_1: u16 = 21;
    pub const sand: u16 = 30;
    pub const snow: u16 = 35;
    pub const swamp: u16 = 40;
    pub const lava: u16 = 45;
    pub const last: u16 = 199;
};

/// Building sprites (200-299).
pub const Building = struct {
    pub const first: u16 = 200;
    pub const lumberjack: u16 = 200;
    pub const stonecutter: u16 = 201;
    pub const fisher: u16 = 202;
    pub const forester: u16 = 203;
    pub const sawmill: u16 = 204;
    pub const boatbuilder: u16 = 205;
    pub const farm: u16 = 206;
    pub const mill: u16 = 207;
    pub const bakery: u16 = 208;
    pub const slaughterhouse: u16 = 209;
    pub const pig_farm: u16 = 210;
    pub const brewery: u16 = 211;
    pub const winery: u16 = 212;
    pub const coal_mine: u16 = 213;
    pub const iron_mine: u16 = 214;
    pub const gold_mine: u16 = 215;
    pub const granite_mine: u16 = 216;
    pub const iron_smelter: u16 = 217;
    pub const gold_smelter: u16 = 218;
    pub const armory: u16 = 219;
    pub const toolmaker: u16 = 220;
    pub const stock: u16 = 221;
    pub const tower: u16 = 222;
    pub const fortress: u16 = 223;
    pub const last: u16 = 240;

    /// Get the sprite ID for a game Building enum.
    pub fn fromGameBuilding(b: core.Building) ?u16 {
        return switch (b) {
            .lumberjack => 200,
            .stonecutter => 201,
            .fisher => 202,
            .forester => 203,
            .sawmill => 204,
            .boatbuilder => 205,
            .farm => 206,
            .mill => 207,
            .bakery => 208,
            .slaughterhouse => 209,
            .pig_farm => 210,
            .brewery => 211,
            .winery => 212,
            .coal_mine => 213,
            .iron_mine => 214,
            .gold_mine => 215,
            .granite_mine => 216,
            .iron_smelter => 217,
            .gold_smelter => 218,
            .armory => 219,
            .toolmaker => 220,
            .stock => 221,
            .tower => 222,
            .fortress => 223,
            else => null,
        };
    }
};

/// Serf sprites (300-499).
pub const Serf = struct {
    pub const first: u16 = 300;
    pub const walk_base: u16 = 300;
    pub const last: u16 = 500;
};

/// UI elements (500+).
pub const UI = struct {
    pub const first: u16 = 500;
    pub const panel_bg: u16 = 500;
    pub const button: u16 = 510;
    pub const resource_icon_base: u16 = 600;
    pub const last: u16 = 1000;
};

/// Font glyphs (typically 1000+).
pub const Font = struct {
    pub const first: u16 = 1000;
    pub const char_base: u16 = 1000;
    pub const last: u16 = 1128;
};

const core = @import("core");
