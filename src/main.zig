const std = @import("std");
const abi = @import("abi");
const gui = @import("gui");

comptime {
    _ = @import("libc");
    abi.rt.installRuntime();
}

const log = std.log.scoped(.doom);
pub const std_options = abi.std_options;
pub const panic = abi.panic;
pub const log_level = .debug;

//

pub fn main() !void {
    try abi.io.init();
    try abi.process.init();

    var arg_map_len: usize = 0;
    var argc: usize = 0;
    var it = abi.process.args();
    while (it.next()) |entry| {
        arg_map_len += entry.len + 1;
        argc += 1;
    }
    const arg_map = try abi.mem.slab_allocator.alloc(u8, arg_map_len);
    const argv = try abi.mem.slab_allocator.alloc([*c]u8, argc);
    arg_map_len = 0;
    argc = 0;
    it = abi.process.args();
    while (it.next()) |entry| {
        const arg = try std.fmt.bufPrintZ(
            arg_map[arg_map_len .. entry.len + 1],
            "{s}",
            .{entry},
        );

        argv[argc] = arg.ptr;
        arg_map_len += entry.len + 1;
        argc += 1;
    }

    doomgeneric_Create(@intCast(argv.len), argv.ptr);

    try abi.io.stdout.writer().print(
        "done\n",
        .{},
    );
}

pub export fn DG_Init() callconv(.c) void {}

pub export fn DG_DrawFrame() callconv(.c) void {}

pub export fn DG_SleepMs(ms: u32) callconv(.c) void {
    _ = abi.caps.COMMON_HPET.call(
        .sleep,
        .{@as(u128, ms) * 1_000_000},
    ) catch |err| {
        log.debug("HPET sleep failed: {}", .{err});
    };
}

pub export fn DG_GetTicksMs() callconv(.c) u32 {
    const nanos = abi.caps.COMMON_HPET.call(
        .timestamp,
        {},
    ) catch |err| {
        log.debug("HPET timestamp failed: {}", .{err});
        return 0;
    };
    return std.math.lossyCast(u32, nanos.@"0" / 1_000_000);
}

pub export fn DG_GetKey(pressed: *c_int, key: *c_uint) callconv(.c) c_int {
    _ = .{ pressed, key };
    return 0;
}

pub export fn DG_SetWindowTitle(title: [*c]const c_char) callconv(.c) void {
    _ = title;
    return;
}

pub const doomgeneric_resx = 640;
pub const doomgeneric_resy = 400;
pub const Pixel = u32;
pub extern var DG_ScreenBuffer: *Pixel;

pub extern fn doomgeneric_Create(argc: c_int, argv: [*c][*c]c_char) callconv(.c) void;
pub extern fn doomgeneric_Tick() callconv(.c) void;
