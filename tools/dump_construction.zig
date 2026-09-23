//! Dump the AssetMapObject construction-related sprite entries from SPAE.PA:
//!   0x90 (144) = foundation cross / PLAN
//!   0x91 (145) = corner stone
//!   0xaf-0xc1 (175-193) = wooden scaffold "frame" sprites (map_building_frame_sprite)
//! Confirms which entries are empty (size 0) in this particular data file,
//! which is why the Zig renderer can't use the freeserf scaffold approach.
const std = @import("std");
const data = @import("data");

pub fn main() !void {
    const a = std.heap.page_allocator;
    const path = "data/SPAE.PA";
    const c_path = try std.fmt.allocPrint(a, "{s}\x00", .{path});
    defer a.free(c_path);
    const fd = std.c.open(@ptrCast(c_path.ptr), .{});
    if (fd < 0) { std.debug.print("SPAE.PA not found\n", .{}); return; }
    defer _ = std.c.close(fd);
    const file_size = std.c.lseek(fd, 0, std.c.SEEK.END);
    _ = std.c.lseek(fd, 0, std.c.SEEK.SET);
    const raw = try a.alloc(u8, @intCast(file_size));
    defer a.free(raw);
    _ = std.c.read(fd, raw.ptr, @intCast(file_size));
    var pak = try data.PakFile.init(a, raw);
    defer pak.deinit();

    const base: u16 = 1250; // AssetMapObject
    std.debug.print("File count: {}  (AssetMapObject base = {})\n", .{ pak.fileCount(), base });
    std.debug.print("--- construction sprites (PAK index = base + hex) ---\n", .{});

    const range = [_]struct { hex: u16, name: []const u8 }{
        .{ .hex = 0x90, .name = "PLAN / foundation cross" },
        .{ .hex = 0x91, .name = "corner stone" },
        .{ .hex = 0xaf, .name = "frame: fortress" },
        .{ .hex = 0xb0, .name = "frame: toolmaker" },
        .{ .hex = 0xb1, .name = "frame: farm/pig_farm" },
        .{ .hex = 0xb3, .name = "frame: tower" },
        .{ .hex = 0xb4, .name = "frame: gold_smelter" },
        .{ .hex = 0xb5, .name = "frame: sawmill" },
        .{ .hex = 0xb6, .name = "frame: iron_smelter" },
        .{ .hex = 0xb7, .name = "frame: bakery" },
        .{ .hex = 0xb8, .name = "frame: slaughterhouse/armory" },
        .{ .hex = 0xb9, .name = "frame: mines" },
        .{ .hex = 0xba, .name = "frame: small (fisher/lumberjack/etc)" },
        .{ .hex = 0xbb, .name = "frame: mill" },
        .{ .hex = 0xc0, .name = "building: stock" },
        .{ .hex = 0xc1, .name = "frame: stock" },
    };

    for (range) |r| {
        const idx: u16 = base + r.hex;
        if (idx >= pak.fileCount()) {
            std.debug.print("  PAK {d} (0x{x:0>2}) {s}: PAST END\n", .{ idx, r.hex, r.name });
            continue;
        }
        const d = pak.getFile(idx) catch {
            std.debug.print("  PAK {d} (0x{x:0>2}) {s}: READ ERROR\n", .{ idx, r.hex, r.name });
            continue;
        };
        if (d.len == 0) {
            std.debug.print("  PAK {d} (0x{x:0>2}) {s}: EMPTY (0 bytes)\n", .{ idx, r.hex, r.name });
            continue;
        }
        if (d.len < 10) {
            std.debug.print("  PAK {d} (0x{x:0>2}) {s}: {d}b (header < 10)\n", .{ idx, r.hex, r.name, d.len });
            continue;
        }
        const w: u16 = std.mem.readInt(u16, d[2..4], .little);
        const h: u16 = std.mem.readInt(u16, d[4..6], .little);
        const ox: i16 = std.mem.readInt(i16, d[6..8], .little);
        const oy: i16 = std.mem.readInt(i16, d[8..10], .little);
        const solid = (d.len == 10 + @as(usize, w) * h);
        std.debug.print("  PAK {d} (0x{x:0>2}) {s}: {d}x{d} off=({d},{d}) {d}b {s}\n", .{
            idx, r.hex, r.name, w, h, ox, oy, d.len, if (solid) "solid" else "RLE",
        });
    }

    // Also: freeserf draws construction progress by clipping ONE sprite vertically
    // (progress float -> y_off in gfx.cc), NOT by storing multiple frames. Confirm
    // there is only a single sprite per building by listing the 24 building slots.
    std.debug.print("--- one sprite per building (no progress frames stored) ---\n", .{});
    const building_hex = [_]u16{ 0x98, 0x99, 0x9a, 0x9b, 0x9c, 0x9d, 0x9e, 0x9f, 0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xab, 0xae, 0xb2, 0xbc, 0xc0 };
    for (building_hex) |hx| {
        const idx: u16 = base + hx;
        const d = pak.getFile(idx) catch { std.debug.print("  0x{x:0>2} PAK {d}: ERR\n", .{ hx, idx }); continue; };
        if (d.len < 10) { std.debug.print("  0x{x:0>2} PAK {d}: {d}b\n", .{ hx, idx, d.len }); continue; }
        const w: u16 = std.mem.readInt(u16, d[2..4], .little);
        const h: u16 = std.mem.readInt(u16, d[4..6], .little);
        std.debug.print("  0x{x:0>2} PAK {d}: {d}x{d} {d}b\n", .{ hx, idx, w, h, d.len });
    }
}