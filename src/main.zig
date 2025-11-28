const std = @import("std");

const CommandTag = enum{ exit, echo, type };
const CommandKind = enum{ builtin, external, invalid, empty };

const Statement = struct {
    tag: ?CommandTag,
    kind: CommandKind,
    args: []const u8,

    fn initFromString(args: []const u8) !Statement {
        const delimiters = " ";
        var iterator = std.mem.tokenizeAny(u8, args, delimiters);

        const first_arg = iterator.next() orelse {
            return Statement{ .tag = null, .kind = .empty, .args = "" };
        };

        const tag = std.meta.stringToEnum(CommandTag, first_arg) orelse {
            return Statement{ .tag = null, .kind = .invalid, .args = first_arg };
        };

        return Statement{ .tag = tag, .kind = .builtin, .args = iterator.rest() };
    }

    fn execute(self: Statement, writer: *std.Io.Writer) !void {
        switch(self.kind) {
            .builtin => switch(self.tag.?) {
                .exit => shellExit(self.args),
                .echo => try shellEcho(self.args, writer),
                .type => try shellType(self.args, writer),
            },
            .external => {},
            .invalid => try writer.print("{s}: command not found\n", .{self.args}),
            .empty => {},
        }


    }
};

fn shellExit(args: []const u8) void {
    const code: u8 = std.fmt.parseUnsigned(u8, args, 10) catch 0;
    std.process.exit(code);
}

fn shellEcho(args: []const u8, writer: *std.Io.Writer) !void {
    try writer.print("{s}\n", .{args});
}

fn shellSearchExec(allocator: std.mem.Allocator, paths: []const u8, name: []const u8) !?[]u8 {
    const delimiter = std.fs.path.delimiter;
    var path_iterator = std.mem.tokenizeAny(u8, paths, &.{delimiter});

    while (path_iterator.next()) |path| {
        var dir = try std.fs.openDirAbsolute(path, .{ .iterate = true });
        defer dir.close();

        var dir_iterator = dir.iterate();
        while (try dir_iterator.next()) |entry| {
            const stat = try dir.statFile(entry.name);
            if (std.mem.eql(u8, entry.name, name) and stat.mode & 0o111 != 0) {
                const full_path = try std.fs.path.join(allocator, &[_][]const u8{ path, entry.name });

                return full_path;
            }
        }
    }

    return null;
}

fn shellType(args: []const u8, writer: *std.Io.Writer) !void {
    const stmt = try Statement.initFromString(args);
    
    switch(stmt.kind) {
        .builtin => try writer.print("{s} is a shell builtin\n", .{@tagName(stmt.tag.?)}),
        .empty => try writer.print("no argument provided\n", .{}),
        .invalid => {
            var gpa = std.heap.DebugAllocator(.{}){};
            defer {
                const status = gpa.deinit();
                std.debug.assert(status == .ok);
            }

            const allocator = gpa.allocator();
            const PATH_ENV = try std.process.getEnvVarOwned(allocator, "PATH");
            defer allocator.free(PATH_ENV);

            const maybe_path = try shellSearchExec(allocator, PATH_ENV, stmt.args);

            if (maybe_path) |path| {
                defer allocator.free(path);
                try writer.print("{s} is {s}\n", .{ stmt.args, path });
            } else {
                try writer.print("{s}: not found\n", .{stmt.args});
            }
        },
        else => {},
    }
}

fn shellExec(argv: []const []const u8, writer: *std.Io.Writer) !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const status = gpa.deinit();
        std.debug.assert(status == .ok);
    }

    const allocator = gpa.allocator();

    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    const PATH_ENV = env_map.get("PATH").?;

    const path = try shellSearchExec(allocator, PATH_ENV, argv[0]);
    
    if(path) |p| {
        argv[0] = p;
        const result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = argv,
        });
        defer result.deinit();
        
        try writer.print("{}", .{result.stdout});
    }

}

var stdout_writer = std.fs.File.stdout().writerStreaming(&.{});
const stdout = &stdout_writer.interface;

var buffer: [100]u8 = undefined;
var stdin_reader = std.fs.File.stdin().readerStreaming(&buffer);
const stdin = &stdin_reader.interface;

pub fn main() !void {
    
    while (true) {
        try stdout.print("$ ", .{});
        const input = try stdin.takeDelimiter('\n');
        const stmt = try Statement.initFromString(input.?);
        try stmt.execute(stdout);
    }
}
