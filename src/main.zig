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

    vmem = try abi.caps.Vmem.self();

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

    wm_display = try gui.WmDisplay.connect();
    window = try wm_display.createWindow(.{
        .size = .{ 600, 400 },
    });

    const pixel_buf = try mapFb(window.fb);
    display = .{
        .width = window.fb.size[0],
        .height = window.fb.size[1],
        .pitch = window.fb.pitch,
        .bits_per_pixel = 32,
        .pixel_array = pixel_buf,
    };
    display.fill(0xff_000000);
    display_lock = try .newLocked();
    display_lock.unlock();

    try window.damage(wm_display, .{
        .min = .{ 0, 0 },
        .max = .{
            std.math.lossyCast(i32, window.fb.size[0]),
            std.math.lossyCast(i32, window.fb.size[1]),
        },
    });

    key_events_lock = try .newLocked();
    key_events_lock.unlock();
    try abi.thread.spawn(eventLoop, .{});

    doomgeneric_Create(@intCast(argv.len), argv.ptr);
    while (true) doomgeneric_Tick();
}

var vmem: abi.caps.Vmem = undefined;
var display_lock: abi.lock.CapMutex = undefined;
var display: abi.util.Image([]volatile u8) = undefined;
var wm_display: gui.WmDisplay = undefined;
var window: gui.Window = undefined;
var key_events_lock: abi.lock.CapMutex = undefined;
var key_events: std.fifo.LinearFifo(abi.input.KeyEvent, .{ .Static = 512 }) = .init();

fn eventLoop() !void {
    while (true) {
        const ev = try wm_display.nextEvent();
        switch (ev) {
            .window => |wev| try windowEvent(wev.event),
            // else => {},
        }
    }
}

fn windowEvent(ev: gui.WindowEvent.Inner) !void {
    switch (ev) {
        .resize => |resize| {
            display_lock.lock();

            window.fb = resize;
            var pixel_array: []volatile u8 = undefined;
            if (resize.shmem.cap != 0) {
                try vmem.unmap(@intFromPtr(display.pixel_array.ptr), display.pixel_array.len);
                pixel_array = try mapFb(resize);
            } else {
                pixel_array = display.pixel_array;
            }
            display = .{
                .width = window.fb.size[0],
                .height = window.fb.size[1],
                .pitch = window.fb.pitch,
                .bits_per_pixel = 32,
                .pixel_array = pixel_array,
            };
            display.fill(0xff_000000);

            display_lock.unlock(); // dont unlock if an error happened, so no defer

            try window.damage(wm_display, .{
                .min = .{ 0, 0 },
                .max = .{
                    std.math.lossyCast(i32, window.fb.size[0]),
                    std.math.lossyCast(i32, window.fb.size[1]),
                },
            });
        },
        .keyboard_input => |kev| {
            key_events_lock.lock();
            defer key_events_lock.unlock();

            if (key_events.writeItem(kev)) |_| {
                // ok
            } else |_| {
                log.warn("lost keyboard event", .{});
                key_events.discard(1);
                key_events.writeItem(kev) catch unreachable;
            }
        },
        else => {},
    }
}

fn mapFb(fb: gui.Framebuffer) ![]volatile u8 {
    const shmem_size = try fb.shmem.getSize();
    const shmem_addr = try vmem.map(
        fb.shmem,
        0,
        0,
        shmem_size,
        .{ .writable = true },
        .{},
    );

    return @as([*]volatile u8, @ptrFromInt(shmem_addr))[0..shmem_size];
}

const Pixel = extern struct {
    b: u8,
    g: u8,
    r: u8,
    a: u8,
};

pub export fn DG_Init() callconv(.c) void {}

pub export fn DG_DrawFrame() callconv(.c) void {
    defer abi.sys.selfYield();
    display_lock.lock();
    defer display_lock.unlock();

    for (0..display.height) |y| {
        for (0..display.width) |x| {
            const px = display.subimage(
                @intCast(x),
                @intCast(y),
                1,
                1,
            ) catch unreachable;
            const lerp_x: usize = x * doomgeneric_resx / display.width;
            const lerp_y: usize = y * doomgeneric_resy / display.height;
            const c = DG_ScreenBuffer[lerp_x + lerp_y * doomgeneric_resx];
            px.fill(@bitCast(Pixel{
                .r = c.r,
                .g = c.g,
                .b = c.b,
                .a = 255,
            }));
        }
    }

    window.damage(wm_display, .{
        .min = .{ 0, 0 },
        .max = .{
            std.math.lossyCast(i32, window.fb.size[0]),
            std.math.lossyCast(i32, window.fb.size[1]),
        },
    }) catch |err| {
        log.err("failed to damage display: {}", .{err});
    };
}

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
    key_events_lock.lock();
    defer key_events_lock.unlock();

    const kev = key_events.readItem() orelse return 0;
    // log.info("got key event: {}", .{kev});

    key.* = switch (kev.code) {
        // .w => 0xad,
        // .a => 0xa0,
        // .s => 0xaf,
        // .d => 0xa1,
        .arrow_right => 0xae,
        .arrow_left => 0xac,
        .arrow_up => 0xad,
        .arrow_down => 0xaf,
        .oem_comma => 0xa0,
        .oem_period => 0xa1,
        .space => 0xa2,
        // .left_control => 0xa3,
        .escape => 27,
        .enter => 13,
        .tab => 9,
        .f1 => 0x80 + 0x3b,
        .f2 => 0x80 + 0x3c,
        .f3 => 0x80 + 0x3d,
        .f4 => 0x80 + 0x3e,
        .f5 => 0x80 + 0x3f,
        .f6 => 0x80 + 0x40,
        .f7 => 0x80 + 0x41,
        .f8 => 0x80 + 0x42,
        .f9 => 0x80 + 0x43,
        .f10 => 0x80 + 0x44,
        .f11 => 0x80 + 0x57,
        .f12 => 0x80 + 0x58,

        .key0 => '0',
        .key1 => '1',
        .key2 => '2',
        .key3 => '3',
        .key4 => '4',
        .key5 => '5',
        .key6 => '6',
        .key7 => '7',
        .key8 => '8',
        .key9 => '9',

        .backspace => 0x7f,
        .pause_break => 0xff,

        .oem_plus => 0x3d,
        .oem_minus => 0x2d,

        .left_shift, .right_shift => 0x80 + 0x36,
        // .right_control => 0x80 + 0x1d,
        .left_control, .right_control => 0xa3,
        .left_alt, .right_alt2 => 0x80 + 0x38,

        .caps_lock => 0x80 + 0x3a,
        .numpad_lock => 0x80 + 0x45,
        .scroll_lock => 0x80 + 0x46,
        .print_screen => 0x80 + 0x59,

        .home => 0x80 + 0x47,
        .end => 0x80 + 0x4f,
        .page_down => 0x80 + 0x49,
        .page_up => 0x80 + 0x51,
        .insert => 0x80 + 0x52,
        .delete => 0x80 + 0x53,

        .numpad0 => 0,
        .numpad1 => 0x80 + 0x4f,
        .numpad2 => 0xaf,
        .numpad3 => 0x80 + 0x49,
        .numpad4 => 0xac,
        .numpad5 => '5',
        .numpad6 => 0xae,
        .numpad7 => 0x80 + 0x47,
        .numpad8 => 0xad,
        .numpad9 => 0x80 + 0x51,

        .numpad_div => '/',
        .numpad_add => '+',
        .numpad_sub => '-',
        .numpad_mul => '*',
        .numpad_period => 0,
        .numpad_enter => 0x3d,
        else => kev.code.toChar() orelse return 0,
    };
    pressed.* = @intFromBool(kev.state == .press);

    return 1;
}

pub export fn DG_SetWindowTitle(title: [*c]const c_char) callconv(.c) void {
    _ = title;
    return;
}

pub const doomgeneric_resx = 640;
pub const doomgeneric_resy = 400;
pub extern var DG_ScreenBuffer: [*]Pixel;

pub extern fn doomgeneric_Create(argc: c_int, argv: [*c][*c]c_char) callconv(.c) void;
pub extern fn doomgeneric_Tick() callconv(.c) void;

test {
    std.testing.refAllDeclsRecursive(@This());
}
