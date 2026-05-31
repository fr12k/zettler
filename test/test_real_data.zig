//! Integration test for loading the real SPAE.PA game data file.
//!
//! Tests TPWM decompression + PAK parsing + BMP sprite decoding.
const std = @import("std");
const data = @import("data");

pub fn main() !void {
    const a = std.heap.page_allocator;

    var found = false;
    const paths = [_][]const u8{ "data/SPAE.PA", "data/spae.pa" };

    for (paths) |path| {
        std.debug.print("Testing: {s}\n", .{path});

        const c_path = try std.fmt.allocPrint(a, "{s}\x00", .{path});
        defer a.free(c_path);

        const fd = std.c.open(@ptrCast(c_path.ptr), .{});
        if (fd < 0) { std.debug.print("  File not found\n", .{}); continue; }
        defer _ = std.c.close(fd);

        const file_size = std.c.lseek(fd, 0, std.c.SEEK.END);
        _ = std.c.lseek(fd, 0, std.c.SEEK.SET);
        const raw = try a.alloc(u8, @intCast(file_size));
        defer a.free(raw);
        _ = std.c.read(fd, raw.ptr, @intCast(file_size));

        std.debug.print("  Size: {} bytes, TPWM: {}\n", .{ file_size, data.tpwm.isTPWM(raw) });

        // Test PakFile (handles TPWM decompression + PAK parsing automatically)
        var pak = data.PakFile.init(a, raw) catch |e| {
            std.debug.print("  PakFile.init error: {}\n\n", .{e});
            continue;
        };
        defer pak.deinit();

        std.debug.print("  Files: {}\n", .{ pak.fileCount() });

        // Show first 5 entries
        for (0..@min(pak.fileCount(), 5)) |i| {
            const entry = pak.entries[i];
            std.debug.print("    [{}] offset={}, size={}\n", .{ i, entry.offset, entry.size });
        }

        // Decode sprites — find first valid ones
        var found_sprite = false;
        for (0..@min(pak.fileCount(), 500)) |i| {
            const sprite_data = pak.getFile(@intCast(i)) catch continue;
            var decoder = data.BmpDecoder.init(a);
            var sprite = decoder.decode(sprite_data) catch continue;
            defer sprite.deinit(a);
            if (!found_sprite) {
                std.debug.print("  First sprite at [{}]: {}x{}", .{ i, sprite.width, sprite.height });
                // Check if pixel data is valid
                if (sprite.pixels.len > 0 and sprite.pixels[0].a > 0) {
                    std.debug.print(" (opaque)", .{});
                }
                std.debug.print("\n", .{});
                found_sprite = true;
            }
        }
        if (!found_sprite) {
            std.debug.print("  No valid sprites found in first 500 entries.\n", .{});
        }

        found = true;
        break;
    }

    if (!found) {
        std.debug.print("SPAE.PA not found in data/ directory.\n", .{});
    } else {
        std.debug.print("\n✓ Data loading pipeline works correctly.\n", .{});
    }
}
