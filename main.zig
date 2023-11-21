const std = @import("std");

const MAX_LINE_LENGTH = 150;
const MAX_COLUMNS = 150;

const Template = struct {
    /// parts are views into the provided slice
    /// NOTE: the spot that the template had is an empty slice
    parts: [MAX_COLUMNS]?[]const u8 = std.mem.zeroes([MAX_COLUMNS]?[]const u8),

    /// col mapping specifies which placeholder the column has
    /// it is absent for non templates. This is 1-index based
    col_mapping: [MAX_COLUMNS]?u8 = std.mem.zeroes([MAX_COLUMNS]?u8),

    num_columns: usize = 0,

    pub fn init(s: []const u8, opening: u8, closing: u8) !Template {
        var tpl = Template{};
        var offset: usize = 0;
        while (offset < s.len) {
            const start = std.mem.indexOfScalarPos(u8, s, offset, opening) orelse {
                tpl.parts[tpl.num_columns] = s[offset..];
                tpl.col_mapping[tpl.num_columns] = null;
                tpl.num_columns += 1;
                break;
            };

            const end = std.mem.indexOfScalarPos(u8, s, start + 1, closing) orelse {
                return error.InvalidSyntax;
            };

            tpl.parts[tpl.num_columns] = s[offset..start];
            tpl.parts[tpl.num_columns + 1] = null;
            tpl.col_mapping[tpl.num_columns] = null;
            tpl.col_mapping[tpl.num_columns + 1] = try std.fmt.parseInt(u8, s[start + 1 .. end], 10);

            tpl.num_columns += 2;
            offset = end + 1;
        }

        return tpl;
    }

    pub fn template(self: Template, columns: [][]const u8, buff: []u8) ![]u8 {
        // compute the total size of all USED columns
        var size_used_columns: u64 = 0;
        var size_of_template: u64 = 0;

        for (0..self.num_columns) |i| {
            if (self.col_mapping[i]) |col| {
                if (col >= columns.len) {
                    return error.TooLittleColumnsForTemplate;
                }
                size_used_columns += columns[col - 1].len;
            }
            if (self.parts[i]) |part| {
                size_of_template += part.len;
            }
        }

        var result_width = size_used_columns + size_of_template + (self.num_columns);
        if (result_width > buff.len) {
            return error.TemplateResultTooLong;
        }

        var offset: usize = 0;
        for (0..self.num_columns) |i| {
            if (self.col_mapping[i]) |col| {
                const col_content = columns[col];
                std.mem.copyForwards(u8, buff[offset..], col_content);
                offset += col_content.len;
                continue;
            }

            const template_str = self.parts[i].?;
            std.mem.copyForwards(u8, buff[offset..], template_str);
            offset += template_str.len;
        }

        return buff[0..result_width];
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

    const tpl = try Template.init(tplstr, '{', '}');

    var parts = std.mem.zeroes([4][]const u8);
    parts[0] = "col1";
    parts[1] = "col2";
    parts[2] = "col3";
    parts[3] = "col4";

    var buff = std.mem.zeroes([1000]u8);

    std.debug.print("{s}\n", .{try tpl.template(&parts, &buff)});
}
