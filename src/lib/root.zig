//! Technical debt markers: compile errors in production, panics in development.
const std = @import("std");
const builtin = @import("builtin");

// Configuration options (set via build.zig addOptions)
const tarea_options = @import("tarea_options");
const allow_todo_in_release = tarea_options.allow_todo_in_release orelse false;
const allow_fixme_in_release = tarea_options.allow_fixme_in_release orelse false;
const allow_custom_in_release = tarea_options.allow_custom_in_release orelse false;

/// A known bug that must never ship. Always a compile error, regardless of mode.
pub inline fn bug(comptime msg: []const u8) noreturn {
    const src = @src();
    const error_msg = std.fmt.comptimePrint(
        "[tarea:BUG] {s}:{d}:{d} — \"{s}\"",
        .{ src.file, src.line, src.column, msg },
    );
    @compileError(error_msg);
}

/// A planned feature that doesn't exist yet. A compile error in Release, panic in Debug.
pub inline fn todo(comptime msg: []const u8) noreturn {
    const src = @src();
    const error_msg = std.fmt.comptimePrint(
        "[tarea:TODO] {s}:{d}:{d} — \"{s}\"",
        .{ src.file, src.line, src.column, msg },
    );

    switch (builtin.mode) {
        .Debug => @panic(error_msg),
        else => {
            if (allow_todo_in_release) {
                @panic(error_msg);
            } else {
                @compileError(error_msg);
            }
        },
    }
}

/// A known issue that should be fixed. A compile error in Release, panic in Debug.
pub inline fn fixme(comptime msg: []const u8) noreturn {
    const src = @src();
    const error_msg = std.fmt.comptimePrint(
        "[tarea:FIXME] {s}:{d}:{d} — \"{s}\"",
        .{ src.file, src.line, src.column, msg },
    );

    switch (builtin.mode) {
        .Debug => @panic(error_msg),
        else => {
            if (allow_fixme_in_release) {
                @panic(error_msg);
            } else {
                @compileError(error_msg);
            }
        },
    }
}

/// An intentional stub that will panic if reached at runtime. Never a compile error.
/// Semantically equivalent to Rust's `unimplemented!()`.
pub inline fn unimplemented(comptime msg: []const u8) noreturn {
    const src = @src();
    const error_msg = std.fmt.comptimePrint(
        "[tarea:UNIMPLEMENTED] {s}:{d}:{d} — \"{s}\"",
        .{ src.file, src.line, src.column, msg },
    );
    @panic(error_msg);
}

/// A custom marker with user-defined label. A compile error in Release, panic in Debug.
pub inline fn custom(comptime label: []const u8, comptime msg: []const u8) noreturn {
    const src = @src();
    const error_msg = std.fmt.comptimePrint(
        "[tarea:{s}] {s}:{d}:{d} — \"{s}\"",
        .{ label, src.file, src.line, src.column, msg },
    );

    switch (builtin.mode) {
        .Debug => @panic(error_msg),
        else => {
            if (allow_custom_in_release) {
                @panic(error_msg);
            } else {
                @compileError(error_msg);
            }
        },
    }
}
