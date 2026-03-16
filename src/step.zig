//! The debt scanner and budget enforcement step.
//! This is imported by build.zig but can also be used by other build systems.

const std = @import("std");

/// Configuration for the debt budget and reporting.
pub const DebtConfig = struct {
    /// Source directories to scan for tarea markers (relative to build root).
    sources: []const []const u8 = &.{"src"},

    /// Budget limits per marker type. Use 0 to forbid entirely.
    budget: struct {
        todo: usize = 50,
        fixme: usize = 10,
        bug: usize = 0,
        unimplemented: usize = 1000,
        custom: usize = 20,
    } = .{},

    /// Whether to print the debt report to stdout.
    report: bool = true,
};

/// Add a build step that scans for tarea markers, reports debt, and enforces budget.
pub fn addDebtStep(b: *std.Build, config: DebtConfig) *std.Build.Step {
    // Create the step
    const step = b.allocator.create(DebtStep) catch @panic("OOM");
    step.* = .{
        .step = std.Build.Step.init(.{
            .id = .custom,
            .name = "tarea-debt",
            .owner = b,
            .makeFn = DebtStep.make,
        }),
        .b = b,
        .config = config,
        .counts = .{},
    };

    return &step.step;
}

const DebtStep = struct {
    step: std.Build.Step,
    b: *std.Build,
    config: DebtConfig,
    counts: DebtCounts,

    const DebtCounts = struct {
        todo: usize = 0,
        fixme: usize = 0,
        bug: usize = 0,
        unimplemented: usize = 0,
        custom: usize = 0,

        fn all(self: DebtCounts) usize {
            return self.todo + self.fixme + self.bug + self.unimplemented + self.custom;
        }
    };

    fn make(step: *std.Build.Step, progress: *std.Progress.Node) !void {
        _ = progress;
        const self: *DebtStep = @fieldParentPtr("step", step);
        const alloc = self.b.allocator;

        var counts = DebtCounts{};

        // Scan source files
        for (self.config.sources) |src_dir| {
            try self.scanDir(alloc, src_dir, &counts);
        }

        // Report
        if (self.config.report) {
            try self.printReport(counts);
        }

        // Check budget
        const budget = self.config.budget;
        if (counts.bug > budget.bug) {
            std.debug.print("Build failed: {d} bug marker(s) over budget (limit: {d}).\n", .{ counts.bug, budget.bug });
            return error.OverBudget;
        }
        if (counts.todo > budget.todo) {
            std.debug.print("Build failed: {d} todo marker(s) over budget (limit: {d}).\n", .{ counts.todo, budget.todo });
            return error.OverBudget;
        }
        if (counts.fixme > budget.fixme) {
            std.debug.print("Build failed: {d} fixme marker(s) over budget (limit: {d}).\n", .{ counts.fixme, budget.fixme });
            return error.OverBudget;
        }
        if (counts.unimplemented > budget.unimplemented) {
            std.debug.print("Build failed: {d} unimplemented marker(s) over budget (limit: {d}).\n", .{ counts.unimplemented, budget.unimplemented });
            return error.OverBudget;
        }
        if (counts.custom > budget.custom) {
            std.debug.print("Build failed: {d} custom marker(s) over budget (limit: {d}).\n", .{ counts.custom, budget.custom });
            return error.OverBudget;
        }
    }

    fn scanDir(self: *DebtStep, alloc: std.mem.Allocator, dir_path: []const u8, counts: *DebtCounts) !void {
        var dir = self.b.build_root.handle.openDir(dir_path, .{ .iterate = true }) catch |e| {
            std.debug.print("warning: could not open directory '{s}': {any}\n", .{ dir_path, e });
            return;
        };
        defer dir.close();

        var iter = try dir.walk(alloc);
        defer iter.deinit();

        while (try iter.next()) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.basename, ".zig")) continue;

            const file = dir.openFile(entry.path, .{}) catch continue;
            defer file.close();

            const contents = file.readToEndAlloc(alloc, 1024 * 1024 * 10) catch continue;
            defer alloc.free(contents);

            self.countMarkers(contents, counts);
        }
    }

    fn countMarkers(self: *DebtStep, contents: []const u8, counts: *DebtCounts) void {
        _ = self;
        var pos: usize = 0;

        while (pos < contents.len) {
            if (std.mem.startsWith(u8, contents[pos..], "tarea.todo(")) {
                counts.todo += 1;
                pos += 1;
            } else if (std.mem.startsWith(u8, contents[pos..], "tarea.fixme(")) {
                counts.fixme += 1;
                pos += 1;
            } else if (std.mem.startsWith(u8, contents[pos..], "tarea.bug(")) {
                counts.bug += 1;
                pos += 1;
            } else if (std.mem.startsWith(u8, contents[pos..], "tarea.unimplemented(")) {
                counts.unimplemented += 1;
                pos += 1;
            } else if (std.mem.startsWith(u8, contents[pos..], "tarea.custom(")) {
                counts.custom += 1;
                pos += 1;
            } else {
                pos += 1;
            }
        }
    }

    fn printReport(self: *DebtStep, counts: DebtCounts) !void {
        const budget = self.config.budget;

        const stdout = std.io.getStdOut().writer();

        try stdout.print("\n", .{});
        try stdout.print("┌─ tarea debt report ──────────────────────────────────┐\n", .{});

        if (counts.todo <= budget.todo) {
            try stdout.print("│  todo     {d: >2} / {d: >2}   ", .{ counts.todo, budget.todo });
            try self.printBar(stdout, counts.todo, budget.todo);
            try stdout.print("  OK                    │\n", .{});
        } else {
            try stdout.print("│  todo     {d: >2} / {d: >2}   ", .{ counts.todo, budget.todo });
            try self.printBar(stdout, counts.todo, budget.todo);
            try stdout.print("  OVER BUDGET            │\n", .{});
        }

        if (counts.fixme <= budget.fixme) {
            try stdout.print("│  fixme    {d: >2} /  {d: >2}   ", .{ counts.fixme, budget.fixme });
            try self.printBar(stdout, counts.fixme, budget.fixme);
            try stdout.print("  OK                    │\n", .{});
        } else {
            try stdout.print("│  fixme    {d: >2} /  {d: >2}   ", .{ counts.fixme, budget.fixme });
            try self.printBar(stdout, counts.fixme, budget.fixme);
            try stdout.print("  OVER BUDGET            │\n", .{});
        }

        try stdout.print("│  bug      {d: >2} /  {d: >2}   ", .{ counts.bug, budget.bug });
        try self.printBar(stdout, counts.bug, budget.bug);
        if (counts.bug > budget.bug) {
            try stdout.print("  OVER BUDGET            │\n", .{});
        } else {
            try stdout.print("  OK                    │\n", .{});
        }

        if (counts.unimplemented <= budget.unimplemented) {
            try stdout.print("│  unimpl.  {d: >2} / {d: >2}   ", .{ counts.unimplemented, budget.unimplemented });
            try self.printBar(stdout, counts.unimplemented, budget.unimplemented);
            try stdout.print("  OK                    │\n", .{});
        } else {
            try stdout.print("│  unimpl.  {d: >2} / {d: >2}   ", .{ counts.unimplemented, budget.unimplemented });
            try self.printBar(stdout, counts.unimplemented, budget.unimplemented);
            try stdout.print("  OVER BUDGET            │\n", .{});
        }

        if (counts.custom <= budget.custom) {
            try stdout.print("│  custom   {d: >2} / {d: >2}   ", .{ counts.custom, budget.custom });
            try self.printBar(stdout, counts.custom, budget.custom);
            try stdout.print("  OK                    │\n", .{});
        } else {
            try stdout.print("│  custom   {d: >2} / {d: >2}   ", .{ counts.custom, budget.custom });
            try self.printBar(stdout, counts.custom, budget.custom);
            try stdout.print("  OVER BUDGET            │\n", .{});
        }

        try stdout.print("└──────────────────────────────────────────────────────┘\n", .{});
        try stdout.print("\n", .{});
    }

    fn printBar(self: *DebtStep, writer: std.fs.File.Writer, current: usize, max: usize) !void {
        _ = self;
        const bar_width = 10;
        const filled = if (max == 0) bar_width else @min((current * bar_width) / max, bar_width);
        try writer.writeByteNTimes('█', filled);
        try writer.writeByteNTimes('░', bar_width - filled);
    }
};
