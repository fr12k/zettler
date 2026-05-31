//! TPWM decompressor — ported from C++ freeserf source.
//!
//! Reference: https://github.com/freeserf/freeserf/blob/master/src/tpwm.cc
//!
//! Format:
//!   - 4 bytes: magic "TPWM"
//!   - 2 bytes: unpacked size (little-endian)
//!   - N bytes: packed data
//!
//! Algorithm: bitmask-controlled LZSS. Each packbyte controls 8 slots.
//! Check MSB of packbyte before shifting left.
//! If MSB = 1 → back-reference (2 bytes), else → literal (1 byte).
//! Back-ref: length = (b1 & 0x0F) + 3, distance = b2 | ((b1 << 4) & 0x0F00).

const std = @import("std");

/// Decompress TPWM-compressed data into an allocated buffer.
pub fn decompress(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    if (data.len < 8) return error.InvalidData;
    if (!std.mem.eql(u8, data[0..4], "TPWM")) return error.NotTPWM;

    // Read unpacked size
    // The C++ freeserf reads 2 bytes (pop<uint16_t>) but our SPAE.PA has
    // a 4-byte LE size at offset 4. Use 4 bytes.
    const res_size: usize = std.mem.readInt(u32, data[4..8], .little);
    if (res_size == 0 or res_size > 4 * 1024 * 1024) return error.InvalidSize;

    const output = try allocator.alloc(u8, res_size);
    errdefer allocator.free(output);

    var ip: usize = 8; // data pointer, starts after 8-byte header
    var op: usize = 0; // output pointer

    while (ip < data.len and op < res_size) {
        var flag: u8 = data[ip];
        ip += 1;

        var bit: usize = 0;
        while (bit < 8) : (bit += 1) {
            if (op >= res_size or ip >= data.len) break;

            // C++ code: flag <<= 1; check if (flag & ~0xFF) -> bit overflowed
            // Equivalent to checking MSB before shift
            const is_backref = (flag & 0x80) != 0;
            flag <<= 1;

            if (is_backref) {
                if (ip + 2 > data.len) return error.TruncatedData;

                const b1 = data[ip];
                ip += 1;
                const b2 = data[ip];
                ip += 1;

                // C++ freeserf confirms: distance = b2 | ((b1 << 4) & 0x0F00)
                const length: usize = @as(usize, b1 & 0x0F) + 3;
                const distance: usize = @as(usize, b2) | ((@as(usize, b1) << 4) & 0x0F00);

                if (distance == 0 or distance > op) return error.InvalidBackref;

                var i: usize = 0;
                while (i < length and op < res_size) : (i += 1) {
                    output[op] = output[op - distance];
                    op += 1;
                }
            } else {
                output[op] = data[ip];
                ip += 1;
                op += 1;
            }
        }
    }

    if (op < res_size) return error.IncompleteDecompress;
    return output;
}

pub fn isTPWM(data: []const u8) bool {
    if (data.len < 4) return false;
    return std.mem.eql(u8, data[0..4], "TPWM");
}

// === Tests ===

test "TPWM header detection" {
    try std.testing.expect(!isTPWM(&[_]u8{0,0,0,0}));
    try std.testing.expect(isTPWM("TPWM\x05\x00"));
    try std.testing.expectError(error.TruncatedData, decompress(std.testing.allocator, "TPWM\x10\x00"));
}

test "TPWM decompress literal only" {
    // Encode "AB" with bitmask 0 (all literals)
    var buf: [6 + 1 + 2]u8 = undefined;
    @memcpy(buf[0..4], "TPWM");
    std.mem.writeInt(u16, buf[4..6], 2, .little); // unpacked = 2
    buf[6] = 0x00; // packbyte = 0: all literals
    buf[7] = 'A';
    buf[8] = 'B';

    const result = try decompress(std.testing.allocator, &buf);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("AB", result);
}

test "TPWM decompress backref" {
    // Encode "AAA" via: literal 'A', backref length 2
    // bitmask: 0x40 = 0b01000000 (slot 0=literal, slot 1=backref)
    // length = 2 => b1 & 0x0F = 2-3 = -1... wait, length=C++ formula: (b1&0xF)+3
    // For actual length 2: b1&0xF = -1? No, unsigned. Minimum is 3.
    // So to get "AAA": literal 'A' (1 byte), backref copies 2 more = length=2
    // Wait, the C++ formula uses +3 so minimum length is 3.
    // Let's just test: literal 'A' + backref len 3 copies 3 bytes = "AAAA"
    // b1: length = 0+3=3 -> b1&0xF = 0 -> b1 = 0x00
    // distance = 1 -> b2 = 1, high nibble of b1 = 0
    // So b1=0, b2=1
    var buf: [6 + 1 + 3]u8 = undefined;
    @memcpy(buf[0..4], "TPWM");
    std.mem.writeInt(u16, buf[4..6], 4, .little); // unpacked = 4
    buf[6] = 0x40; // literal then backref
    buf[7] = 'A';
    buf[8] = 0x00; // b1: length=0+3=3, distance_high=0
    buf[9] = 0x01; // b2: distance_low=1

    const result = try decompress(std.testing.allocator, &buf);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("AAAA", result);
}
