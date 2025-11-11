const std = @import("std");

var stdout_writer = std.fs.File.stdout().writerStreaming(&.{});
const stdout = &stdout_writer.interface;

var buffer: [100]u8 = undefined;
var stdin_reader = std.fs.File.stdin().readerStreaming(&buffer);
const stdin = &stdin_reader.interface;

pub fn main() !void {
    // TODO: Uncomment the code below to pass the first stage
    while(true) {
        try stdout.print("$ ", .{});
        const command = try stdin.takeDelimiter('\n');
        try stdout.print("{s}: command not found\n", .{command.?});
    }
}
