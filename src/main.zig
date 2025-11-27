const std = @import("std");

const Command = union(enum) {
    exit: ?[]const u8,
    echo: []const u8,
    type: []const u8,

    fn execute(self: Command, args: []const u8, writer: *std.Io.Writer) void {
        switch(self) {
            .exit => shellExit(args),
            .echo => shellEcho(args, writer),
            .type => shellType(args, writer),
        }
    }
};

const Statement = union(enum) {
    builtin: Command,
    invalid: []const u8,
    empty: void,

    fn initFromString(argv: []const u8) !Statement {
        const delimiters = " ";
        var iterator = std.mem.tokenizeAny(u8, argv, delimiters);
        const first_arg = iterator.next() orelse {
            return Statement{ .empty = {} };
        };

        const CommandTagType = @typeInfo(Command).@"union".tag_type.?;
        const tag = std.meta.stringToEnum(CommandTagType, first_arg) orelse {
            return Statement{ .invalid = first_arg };
        };

        return Statement{ .builtin = command };
    }
};

fn shellExit(args: ?[]const u8) !void {
    var code = 0;
    if(args) |a| code = try std.fmt.parseUnsigned(a);

    std.process.exit(code);
}

fn shellEcho(args: []const u8, writer: *std.Io.Writer) !void {
    try writer.print("{s}", .{args});
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
    const stmt = Statement.initFromString(args);
    
    switch(stmt) {
        .builtin => try writer.print("{s} is a shell builtin"),
        .empty => try writer.print("no argument provided"),
        .invalid => |command| {
            var gpa = std.heap.DebugAllocator(.{}){};
            defer {
                const status = gpa.deinit();
                std.debug.assert(status == .ok);
            }

            const allocator = gpa.allocator();
            const PATH_ENV = std.process.getEnvVarOwned(allocator, "PATH");
            
            const maybe_path = try shellSearchExec(allocator, PATH_ENV, command);

            if (maybe_path) |path| {
                defer allocator.free(path.?);
                try writer.print("{s} is {s}\n", .{ command, path });
            } else {
                try writer.print("{s}: not found\n", .{command});
            }
        }
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
        std.debug.print("{any}", .{stmt});

        switch (stmt) {
            .builtin => |command| command.execute(stdout),
            .invalid => |name| try stdout.print("{s}: command not found\n", .{name}),
            .empty => {}
        }
    }
}
