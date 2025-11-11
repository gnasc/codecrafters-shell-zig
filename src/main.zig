const std = @import("std");

const Commands = enum{
    exit,
    echo,
    type,
    not_found,
};

var stdout_writer = std.fs.File.stdout().writerStreaming(&.{});
const stdout = &stdout_writer.interface;

var buffer: [100]u8 = undefined;
var stdin_reader = std.fs.File.stdin().readerStreaming(&buffer);
const stdin = &stdin_reader.interface;

pub fn main() !void {
    while(true) {
        try stdout.print("$ ", .{});
        const input = try stdin.takeDelimiter('\n');

        var it = std.mem.tokenizeAny(u8, input.?, " \n");
        const str_command = it.next().?;
        const command = std.meta.stringToEnum(Commands, str_command) orelse .not_found;

        switch(command) {
            .exit => {
                const str_code = it.next().?;
                const code = try std.fmt.parseUnsigned(u8, str_code, 10);
                std.process.exit(code);
            },
            .echo => {
                while(it.next()) |arg| {
                    if(it.peek() != null) {
                        try stdout.print("{s} ", .{arg});
                    } else {
                        try stdout.print("{s}\n", .{arg});
                    }
                }
            },
            .type => {
                const str_arg_command = it.next().?;
                const arg_command = std.meta.stringToEnum(Commands, str_arg_command) orelse .not_found;
                switch(arg_command) {
                    .not_found => try stdout.print("{s}: command not found\n", .{str_arg_command}),
                    else => try stdout.print("{s} is a shell builtin\n", .{str_arg_command}),
                }
            },
            else => try stdout.print("{s}: command not found\n", .{str_command}),
        }

    }
}
