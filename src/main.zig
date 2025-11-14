const std = @import("std");

const TokenIterator = std.mem.TokenIterator(u8, .any);
const Writer = std.Io.Writer;

const Commands = enum{
    exit,
    echo,
    type,
    not_found,
};

fn shellEcho(iterator: *TokenIterator, writer: *Writer) !void {
    while(iterator.next()) |arg| {
        if(iterator.peek() != null) {
            try writer.print("{s} ", .{arg});
        } else {
            try writer.print("{s}\n", .{arg});
        }
    }
}

fn shellTypeSearch(allocator: std.mem.Allocator) !void {
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    const PATH_ENV = env_map.get("PATH").?;
    std.debug.print("{s}", .{PATH_ENV});
}

fn shellType(iterator: *TokenIterator, writer: *Writer) !void  {
    const str_arg_command = iterator.next().?;
    const arg_command = std.meta.stringToEnum(Commands, str_arg_command) orelse .not_found;
    
    switch(arg_command) {
        .not_found => try writer.print("{s}: not found\n", .{str_arg_command}),
        else => {
            var gpa = std.heap.GeneralPurposeAllocator(.{}){};
            defer {
                const status = gpa.deinit();
                if(status == .leak) @panic("GPA Error!");
            }
            
            const allocator = gpa.allocator();

            try shellTypeSearch(allocator);//try writer.print("{s} is a shell builtin\n", .{str_arg_command}),
        },
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

        var it = std.mem.tokenizeAny(u8, input.?, " \n");
        const str_command = it.next().?;
        const command = std.meta.stringToEnum(Commands, str_command) orelse .not_found;

        switch(command) {
            .exit => {
                const str_code = it.next().?;
                const code = try std.fmt.parseUnsigned(u8, str_code, 10);
                std.process.exit(code);
            },
            .echo => try shellEcho(&it, stdout),
            .type => try shellType(&it, stdout),
            else => try stdout.print("{s}: command not found\n", .{str_command}),
        }

    }
}
