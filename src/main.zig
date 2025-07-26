const abi = @import("abi");
const gui = @import("gui");

pub const std_options = abi.std_options;
pub const panic = abi.panic;

pub fn main() !void {
    try abi.io.init();
    try abi.process.init();

    try abi.io.stdout.writer().print(
        "hello from doom\n",
        .{},
    );
}

comptime {
    abi.rt.installRuntime();
}
