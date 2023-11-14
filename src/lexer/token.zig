const std = @import("std");

const fmt = @import("std").fmt;
const Allocator = std.mem.Allocator;
const String = std.ArrayList(u8);

pub const TokenTag = enum {
    // Type annotations
    single_arrow,
    colon,

    // Keywords
    lambda,
    match,
    with,
    let,
    in,
    if_keyword,
    then,
    else_keyword,
    import,
    as,

    // Punctuation
    double_arrow,
    comma,
    semicolon,
    assign,
    left_paren,
    right_paren,
    left_curly_brace,
    right_curly_brace,
    left_square_bracket,
    right_square_bracket,

    // Infix operators
    plus,
    minus,
    slash,
    star,
    pipe,

    // Literals
    id,
    atom,
    number,
    string,

    // Invalid
    invalid,

    // End of File
    eof,
};

// TODO: Save the slice in the original source and delete this union; tokens should only be represented by their tag and have the source span in a separate struct
pub const Token = union(TokenTag) {
    // Type annotations
    single_arrow,
    colon,

    // Keywords
    lambda,
    match,
    with,
    if_keyword,
    then,
    else_keyword,
    import,
    as,

    // Punctuation
    double_arrow,
    comma,
    semicolon,
    assign,
    left_paren,
    right_paren,
    left_curly_brace,
    right_curly_brace,
    left_square_bracket,
    right_square_bracket,
    let,
    in,

    // Infix operators
    plus,
    minus,
    slash,
    star,
    pipe,

    // Literals
    id: String,
    number: String,
    string: String,
    atom: String,

    // Invalid
    invalid: u8,

    // End of File
    eof,

    const Self = @This();

    pub fn destroy(self: *Self) void {
        switch (self.*) {
            Self.id => |*id| id.destroy(),
            else => return,
        }
    }

    pub fn size(self: *const Self) usize {
        switch (self.*) {
            .eof => return 0,
            .comma,
            .semicolon,
            .assign,
            .colon,
            .left_paren,
            .right_paren,
            .left_square_bracket,
            .right_square_bracket,
            .left_curly_brace,
            .right_curly_brace,
            .plus,
            .minus,
            .slash,
            .star,
            .invalid,
            => return 1,
            .lambda,
            .in,
            .single_arrow,
            .double_arrow,
            .pipe,
            .as,
            .if_keyword,
            => return 2,
            .let => return 3,
            .then,
            .else_keyword,
            .with,
            => return 4,
            .match => return 5,
            .import => return 6,
            Self.atom => |atom| return atom.items.len,
            Self.id => |id| return id.items.len,
            Self.number => |number| return number.items.len,
            Self.string => |string| return string.items.len,
        }
    }

    pub fn newId(allocator: Allocator, name: []const u8) !Self {
        var id = String.init(allocator);
        try id.appendSlice(name);
        return Self{ .id = id };
    }

    pub fn newAtom(allocator: Allocator, name: []const u8) !Self {
        var atom = String.init(allocator);
        try atom.appendSlice(name);
        return Self{ .atom = atom };
    }

    pub fn newNumber(allocator: Allocator, number: []const u8) !Self {
        var num = String.init(allocator);
        try num.appendSlice(number);
        return Self{ .number = num };
    }

    pub fn equal(self: *const Self, other: Self) bool {
        switch (self.*) {
            Self.id => |id1| switch (other) {
                Self.id => |id2| return std.mem.eql(u8, id1.items, id2.items),
                else => return false,
            },
            Self.number => |number1| switch (other) {
                Self.number => |number2| return std.mem.eql(u8, number1.items, number2.items),
                else => return false,
            },
            Self.string => |string1| switch (other) {
                Self.string => |string2| return std.mem.eql(u8, string1.items, string2.items),
                else => return false,
            },
            else => |simple| return simple.is(@as(TokenTag, other)),
        }
    }

    pub fn is(self: *const Self, tag: TokenTag) bool {
        return @as(TokenTag, self.*) == tag;
    }

    pub fn clone(self: *const Self, ator: Allocator) !Self {
        switch (self.*) {
            Self.id => |id| return Token{ .id = try id.clone(ator) },
            Self.number => |number| return Token{ .number = try number.clone(ator) },
            Self.string => |string| return Token{ .string = try string.clone(ator) },
            else => return self.*,
        }
    }
};
