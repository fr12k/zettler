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

    var pak = data.PakFile.init(a, raw) catch |e| {
        std.debug.print("PAK error: {}\n", .{e});
        return;
    };
    defer pak.deinit();
    std.debug.print("Total files: {}\n\n", .{pak.fileCount()});

    // Correct header layout (10 bytes):
    //   [0]   s8  delta_x
    //   [1]   s8  delta_y
    //   [2-3] u16 width
    //   [4-5] u16 height
    //   [6-7] s16 offset_x
    //   [8-9] s16 offset_y

    std.debug.print("=== All sprites >= 20x20 (correct header) ===\n", .{});
    var big_count: usize = 0;
    for (0..pak.fileCount()) |i| {
        const sprite_data = pak.getFile(@intCast(i)) catch continue;
        if (sprite_data.len < 10) continue;
        const w: u32 = std.mem.readInt(u16, sprite_data[2..4], .little);
        const h: u32 = std.mem.readInt(u16, sprite_data[4..6], .little);
        if (w == 0 or h == 0 or w > 640 or h > 640) continue;
        if (w >= 20 and h >= 20) {
            const solid = sprite_data.len == 10 + w * h;
            std.debug.print("  [{d:4}] {d}x{d} ({}b, {s})\n", .{ i, w, h, sprite_data.len, if (solid) "solid" else "rle" });
            big_count += 1;
            if (big_count > 200) { std.debug.print("  ... (truncated)\n", .{}); break; }
        }
    }
    std.debug.print("\nTotal big sprites: {}\n\n", .{big_count});

    // Show first 30 sprites with correct dimensions
    std.debug.print("=== First 30 sprites ===\n", .{});
    for (0..@min(pak.fileCount(), 30)) |i| {
        const sprite_data = pak.getFile(@intCast(i)) catch {
            std.debug.print("  [{d}] error\n", .{i}); continue;
        };
        if (sprite_data.len < 10) {
            std.debug.print("  [{d}] too small ({}b)\n", .{i, sprite_data.len}); continue;
        }
        const dx: i8 = @bitCast(sprite_data[0]);
        const dy: i8 = @bitCast(sprite_data[1]);
        const w: u32 = std.mem.readInt(u16, sprite_data[2..4], .little);
        const h: u32 = std.mem.readInt(u16, sprite_data[4..6], .little);
        const ox: i16 = std.mem.readInt(i16, sprite_data[6..8], .little);
        const oy: i16 = std.mem.readInt(i16, sprite_data[8..10], .little);
        const solid = sprite_data.len == 10 + w * h;
        std.debug.print("  [{d:2}] {d}x{d} dx={d} dy={d} ox={d} oy={d} {}b {s}\n",
            .{ i, w, h, dx, dy, ox, oy, sprite_data.len, if (solid) "solid" else "rle" });
    }

    // Raw byte dumps
    const dump_ids = [_]u16{ 0, 3, 4, 100, 180, 200, 460 };
    std.debug.print("\n=== Raw byte dumps (first 24 bytes) ===\n", .{});
    for (dump_ids) |idx| {
        if (idx >= pak.fileCount()) continue;
        const sprite_data = pak.getFile(idx) catch continue;
        const w: u32 = if (sprite_data.len >= 4) std.mem.readInt(u16, sprite_data[2..4], .little) else 0;
        const h: u32 = if (sprite_data.len >= 6) std.mem.readInt(u16, sprite_data[4..6], .little) else 0;
        std.debug.print("  [{d}] {d}x{d} size={d}b: ", .{idx, w, h, sprite_data.len});
        for (0..@min(sprite_data.len, 24)) |b| {
            std.debug.print("{x:0>2} ", .{sprite_data[b]});
        }
        std.debug.print("\n", .{});
    }

    // Decode a few sprites to check the decoder works
    std.debug.print("\n=== Decode test (indices 100-120) ===\n", .{});
    var decoder = data.BmpDecoder.init(a);
    for (100..120) |i| {
        const sprite_data = pak.getFile(@intCast(i)) catch continue;
        const sprite = decoder.decode(sprite_data) catch |e| {
            std.debug.print("  [{d}] decode error: {}\n", .{i, e});
            continue;
        };
        var s = sprite;
        defer s.deinit(a);
        std.debug.print("  [{d}] {}x{} OK\n", .{i, sprite.width, sprite.height});
    }
}
