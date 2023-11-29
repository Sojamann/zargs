const std = @import("std");
const clap = @import("clap");

const MAX_LINE_LENGTH = 10000;
const MAX_COLUMNS = 150;
const MAX_TEMPLATE_RESULT_LENGTH = MAX_LINE_LENGTH * 3;

/// basically cached token iterator result
const ColumnStringView = struct {
    /// original input on which the tokenization is done
    s: []const u8 = undefined,
    cache: [MAX_COLUMNS][]const u8 = std.mem.zeroes([MAX_COLUMNS][]const u8),
    count: usize = 0,

    pub fn update(self: *ColumnStringView, s: []const u8, delim: []const u8) !void {
        self.count = 0;
        self.s = s;

        var iter = std.mem.tokenizeSequence(u8, s, delim);
        while (true) {
            const word = iter.next() orelse break;
            if (self.count + 1 >= MAX_COLUMNS) {
                return error.TooManyColumns;
            }
            self.cache[self.count] = word;
            self.count += 1;
        }
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

    pub fn init(s: []const u8, opening: []const u8, closing: []const u8) !Template {
        var tpl = Template{};
        var offset: usize = 0;
        while (offset < s.len) {
            const start = std.mem.indexOfPos(u8, s, offset, opening) orelse {
                tpl.parts[tpl.num_parts] = s[offset..];
                tpl.targets[tpl.num_parts] = MapTarget.template_str;
                tpl.num_parts += 1;
                break;
            };

            const end = std.mem.indexOfPos(u8, s, start + opening.len, closing) orelse {
                return error.TemplatePlaceholderNotClosed;
            };

            tpl.parts[tpl.num_parts] = s[offset..start];
            tpl.parts[tpl.num_parts + 1] = s[0..0];
            tpl.targets[tpl.num_parts] = MapTarget.template_str;

            const col = std.mem.trim(u8, s[start + opening.len .. end], " ");
            if (col.len == 0) {
                tpl.targets[tpl.num_parts + 1] = MapTarget.all_columns;
            } else {
                tpl.targets[tpl.num_parts + 1] = MapTarget{ .column_index = try std.fmt.parseInt(u8, col, 10) };
            }
            tpl.num_parts += 2;
            offset = end + closing.len;
        }

        if (!tpl.has_placeholders()) {
            if (!std.mem.endsWith(u8, tpl.parts[tpl.num_parts - 1], " ")) {
                tpl.parts[tpl.num_parts] = " ";
                tpl.targets[tpl.num_parts] = MapTarget.template_str;
                tpl.num_parts += 1;
            }
            tpl.parts[tpl.num_parts] = s[0..0];
            tpl.targets[tpl.num_parts] = MapTarget.all_columns;
            tpl.num_parts += 1;
        }

        return tpl;
    }

    pub fn has_placeholders(self: *const Template) bool {
        for (0..self.num_parts) |i| {
            switch (self.targets[i]) {
                .template_str => {},
                else => {
                    return true;
                },
            }
        }
        return false;
    }

    pub fn template(self: *const Template, writer: anytype, input: *ColumnStringView) !void {
        const columns = input.fields();
        for (0..self.num_parts) |i| {
            switch (self.targets[i]) {
                .template_str => {
                    try writer.writeAll(self.parts[i]);
                },
                .column_index => |index| {
                    if (index >= input.count) {
                        return error.TooLittleColumnsForTemplate;
                    }

                    try writer.writeAll(columns[index]);
                },
                .all_columns => {
                    try writer.writeAll(input.s);
                },
            }
        }
    }
};

fn processLineWise(f: std.fs.File, tpl: *const Template, column_delim: []const u8, allocator: std.mem.Allocator) !void {
    var colview: ColumnStringView = ColumnStringView{};

    var tpl_buffer = std.ArrayList(u8).init(allocator);
    defer tpl_buffer.deinit();

    var read_buffer = std.ArrayList(u8).init(allocator);
    defer read_buffer.deinit();

    while (true) {
        f.reader().streamUntilDelimiter(read_buffer.writer(), '\n', MAX_LINE_LENGTH) catch |err| {
            switch (err) {
                error.EndOfStream => {
                    break;
                },
                error.StreamTooLong => {
                    _ = try std.io.getStdErr().write("The input line was too long!\n");
                    std.os.exit(1);
                },
                else => {
                    _ = try std.io.getStdErr().write("Encountered unexpected error while reading stdin!\n");
                    std.os.exit(1);
                },
            }
        };

        try colview.update(read_buffer.items, column_delim);
        try tpl.template(tpl_buffer.writer(), &colview);

        try colview.update(tpl_buffer.items, " ");
        var child = std.process.Child.init(colview.fields(), allocator);
        _ = child.spawnAndWait() catch |err| {
            var stderr = std.io.getStdErr();
            switch (err) {
                error.FileNotFound => {
                    _ = try stderr.write("Could not start process ... ");
                    _ = try stderr.write(colview.fields()[0]);
                    _ = try stderr.write(" could not be found! Is it in PATH?");
                },
                else => {
                    _ = try stderr.write("failed starting process ... ");
                    _ = try stderr.write(@typeName(@TypeOf(err)));
                    _ = try stderr.write("\n");
                },
            }
            std.os.exit(1);
        };

        tpl_buffer.clearRetainingCapacity();
        read_buffer.clearRetainingCapacity();
    }
}

pub fn main() !void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help                        Display this help and exit.
        \\-d, --delimiter <str>             Column delimiter to use for templating (Defaults to: ' ').
        \\-s, --tplstart <str>              What character sequence starts a template placeholder (Defaults to: '{').
        \\-e, --tplend <str>                What character sequence ends a template placeholder (Defaults to: '}').
        \\<str>...
        \\
    );
    const err_writer = std.io.getStdErr().writer();

    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{}) catch {
        return clap.usage(err_writer, clap.Help, &params);
    };
    defer res.deinit();

    if (res.args.help != 0) {
        return clap.help(err_writer, clap.Help, &params, .{});
    }

    if (res.positionals.len < 1) {
        return clap.usage(err_writer, clap.Help, &params);
    }

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const delim = res.args.delimiter orelse " ";
    const opening = res.args.tplstart orelse "{";
    const closing = res.args.tplend orelse "}";
    const tplstr = try std.mem.join(allocator, " ", res.positionals);
    defer allocator.free(tplstr);

    const tpl = try Template.init(tplstr, opening, closing);

    try processLineWise(std.io.getStdIn(), &tpl, delim, allocator);
}
