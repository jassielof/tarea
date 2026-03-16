# Tarea: Technical Debt Markers

Technical debt markers that are a compile error in production, a structured report in development, and a budget you can enforce in CI — with zero configuration required to get started.

## Why Tarea?

Technical debt markers exist in every codebase. The challenge is making them *visible*, *actionable*, and *enforceable* without slowing down development.

Unlike `@compileError` scattered throughout your code or external tools that scan post-build:

- **Tarea blocks production builds** by making `todo`, `fixme`, and `bug` markers into compile errors in Release modes
- **Tarea provides debt visibility** with an optional structured report step that tracks marker count and enforces budgets
- **Tarea distinguishes marker types** — `bug` always blocks compilation; `unimplemented` always runs at runtime, matching Rust's semantics
- **Tarea costs nothing at runtime** — all logic is compile-time or build-time only
- **Tarea requires zero configuration** to use as a library (just `@import("tarea")`)

## Usage

This package exposes the `tarea` module.

### The Marker API

Import and use directly:

```zig
const tarea = @import("tarea");

pub fn parseConfig() !Config {
    if (some_condition) {
        tarea.todo("handle the async case");
    }

    if (known_bug) {
        tarea.bug("off-by-one in UTF-16 handling");
    }

    if (!implemented) {
        tarea.unimplemented("custom file formats");
    }
}
```

#### Error Messages

All markers produce consistent, source-localized error messages:

```
[tarea:TODO] src/parser.zig:88:5 — "handle UTF-16 surrogate pairs"
[tarea:FIXME] src/net.zig:142:10 — "connection pooling"
[tarea:BUG] src/codec.zig:55:3 — "off-by-one in frame boundary detection"
[tarea:UNIMPLEMENTED] src/main.zig:201:8 — "custom file formats"
[tarea:CUSTOM] src/lib.zig:10:2 — "deprecated feature"
```

---

## Marker Semantics

| Marker | Debug | Release* | Purpose |
| --- | --- | --- | --- |
| `todo(msg)` | `@panic` | `@compileError` | Planned feature (doesn't exist yet) |
| `fixme(msg)` | `@panic` | `@compileError` | Known issue (exists but broken) |
| `bug(msg)` | `@compileError` | `@compileError` | Confirmed bug (never ship) |
| `unimplemented(msg)` | `@panic` | `@panic` | Intentional stub (never compile-blocked) |
| `custom(label, msg)` | `@panic` | `@compileError` | User-defined marker type |

*"Release" includes `ReleaseSafe`, `ReleaseFast`, and `ReleaseSmall` modes.

### Why These Behaviors?

- **`bug` blocks everything** — If you tag something as a bug, the build should never silently succeed, even in Debug mode.
- **`unimplemented` always panics** — It matches Rust's `unimplemented!()` semantics exactly. It's an intentional stub, not debt. The code *can* compile, but it will panic at runtime if reached.
- **Everything else allows Debug builds** — You need to develop and test even with incomplete features. Release builds are where you enforce quality.

---

## Build Integration (Optional)

`tarea` provides an optional build step for teams that want structured debt tracking in CI.

### Adding the Debt Step

In `build.zig`:

```zig
const tarea = b.dependency("tarea", .{
    .target = target,
    .optimize = optimize,
});

const check = tarea.module("tarea_step").addDebtStep(b, .{
    .sources = &.{"src", "tools"},
    .budget = .{
        .todo = 10,
        .fixme = 5,
        .bug = 0,
        .unimplemented = 20,
        .custom = 15,
    },
    .report = true,
});

b.step("check", "Check debt budget").dependOn(check);
```

### Sample Output

```
┌─ tarea debt report ──────────────────────────────────┐
│  todo      8 / 10   ████████░░  OK                   │
│  fixme     6 /  5   ██████████  OVER BUDGET          │
│  bug       1 /  0   ██████████  OVER BUDGET          │
│  unimpl.   4 / 20   ██░░░░░░░░  OK                   │
│  custom    0 / 15   ░░░░░░░░░░  OK                   │
└──────────────────────────────────────────────────────┘

Build failed: 2 markers over budget.
```

Then run: `zig build check`

---

## Configuration

Configuration is entirely optional and only needed if you want to override defaults. It lives in `build.zig` using `std.Build.addOptions()`:

```zig
const opts = b.addOptions();
opts.addOption(bool, "allow_todo_in_release", false);
opts.addOption(bool, "allow_fixme_in_release", false);
opts.addOption(bool, "allow_custom_in_release", false);

const tarea_mod = tarea.module("tarea");
tarea_mod.addOptions("tarea_options", opts);
```

**Options:**

- `allow_todo_in_release` (default: `false`) — Allow `tarea.todo()` to panic in Release instead of compile error
- `allow_fixme_in_release` (default: `false`) — Allow `tarea.fixme()` to panic in Release instead of compile error
- `allow_custom_in_release` (default: `false`) — Allow `tarea.custom()` to panic in Release instead of compile error

Note: `tarea.bug()` **always** compiles to `@compileError`, regardless of configuration.

---

## Comparison to Rust

| Concern | Rust `todo!()` / `unimplemented!()` | Tarea |
| --- | --- | --- |
| Blocks production builds? | ❌ Runtime only | ✅ Compile error |
| Call site location in error | ✅ Via macro | ✅ Via `@src()` inline |
| Distinguishes `bug` vs `todo`? | ❌ Same behavior | ✅ Different enforcement |
| Debt visibility in CI | ❌ External tools | ✅ Built-in report step |
| Debt budget enforcement | ❌ Not possible | ✅ Configurable `DebtStep` |
| Configuration | ❌ In source / compile flags | ✅ In `build.zig` |
| Runtime cost (non-panic) | zero | zero |
| Compile-time cost | macro expansion | comptimePrint |

---

## Implementation Notes

- All marker functions are `inline` to ensure `@src()` resolves to the call site, not `root.zig`
- Error messages are built with `std.fmt.comptimePrint` — zero runtime overhead for formatting
- The debt step uses simple text scanning (not AST parsing) for maximum efficiency
- No allocator required for the library itself; only the build step allocates
- Minimum Zig version: **0.15.2**

---

## License

See `LICENSE.txt` for details.
