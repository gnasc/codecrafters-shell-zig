const std = @import("std");

const Command = union(enum) {
    exit: u8,
    echo: []const u8,
    type: []const u8,
    external: [][]const u8,

    fn initFromString(text: []const u8, args: [][]const u8) !Command {
        const CommandTagType = @typeInfo(Command).@"union".tag_type.?;
        const tag = std.meta.stringToEnum(CommandTagType, text).?;

        std.debug.print("{s}", .{args[0]});
        const command = switch(tag) {
            .exit => Command{ .exit = try std.fmt.parseUnsigned(u8, args[0], 10) },
            .echo => Command{ .echo = args[0] },
            .type => Command{ .type = args[0] },
            .external => Command{ .external = args },
        };

        return command;
    }
};

const Statement = union(enum) {
    command: Command,
    none: []u8,
};

const Command2 = union(enum) {
    exit: u8,
    echo: []const u8,
    type: []const u8,
    not_found: []const []const u8,

    const map = createMap();

    fn createMap() std.StaticStringMap(Command) {
        const ssm = std.StaticStringMap(Command);

        const field_map = ssm.initComptime(blk: {
            const fields = @typeInfo(Command).@"union".fields;
            var result: [fields.len]struct { []const u8, Command } = undefined;

            inline for (fields, 0..) |field, i| {
                const command_init = switch (field.type) {
                    u8 => @unionInit(Command, field.name, 0),
                    []const u8 => @unionInit(Command, field.name, ""),
                    []const []const u8 => @unionInit(Command, field.name, undefined),
                    else => @unionInit(Command, field.name, void{}),
                };

                result[i] = .{ field.name, command_init };
            }

            const final = result;
            break :blk final;
        });

        return field_map;
    }
};

fn parseStdin(input: []const u8, delimiters: []const u8) !Command {
    var iterator = std.mem.tokenizeAny(u8, input, delimiters);
    const first = iterator.next().?;
    var command = Command.map.get(first) orelse @unionInit(Command, "not_found", undefined);

    if (iterator.peek()) |token| {
        switch (command) {
            .exit => |*value| value.* = try std.fmt.parseUnsigned(u8, token, 10),
            .echo, .type => |*value| value.* = iterator.rest(),
            .not_found => {
                var argv: [][]const u8 = undefined;
                var i: usize = 0;

                while(iterator.next()) |arg| : (i += 1) {
                    argv[i] = arg;
                    std.debug.print("{s}", .{arg});
                }

                return @unionInit(Command, "not_found", argv);
            },
        }
    }

    return command;
}

fn shellSearch(allocator: std.mem.Allocator, paths: []const u8, file: []const u8) !?[]u8 {
    const delimiter = std.fs.path.delimiter;
    var path_iterator = std.mem.tokenizeAny(u8, paths, &.{delimiter});

    while (path_iterator.next()) |path| {
        var dir = try std.fs.openDirAbsolute(path, .{ .iterate = true });
        defer dir.close();

        var dir_iterator = dir.iterate();
        while (try dir_iterator.next()) |entry| {
            const stat = try dir.statFile(entry.name);
            if (std.mem.eql(u8, entry.name, file) and stat.mode & 0o111 != 0) {
                const full_path = try std.fs.path.join(allocator, &[_][]const u8{ path, entry.name });

                return full_path;
            }
        }
    }

    return null;
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

    const path = try shellSearch(allocator, PATH_ENV, argv[0]);
    
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

fn shellType(args: []const u8, writer: *std.Io.Writer) !void {
    const command = try parseStdin(args, " \n");

    switch (command) {
        .not_found => |value| {
            var gpa = std.heap.DebugAllocator(.{}){};
            defer {
                const status = gpa.deinit();
                std.debug.assert(status == .ok);
            }

            const allocator = gpa.allocator();

            var env_map = try std.process.getEnvMap(allocator);
            defer env_map.deinit();

            const PATH_ENV = env_map.get("PATH").?;
            const path = try shellSearch(allocator, PATH_ENV, value[0]);

            if (path) |p| {
                defer allocator.free(path.?);
                try writer.print("{s} is {s}\n", .{ value[0], p });
            } else {
                try writer.print("{s}: not found\n", .{value[0]});
            }
        },
        else => try writer.print("{s} is a shell builtin\n", .{@tagName(command)}),
    }
}

var stdout_writer = std.fs.File.stdout().writerStreaming(&.{});
const stdout = &stdout_writer.interface;

var buffer: [100]u8 = undefined;
var stdin_reader = std.fs.File.stdin().readerStreaming(&buffer);
const stdin = &stdin_reader.interface;

pub fn main() !void {
    var aaa: [2][]const u8 = .{"0", "1"};
    _ = try Command.initFromString("exit", &aaa);
    aaa = .{"0", "1"};
    
//    std.debug.print("{any}", .{cmd});
//    while (true) {
//        try stdout.print("$ ", .{});
//        const input = try stdin.takeDelimiter('\n');
//        const command = try parseStdin(input.?, " \n");

//      switch (command) {
//            .exit => |value| std.process.exit(value),
//            .echo => |value| try stdout.print("{s}\n", .{value}),
//            .type => |value| try shellType(value, stdout),
//            .not_found => |value| try stdout.print("{s}: command not found\n", .{value[0]}),
//        }
//    }
}
