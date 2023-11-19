const std = @import("std");

const MAX_LINE_LENGTH = 150;
const MAX_COLUMNS = 150;

const Template = struct {
    /// parts are views into the provided slice
    /// NOTE: the spot that the template had is an empty slice
    parts: []const []const u8,

    /// col mapping specifies which placeholder the column has
    /// it is absent for non templates. This is 1-index based
    col_mapping: []u8,

    allocator: std.mem.Allocator,

    pub fn init(s: []const u8, allocator: std.mem.Allocator) !Template {
        const num_tokens = std.mem.count(u8, s, " ") + 1;

        var parts = try allocator.alloc([]const u8, num_tokens);
        var col_mapping = try allocator.alloc(u8, num_tokens);
        @memset(col_mapping, 0);

        var token_iter = std.mem.tokenizeSequence(u8, s, " ");

        for (0..num_tokens) |i| {
            var word = token_iter.next().?;

            if (word.len <= 2 or word[0] != '{' and word[word.len - 1] != '}') {
                parts[i] = word;
                continue;
            }

            word = word[1 .. word.len - 1];
            parts[i] = word[0..0];
            col_mapping[i] = try std.fmt.parseInt(u8, word, 10);
        }

        return Template{
            .allocator = allocator,
            .parts = parts,
            .col_mapping = col_mapping,
        };
    }

    pub fn deinit(self: Template) void {
        self.allocator.free(self.parts);
        self.allocator.free(self.col_mapping);
    }
};

fn processLineWise(f: std.fs.File) !void {
    var buff = std.mem.zeroes([MAX_LINE_LENGTH]u8);
    var offset: usize = 0;

    var n = try f.read(&buff);
    while (true) {
        if (std.mem.indexOf(u8, buff[offset..], "\n")) |found| {
            const line = buff[offset .. offset + found];
            if (line.len != 0) {
                std.debug.print("{s}\n", .{line});
            }
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
    var argIter = std.process.args();
    _ = argIter.next();
    const tplstr = argIter.next() orelse "";

    try processLineWise(stdin);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const tpl = try Template.init(tplstr, allocator);
    defer tpl.deinit();

    std.debug.print("{any}", .{tpl.parts});
    std.debug.print("{any}", .{tpl.col_mapping});
}
