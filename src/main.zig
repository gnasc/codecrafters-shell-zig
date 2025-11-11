const std = @import("std");

const Commands = enum{
    exit,
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
            .exit => blk: {
                const str_code = it.peek().?;
                const code = try std.fmt.parseUnsigned(u8, str_code, 10);
                break :blk std.process.exit(code);
            },
            else => try stdout.print("{s}: command not found\n", .{str_command}),
        }

    }
}
