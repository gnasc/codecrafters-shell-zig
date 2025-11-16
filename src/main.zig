const std = @import("std");

const Command = union(enum) {
    exit: u8,
    echo: []const u8,
    type: []const u8,
    not_found: []const u8,

    const map = createMap();

    fn createMap() std.StaticStringMap(Command) {
        const ssm = std.StaticStringMap(Command);
        
         const field_map = ssm.initComptime(blk: {
            const fields = @typeInfo(Command).@"union".fields;
            var result: [fields.len] struct { []const u8, Command } = undefined;

            inline for(fields, 0..) |field, i| {
                const command_init = switch(field.type) {
                    u8 => @unionInit(Command, field.name, 0),
                    []const u8 => @unionInit(Command, field.name, ""),
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
    var command = Command.map.get(first) orelse @unionInit(Command, "not_found", first);

    if(iterator.peek()) |token| {
        switch(command) {
            .exit => |*value| value.* = try std.fmt.parseUnsigned(u8, token, 10),
            .echo, .type => |*value| value.* = iterator.rest(),
            .not_found => |*value| value.* = first,
        }            
    }    
        
    return command;
}

fn shellTypeSearch(allocator: std.mem.Allocator) !void {
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    const PATH_ENV = env_map.get("PATH").?;
    std.debug.print("{s}", .{PATH_ENV});
}

fn shellType(args: []const u8, writer: *std.Io.Writer) !void {
    const command = try parseStdin(args, " \n");

    switch(command) {
        .not_found => |value| try writer.print("{s}: not found\n", .{value}),
        else => try writer.print("{s} is a shell builtin\n", .{@tagName(command)}),
    }
}

var stdout_writer = std.fs.File.stdout().writerStreaming(&.{});
const stdout = &stdout_writer.interface;

var buffer: [100]u8 = undefined;
var stdin_reader = std.fs.File.stdin().readerStreaming(&buffer);
const stdin = &stdin_reader.interface;

pub fn main() !void {
    while(true) {
        try stdout.print("$ ", .{});
        const input = try stdin.takeDelimiter('\n');
        const command = try parseStdin(input.?, " \n");

        switch(command) {
            .exit => |value| std.process.exit(value),
            .echo => |value| try stdout.print("{s}\n", .{value}),
            .type => |value| try shellType(value, stdout),
            .not_found => |value| try stdout.print("{s}: command not found\n", .{value}),
        }
    }
}
