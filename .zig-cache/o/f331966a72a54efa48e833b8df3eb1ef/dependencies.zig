pub const packages = struct {
    pub const @"N-V-__8AAGVtrgCcOcmjrOJnagmnRyMrcKaOo09KbU-vu8w8" = struct {
        pub const build_root = "/ai/repos/2026/bsvz-aria/zig-pkg/N-V-__8AAGVtrgCcOcmjrOJnagmnRyMrcKaOo09KbU-vu8w8";
        pub const deps: []const struct { []const u8, []const u8 } = &.{};
    };
    pub const @"bsvz-0.1.0-wvsL-dviFQDU2Al1QQBlT1s8lDJPmNDXLWdg1-1Q4fBw" = struct {
        pub const build_root = "/ai/repos/2026/bsvz-aria/zig-pkg/bsvz-0.1.0-wvsL-dviFQDU2Al1QQBlT1s8lDJPmNDXLWdg1-1Q4fBw";
        pub const build_zig = @import("bsvz-0.1.0-wvsL-dviFQDU2Al1QQBlT1s8lDJPmNDXLWdg1-1Q4fBw");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
    pub const @"bsvz-0.2.0-wvsL-a2NFgBd_iD1vq1jlixrjH2pun9ZyN1EVzwxdZd-" = struct {
        pub const build_root = "/ai/repos/2026/bsvz-aria/zig-pkg/bsvz-0.2.0-wvsL-a2NFgBd_iD1vq1jlixrjH2pun9ZyN1EVzwxdZd-";
        pub const build_zig = @import("bsvz-0.2.0-wvsL-a2NFgBd_iD1vq1jlixrjH2pun9ZyN1EVzwxdZd-");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
    pub const @"sqlite-3.53.4-F2R_a_9DDwBktiEd3EBGtbAqXJ8SwBLUJPhdydz0XcUG" = struct {
        pub const build_root = "/ai/repos/2026/bsvz-aria/zig-pkg/sqlite-3.53.4-F2R_a_9DDwBktiEd3EBGtbAqXJ8SwBLUJPhdydz0XcUG";
        pub const build_zig = @import("sqlite-3.53.4-F2R_a_9DDwBktiEd3EBGtbAqXJ8SwBLUJPhdydz0XcUG");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "sqlite", "N-V-__8AAGVtrgCcOcmjrOJnagmnRyMrcKaOo09KbU-vu8w8" },
        };
    };
    pub const @"zig_algebra-0.3.0-PdVS09HBEgCz3_dLdFN_YuBsJk7_LRQSVDM2WYkCKUZg" = struct {
        pub const build_root = "/ai/repos/2026/bsvz-aria/zig-pkg/zig_algebra-0.3.0-PdVS09HBEgCz3_dLdFN_YuBsJk7_LRQSVDM2WYkCKUZg";
        pub const build_zig = @import("zig_algebra-0.3.0-PdVS09HBEgCz3_dLdFN_YuBsJk7_LRQSVDM2WYkCKUZg");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
    pub const @"zig_wallet_toolbox-0.1.0-yWfVokzCBgB4439qY9GPbB0uy4pgJw20HEMRtn0r7Z4o" = struct {
        pub const build_root = "/ai/repos/2026/bsvz-aria/zig-pkg/zig_wallet_toolbox-0.1.0-yWfVokzCBgB4439qY9GPbB0uy4pgJw20HEMRtn0r7Z4o";
        pub const build_zig = @import("zig_wallet_toolbox-0.1.0-yWfVokzCBgB4439qY9GPbB0uy4pgJw20HEMRtn0r7Z4o");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "bsvz", "bsvz-0.1.0-wvsL-dviFQDU2Al1QQBlT1s8lDJPmNDXLWdg1-1Q4fBw" },
            .{ "sqlite", "sqlite-3.53.4-F2R_a_9DDwBktiEd3EBGtbAqXJ8SwBLUJPhdydz0XcUG" },
        };
    };
    pub const @"zig_zk-0.1.0-B0HDknWHCgCgPhxWdDj7rd5O3Dh5VIs_AETPQCrJ3hYX" = struct {
        pub const build_root = "/ai/repos/2026/bsvz-aria/zig-pkg/zig_zk-0.1.0-B0HDknWHCgCgPhxWdDj7rd5O3Dh5VIs_AETPQCrJ3hYX";
        pub const build_zig = @import("zig_zk-0.1.0-B0HDknWHCgCgPhxWdDj7rd5O3Dh5VIs_AETPQCrJ3hYX");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "zig_algebra", "zig_algebra-0.3.0-PdVS09HBEgCz3_dLdFN_YuBsJk7_LRQSVDM2WYkCKUZg" },
        };
    };
    pub const @"zig_zkml-0.1.0-ldYnSQDMAwBysZFeGiKJ651xieEM46zywx57C2MsjMPZ" = struct {
        pub const build_root = "/ai/repos/2026/bsvz-aria/zig-pkg/zig_zkml-0.1.0-ldYnSQDMAwBysZFeGiKJ651xieEM46zywx57C2MsjMPZ";
        pub const build_zig = @import("zig_zkml-0.1.0-ldYnSQDMAwBysZFeGiKJ651xieEM46zywx57C2MsjMPZ");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "zig_algebra", "zig_algebra-0.3.0-PdVS09HBEgCz3_dLdFN_YuBsJk7_LRQSVDM2WYkCKUZg" },
            .{ "zig_zk", "zig_zk-0.1.0-B0HDknWHCgCgPhxWdDj7rd5O3Dh5VIs_AETPQCrJ3hYX" },
        };
    };
};

pub const root_deps: []const struct { []const u8, []const u8 } = &.{
    .{ "bsvz", "bsvz-0.2.0-wvsL-a2NFgBd_iD1vq1jlixrjH2pun9ZyN1EVzwxdZd-" },
    .{ "zig_wallet_toolbox", "zig_wallet_toolbox-0.1.0-yWfVokzCBgB4439qY9GPbB0uy4pgJw20HEMRtn0r7Z4o" },
    .{ "zig_zkml", "zig_zkml-0.1.0-ldYnSQDMAwBysZFeGiKJ651xieEM46zywx57C2MsjMPZ" },
};
