pub export fn strcasecmp(lhs: [*c]const u8, rhs: [*c]const u8) callconv(.c) c_int {
    _ = lhs; // autofix
    _ = rhs; // autofix
    unreachable;
}

pub export fn strncasecmp(lhs: [*c]const u8, rhs: [*c]const u8, num: c_ulong) callconv(.c) c_int {
    _ = lhs; // autofix
    _ = rhs; // autofix
    _ = num; // autofix
    unreachable;
}
