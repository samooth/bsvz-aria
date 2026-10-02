const std = @import("std");
const bsvz_aria = @import("bsvz_aria");
const types = bsvz_aria.api.types;
const aria = bsvz_aria.api.aria;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    if (args.len < 2) {
        try printUsage(io);
        return;
    }

    const command = args[1];
    if (std.mem.eql(u8, command, "version")) {
        try printVersion(io);
    } else if (std.mem.eql(u8, command, "demo")) {
        try runDemo(init);
    } else {
        try printUsage(io);
    }
}

fn printUsage(io: std.Io) !void {
    var buf: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &buf);
    defer stdout.flush() catch {};
    try stdout.interface.print(
        \\bsvz-aria {s}
        \\Usage: bsvz_aria <command>
        \\
        \\Commands:
        \\  version    Print the version
        \\  demo       Run an in-memory epoch lifecycle demo
        \\
    , .{bsvz_aria.version()});
}

fn printVersion(io: std.Io) !void {
    var buf: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &buf);
    defer stdout.flush() catch {};
    try stdout.interface.print("bsvz-aria {s}\n", .{bsvz_aria.version()});
}

fn runDemo(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    const genesis = types.hashBytes("genesis");
    var app = try aria.Aria.init(allocator, .{}, genesis, io);
    defer app.deinit();

    const model_hash = types.hashBytes("model-bytes");
    const epoch = try app.openEpoch("ep_1700000000000_0001", "demo-system", &[_]types.ModelHash{
        .{ .model_id = "demo-model", .sha256 = model_hash },
    });
    defer {
        epoch.deinit();
        allocator.destroy(epoch);
    }

    _ = try app.addRecord(epoch, .{
        .model_id = "demo-model",
        .input = "input-1",
        .output = "output-1",
        .confidence = 0.95,
        .latency_ms = 12,
    });
    _ = try app.addRecord(epoch, .{
        .model_id = "demo-model",
        .input = "input-2",
        .output = "output-2",
        .confidence = 0.87,
        .latency_ms = 30,
    });

    const result = try app.closeEpoch(epoch);
    try app.verifyEpoch(epoch);

    var buf: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &buf);
    defer stdout.flush() catch {};
    try stdout.interface.print("epoch: ep_1700000000000_0001\n", .{});
    try stdout.interface.print("system: demo-system\n", .{});
    try stdout.interface.print("records: {d}\n", .{result.records_count});
    try stdout.interface.print("merkle root: {s}\n", .{types.hashToHex(result.records_merkle_root)});
    try stdout.interface.print("close txid: {s}\n", .{types.hashToHex(result.txid)});
    try stdout.interface.print("duration: {d} ms\n", .{result.duration_ms});
    try stdout.interface.print("status: verified\n", .{});
}

test "cli version string" {
    try std.testing.expectEqualStrings("0.1.0", bsvz_aria.version());
}
