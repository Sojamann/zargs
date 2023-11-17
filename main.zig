const std = @import("std");

const MAX_LINE_LENGTH = 50;
var buff = std.mem.zeroes([MAX_LINE_LENGTH]u8);

fn readLineWise(f: std.fs.File) !void {
    var offset: usize = 0;

    var n = try f.read(&buff);
    while (true) {
        if (std.mem.indexOf(u8, buff[offset..], "\n")) |found| {
            std.debug.print("{s}\n", .{buff[offset .. offset + found]});
            offset += found + 1;
            continue;
        }

        std.mem.copyForwards(u8, &buff, buff[offset..]);

        n = try f.read(buff[buff.len - offset ..]);
        if (n == 0) {
            // if we normyally could have read more the line was just
            // too long for our buffer
            if (try f.read(buff[0..1]) > 0) {
                return error.LineTooLong;
            }
            break;
        }
        offset = 0;
    }
}

pub fn main() !void {
    const stdin = std.io.getStdIn();
    try readLineWise(stdin);
}
