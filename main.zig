const std = @import("std");

const MAX_LINE_LENGTH = 1000;
const MAX_COLUMNS = 150;
const MAX_TEMPLATE_RESULT_LENGTH = 2000;

/// basically cached token iterator result
const ColumnStringView = struct {
    cache: [MAX_COLUMNS][]const u8 = std.mem.zeroes([MAX_COLUMNS][]const u8),
    count: usize = 0,

    pub fn update(self: *ColumnStringView, s: []const u8, delim: []const u8) ![][]const u8 {
        self.count = 0;

        var iter = std.mem.tokenizeSequence(u8, s, delim);
        while (true) {
            const word = iter.next() orelse break;
            if (self.count + 1 >= MAX_COLUMNS) {
                return error.TooManyColumns;
            }
            self.cache[self.count] = word;
            self.count += 1;
        }

        return self.fields();
    }

    pub fn fields(self: *ColumnStringView) [][]const u8 {
        return self.cache[0..self.count];
    }
};

const Template = struct {
    /// NOTE: the spot that the template had is an empty slice
    parts: [MAX_COLUMNS]?[]const u8 = std.mem.zeroes([MAX_COLUMNS]?[]const u8),

    /// col mapping specifies which placeholder the column has
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
                size_used_columns += columns[col].len;
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

// TODO: use a heap allocated buffer as this is much faster than having
//          so many read syscalls
//          .
fn processLineWise(f: std.fs.File, tpl: *const Template, allocator: std.mem.Allocator) !void {
    var line_buff = try allocator.alloc(u8, MAX_LINE_LENGTH);
    defer allocator.free(line_buff);
    var tpl_buffer = try allocator.alloc(u8, MAX_TEMPLATE_RESULT_LENGTH);
    defer allocator.free(tpl_buffer);

    var tokenizationCache: ColumnStringView = ColumnStringView{};
    var offset: usize = 0;

    var n = try f.read(line_buff);
    while (true) {
        if (std.mem.indexOf(u8, line_buff[offset..], "\n")) |found| {
            const line = line_buff[offset .. offset + found];
            if (line.len != 0) {
                // TODO: accept a delimiter instead of this hard coded one
                const tpl_res = try tpl.template(try tokenizationCache.update(line, " "), tpl_buffer);

                // TODO: need error handling for FileNotFound and different exist codes.
                var child = std.process.Child.init(try tokenizationCache.update(tpl_res, " "), allocator);
                std.debug.print("Res: {}", .{try child.spawnAndWait()});
            }
            offset += found + 1;
            continue;
        }

        std.mem.copyForwards(u8, line_buff, line_buff[offset..]);

        n = try f.read(line_buff[line_buff.len - offset ..]);
        if (n == 0) {
            // if we normyally could have read more the line was just
            // too long for our buffer
            if (try f.read(line_buff[0..1]) > 0) {
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

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const tpl = try Template.init(tplstr, '{', '}');

    try processLineWise(stdin, &tpl, allocator);
}
