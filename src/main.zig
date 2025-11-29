const std = @import("std");

const CommandTag = enum{ exit, echo, type, pwd };
const CommandKind = enum{ builtin, external, invalid, empty };

const Statement = struct {
    tag: ?CommandTag,
    kind: CommandKind,
    args: union{ single: []const u8, multiple: [][]const u8 },

    fn initFromString(allocator: std.mem.Allocator, args: []const u8) !Statement {
        const delimiters = " ";
        var iterator = std.mem.tokenizeAny(u8, args, delimiters);

        const first_arg = iterator.next() orelse {
            return Statement{ .tag = null, .kind = .empty, .args = .{ .single = "" } };
        };

        const tag = std.meta.stringToEnum(CommandTag, first_arg) orelse {
            const PATH_ENV = try std.process.getEnvVarOwned(allocator, "PATH");
            defer allocator.free(PATH_ENV);

            const maybe_path = try shellSearchExec(allocator, PATH_ENV, first_arg);

            if(maybe_path) |path| {
                var arg_array = try std.ArrayList([]const u8).initCapacity(allocator, 64);
                try arg_array.append(allocator, path);

                iterator.reset();

                while(iterator.next()) |token| {
                    try arg_array.append(allocator, token);
                }

                const extern_args = try arg_array.toOwnedSlice(allocator);

                return Statement{ .tag = null, .kind = .external, .args = .{ .multiple = extern_args } };        
            }

            return Statement{ .tag = null, .kind = .invalid, .args = .{ .single = first_arg } };
        };

        return Statement{ .tag = tag, .kind = .builtin, .args = .{ .single = iterator.rest() } };
    }
    
    fn execute(self: Statement, allocator: std.mem.Allocator, writer: *std.Io.Writer) !void {
        switch(self.kind) {
            .builtin => switch(self.tag.?) {
                .exit => shellExit(self.args.single),
                .echo => try shellEcho(self.args.single, writer),
                .type => try shellType(allocator, self.args.single, writer),
                .pwd => try shellPwd(writer), 
            },
            .external => try shellExec(allocator, self.args.multiple, writer),
            .invalid => try writer.print("{s}: command not found\n", .{self.args.single}),
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

fn shellPwd(writer: *std.Io.Writer) !void {
    var cwd_buffer: [1024]u8 = undefined;
    const cwd = try std.process.getCwd(&cwd_buffer);
    try writer.print("{s}\n", .{cwd});
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

fn shellType(allocator: std.mem.Allocator, args: []const u8, writer: *std.Io.Writer) !void {
    const stmt = try Statement.initFromString(allocator, args);
    
    switch(stmt.kind) {
        .builtin => try writer.print("{s} is a shell builtin\n", .{@tagName(stmt.tag.?)}),
        .external => try writer.print("{s} is {s}\n", .{ stmt.args.multiple[1], stmt.args.multiple[0] }),
        .empty => try writer.print("no argument provided\n", .{}),
        .invalid => try writer.print("{s}: not found\n", .{stmt.args.single}),
    }
}

fn shellExec(allocator: std.mem.Allocator, args: [][]const u8, writer: *std.Io.Writer) !void {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = args[1..],
    });
        
    try writer.print("{s}", .{result.stdout});
}

var stdout_writer = std.fs.File.stdout().writerStreaming(&.{});
const stdout = &stdout_writer.interface;

var buffer: [100]u8 = undefined;
var stdin_reader = std.fs.File.stdin().readerStreaming(&buffer);
const stdin = &stdin_reader.interface;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const status = gpa.deinit();
        std.debug.assert(status == .ok);
    }

    const allocator = gpa.allocator();

    while (true) {
        try stdout.print("$ ", .{});
        const input = try stdin.takeDelimiter('\n');
        const stmt = try Statement.initFromString(allocator, input.?);
        try stmt.execute(allocator, stdout);
    }
}
