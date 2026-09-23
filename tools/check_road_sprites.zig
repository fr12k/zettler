//! Quick check: verify PAK 230-245 (path masks) and 300-308 (path grounds) exist.
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

    std.debug.print("File count: {}\n", .{pak.fileCount()});

    // Path masks: PAK 230-245
    std.debug.print("--- Path masks (PAK 230-245) ---\n", .{});
    var i: u16 = 230;
    while (i < 246 and i < pak.fileCount()) : (i += 1) {
        const raw_entry = pak.getFile(i) catch {
            std.debug.print("  [{}] ERROR\n", .{i});
            continue;
        };
        if (raw_entry.len < 10) {
            std.debug.print("  [{}] too short ({})\n", .{ i, raw_entry.len });
            continue;
        }
        const w = std.mem.readInt(u16, raw_entry[2..4], .little);
        const h = std.mem.readInt(u16, raw_entry[4..6], .little);
        std.debug.print("  [{}] {}x{} ({} bytes)\n", .{ i, w, h, raw_entry.len });
    }

    // Path grounds: PAK 300-308
    std.debug.print("--- Path grounds (PAK 300-308) ---\n", .{});
    i = 300;
    while (i < 309 and i < pak.fileCount()) : (i += 1) {
        const raw_entry = pak.getFile(i) catch {
            std.debug.print("  [{}] ERROR\n", .{i});
            continue;
        };
        if (raw_entry.len < 10) {
            std.debug.print("  [{}] too short ({})\n", .{ i, raw_entry.len });
            continue;
        }
        const w = std.mem.readInt(u16, raw_entry[2..4], .little);
        const h = std.mem.readInt(u16, raw_entry[4..6], .little);
        std.debug.print("  [{}] {}x{} ({} bytes)\n", .{ i, w, h, raw_entry.len });
    }
}
