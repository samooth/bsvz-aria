const std = @import("std");
const bsvz_aria = @import("bsvz_aria");
const types = bsvz_aria.api.types;

pub fn main() !void {
    const gpa = std.testing.allocator;

    const genesis = types.hashBytes("genesis");
    var aria = try bsvz_aria.api.aria.init(gpa, types.Config{}, genesis);
    defer aria.deinit();

    const epoch = try aria.openEpoch("ep_001", "system-a", &[_]types.ModelHash{});
    defer {
        epoch.deinit();
        gpa.destroy(epoch);
    }

    const rec = try aria.addRecord(epoch, .{
        .model_id = "model-x",
        .input = "input-1",
        .output = "output-1",
        .confidence = 0.95,
        .latency_ms = 12,
    });
    _ = rec;

    try aria.closeEpoch(epoch);
    try aria.verifyEpoch(epoch);

    std.debug.print("example: epoch closed and verified\n", .{});
}
