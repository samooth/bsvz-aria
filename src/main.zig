const std = @import("std");
const bsvz_aria = @import("bsvz_aria");
const types = bsvz_aria.api.types;
const aria = bsvz_aria.api.aria;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    if (args.len < 2) {
        std.debug.print("bsvz-aria {s}\nUsage: bsvz_aria <open|close|add|verify> [args...]\n", .{bsvz_aria.version()});
        return;
    }

    const command = args[1];
    std.debug.print("Command: {s}\n", .{command});
}

test "basic add functionality" {
    try std.testing.expect(3 + 7 == 10);
}
