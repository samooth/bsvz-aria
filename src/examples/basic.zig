const std = @import("std");
const bsvz_aria = @import("bsvz_aria");
const types = bsvz_aria.api.types;
const aria = bsvz_aria.api.aria;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    const genesis = types.hashBytes("genesis");
    var app = try aria.Aria.init(gpa, .{}, genesis, io);
    defer app.deinit();

    const model_hash = types.hashBytes("model-bytes");
    const epoch = try app.openEpoch("ep_1700000000000_0001", "example-system", &[_]types.ModelHash{
        .{ .model_id = "example-model", .sha256 = model_hash },
    });
    defer {
        epoch.deinit();
        gpa.destroy(epoch);
    }

    const rec = try app.addRecord(epoch, .{
        .model_id = "example-model",
        .input = "input-1",
        .output = "output-1",
        .confidence = 0.95,
        .latency_ms = 12,
    });

    const result = try app.closeEpoch(epoch);
    try app.verifyEpoch(epoch);

    var buf: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &buf);
    defer stdout.flush() catch {};
    try stdout.interface.print("example: epoch closed and verified\n", .{});
    try stdout.interface.print("record: {s}\n", .{rec.record_id});
    try stdout.interface.print("records: {d}\n", .{result.records_count});
    try stdout.interface.print("merkle root: {s}\n", .{types.hashToHex(result.records_merkle_root)});
}
