const std = @import("std");

const MAX_LINE_LENGTH = 10000;
const MAX_COLUMNS = 150;
const MAX_TEMPLATE_RESULT_LENGTH = MAX_LINE_LENGTH * 3;

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
    const MapTarget = union(enum) {
        column_index: usize,
        all_columns: void,
        template_str: void,
    };

    parts: [MAX_COLUMNS][]const u8 = std.mem.zeroes([MAX_COLUMNS][]const u8),
    targets: [MAX_COLUMNS]MapTarget = undefined,
    num_parts: usize = 0,

    pub fn init(s: []const u8, opening: u8, closing: u8) !Template {
        var tpl = Template{};
        var offset: usize = 0;
        while (offset < s.len) {
            const start = std.mem.indexOfScalarPos(u8, s, offset, opening) orelse {
                tpl.parts[tpl.num_parts] = s[offset..];
                tpl.targets[tpl.num_parts] = MapTarget.template_str;
                tpl.num_parts += 1;
                break;
            };

            const end = std.mem.indexOfScalarPos(u8, s, start + 1, closing) orelse {
                return error.InvalidTemplateSyntax;
            };

            tpl.parts[tpl.num_parts] = s[offset..start];
            tpl.parts[tpl.num_parts + 1] = s[0..0];
            tpl.targets[tpl.num_parts] = MapTarget.template_str;

            const col = std.mem.trim(u8, s[start + 1 .. end], " ");
            if (col.len > 0) {
                tpl.targets[tpl.num_parts + 1] = MapTarget{ .column_index = try std.fmt.parseInt(u8, col, 10) };
            } else {
                tpl.targets[tpl.num_parts + 1] = MapTarget.all_columns;
            }

            tpl.num_parts += 2;
            offset = end + 1;
        }

        return tpl;
    }

    pub fn template(self: Template, columns: [][]const u8, buff: []u8) ![]u8 {
        var offset: usize = 0;
        for (0..self.num_parts) |i| {
            switch (self.targets[i]) {
                .template_str => {
                    const s = self.parts[i];
                    if (s.len + offset >= buff.len) {
                        return error.TemplateResultTooLong;
                    }

                    std.mem.copyForwards(u8, buff[offset..], s);
                    offset += s.len;
                },
                .column_index => |index| {
                    if (index >= columns.len) {
                        return error.TooLittleColumnsForTemplate;
                    }

                    const s = columns[index];
                    if (s.len + offset >= buff.len) {
                        return error.TemplateResultTooLong;
                    }

                    std.mem.copyForwards(u8, buff[offset..], s);
                    offset += s.len;
                },
                .all_columns => {
                    for (columns) |s| {
                        if (s.len + offset >= buff.len) {
                            return error.TemplateResultTooLong;
                        }

                        std.mem.copyForwards(u8, buff[offset..], s);
                        offset += s.len;
                    }
                },
            }
        }

        return buff[0..offset];
    }
};

fn processLineWise(f: std.fs.File, tpl: *const Template, column_delim: []const u8, allocator: std.mem.Allocator) !void {
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
                const columns = try tpl.template(try tokenizationCache.update(line, column_delim), tpl_buffer);

                // TODO: need error handling for FileNotFound and different exist codes.
                var child = std.process.Child.init(try tokenizationCache.update(columns, " "), allocator);
                _ = try child.spawnAndWait();
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

    try processLineWise(stdin, &tpl, " ", allocator);
}
