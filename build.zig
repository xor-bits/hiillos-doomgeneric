const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .abi = .none,
    });
    const optimize = b.standardOptimizeOption(.{});
    const test_step = b.step("test", "run unit tests");

    const abi = b.dependency("hiillos", .{}).module("abi");
    const gui = b.dependency("hiillos", .{}).module("gui");

    const libc = libcMod(b, target, optimize, abi);

    const libc_test = libcMod(b, b.graph.host, optimize, abi);
    const test_libc = b.addTest(.{
        .root_module = libc_test,
    });
    const run_test_libc = b.addRunArtifact(test_libc);
    test_step.dependOn(&run_test_libc.step);

    // const libc = b.addLibrary(.{
    //     .name = "c",
    //     .root_module = libc_mod,
    // });

    // TODO: remove include/ and use this instead once emit-h is fixed in zig
    // const libc_install = b.addInstallArtifact(libc, .{});
    // libc_install.emitted_h = libc.getEmittedH();
    // b.getInstallStep().dependOn(&libc_install.step);

    const exe_mod = exeMod(
        b,
        target,
        optimize,
        abi,
        gui,
        libc,
    );

    const exe = b.addExecutable(.{
        .name = "doom",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const exe_test_mod = exeMod(
        b,
        b.graph.host,
        optimize,
        abi,
        gui,
        libc_test,
    );
    const test_exe = b.addTest(.{
        .root_module = exe_test_mod,
    });
    const run_test_exe = b.addRunArtifact(test_exe);
    test_step.dependOn(&run_test_exe.step);
}

fn libcMod(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    abi: *std.Build.Module,
) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path("src/libc.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &[_]std.Build.Module.Import{.{
            .name = "abi",
            .module = abi,
        }},
    });
}

fn exeMod(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    abi: *std.Build.Module,
    gui: *std.Build.Module,
    libc: *std.Build.Module,
) *std.Build.Module {
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &[_]std.Build.Module.Import{ .{
            .name = "abi",
            .module = abi,
        }, .{
            .name = "gui",
            .module = gui,
        }, .{
            .name = "libc",
            .module = libc,
        } },
        .link_libc = false,
        .link_libcpp = false,
    });
    try addCSources(b, exe_mod);
    return exe_mod;
}

fn addCSources(
    b: *std.Build,
    exe_mod: *std.Build.Module,
) !void {
    // const asset_dir_path = b.path("doomgeneric").getPath3(b, null);

    // var asset_dir = try asset_dir_path.openDir("", .{ .iterate = true });
    // defer asset_dir.close();

    // var walker = try asset_dir.walk(b.allocator);
    // defer walker.deinit();

    // while (try walker.next()) |entry| {
    //     if (entry.kind != .file) continue;
    //     const ext = std.fs.path.extension(entry.path);
    //     if (!std.mem.eql(u8, ".c", ext)) continue;

    //     exe_mod.addCSourceFile(.{
    //         .file = try b.path(doom_c_files).join(b.allocator, entry.path),
    //     });
    // }

    inline for (doom_c_files) |c_file| {
        exe_mod.addCSourceFile(.{
            .file = b.path("doomgeneric/" ++ c_file),
            .flags = &.{"-fno-sanitize=undefined"}, // DOOM source is buggy, ex: left shifting a negative value
        });
    }

    exe_mod.addIncludePath(b.path("include"));
}

// this isn't all of the C files, only the specific ones needed for this port,
// 'automatic' dir walk would just make things more complex and unreadable
const doom_c_files = &.{
    "am_map.c",     "d_event.c",     "d_items.c",     "d_iwad.c",
    "d_loop.c",     "d_main.c",      "d_mode.c",      "d_net.c",
    "doomdef.c",    "doomgeneric.c", "doomstat.c",    "dstrings.c",
    "dummy.c",      "f_finale.c",    "f_wipe.c",      "g_game.c",
    "gusconf.c",    "hu_lib.c",      "hu_stuff.c",    "i_cdmus.c",
    "i_endoom.c",   "i_input.c",     "i_joystick.c",  "i_scale.c",
    "i_sound.c",    "i_system.c",    "i_timer.c",     "i_video.c",
    "icon.c",       "info.c",        "m_argv.c",      "m_bbox.c",
    "m_cheat.c",    "m_config.c",    "m_controls.c",  "m_fixed.c",
    "m_menu.c",     "m_misc.c",      "m_random.c",    "memio.c",
    "mus2mid.c",    "p_ceilng.c",    "p_doors.c",     "p_enemy.c",
    "p_floor.c",    "p_inter.c",     "p_lights.c",    "p_map.c",
    "p_maputl.c",   "p_mobj.c",      "p_plats.c",     "p_pspr.c",
    "p_saveg.c",    "p_setup.c",     "p_sight.c",     "p_spec.c",
    "p_switch.c",   "p_telept.c",    "p_tick.c",      "p_user.c",
    "r_bsp.c",      "r_data.c",      "r_draw.c",      "r_main.c",
    "r_plane.c",    "r_segs.c",      "r_sky.c",       "r_things.c",
    "s_sound.c",    "sha1.c",        "sounds.c",      "st_lib.c",
    "st_stuff.c",   "statdump.c",    "tables.c",      "v_video.c",
    "w_checksum.c", "w_file.c",      "w_file_stdc.c", "w_main.c",
    "w_wad.c",      "wi_stuff.c",    "z_zone.c",
};
