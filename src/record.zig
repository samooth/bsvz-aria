const std = @import("std");
const types = @import("types.zig");
const canonical = @import("canonical.zig");

pub fn createRecord(
    allocator: std.mem.Allocator,
    epoch: *const types.Epoch,
    cfg: types.RecordConfig,
) !types.AuditRecord {
    if (std.mem.eql(u8, cfg.input, "")) return types.RecordError.EmptyInput;
    if (std.mem.eql(u8, cfg.output, "")) return types.RecordError.EmptyOutput;
    if (cfg.confidence < 0 or cfg.confidence > 1) return types.RecordError.InvalidConfidence;

    const epoch_id_str = try epoch.open_payload.epoch_id.format(allocator);
    defer allocator.free(epoch_id_str);

    const sequence = epoch.next_sequence;
    if (sequence > 999999) return types.RecordError.SequenceOverflow;

    const record_id = try std.fmt.allocPrint(allocator, "rec_{s}_{d:0>6}", .{ epoch_id_str, sequence });
    errdefer allocator.free(record_id);

    const model_id = try allocator.dupe(u8, cfg.model_id);
    errdefer if (model_id.len > 0) allocator.free(model_id);

    const input_hash = types.hashBytes(cfg.input);
    const output_hash = types.hashBytes(cfg.output);

    var metadata: ?types.Metadata = null;
    if (cfg.metadata) |src| {
        metadata = try src.clone(allocator);
    }

    return types.AuditRecord{
        .record_id = record_id,
        .epoch_id = try allocator.dupe(u8, epoch_id_str),
        .model_id = model_id,
        .input_hash = input_hash,
        .output_hash = output_hash,
        .confidence = cfg.confidence,
        .latency_ms = cfg.latency_ms,
        .sequence = sequence,
        .metadata = metadata,
    };
}

pub fn hashRecord(record: *const types.AuditRecord) ![32]u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const json = try serializeRecordAlloc(allocator, record);
    return types.hashBytes(json);
}

pub fn serializeRecord(record: *const types.AuditRecord, allocator: std.mem.Allocator) ![]u8 {
    return serializeRecordAlloc(allocator, record);
}

fn serializeRecordAlloc(allocator: std.mem.Allocator, record: *const types.AuditRecord) ![]u8 {
    var custom_json: ?std.json.Value = null;
    if (record.metadata) |m| {
        if (m.custom) |c| {
            custom_json = try types.cloneJsonValue(allocator, c);
        }
    }
    var meta = types.Metadata{
        .decision_class = if (record.metadata) |m| m.decision_class else null,
        .custom = custom_json,
    };
    const wrapper = .{
        .aria_version = record.aria_version,
        .record_id = record.record_id,
        .epoch_id = record.epoch_id,
        .model_id = record.model_id,
        .input_hash = record.input_hash,
        .output_hash = record.output_hash,
        .confidence = record.confidence,
        .latency_ms = record.latency_ms,
        .sequence = record.sequence,
        .metadata = if (meta.decision_class == null and meta.custom == null) null else meta,
    };
    return canonical.canonicalJson(wrapper, allocator);
}
