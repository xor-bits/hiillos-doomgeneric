const std = @import("std");

const math = @import("libc/math.zig");
const ctype = @import("libc/ctype.zig");
const errno = @import("libc/errno.zig");
const stdio = @import("libc/stdio.zig");
const stdlib = @import("libc/stdlib.zig");
const string = @import("libc/string.zig");
const strings = @import("libc/strings.zig");
const sys = struct {
    const stat = @import("libc/sys/stat.zig");
};

comptime {
    _ = .{ math, ctype, errno, stdio, stdlib, string, strings, sys.stat };
}

// pub const std_options = @import("abi").std_options;
// pub const panic = @import("abi").panic;
// pub const log_level = .debug;

test {
    std.testing.refAllDeclsRecursive(@This());
}
