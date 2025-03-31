const std = @import("std");

const fmt = @import("std").fmt;
const Allocator = std.mem.Allocator;
const SourceSpan = @import("../common/meta.zig");

// TODO: Save the slice in the original source and delete this union; tokens should only be represented by their tag and have the source span in a separate struct
pub const Token = struct {
    pub const Tag = enum {
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
        identifier,
        atom,
        number,
        string,

        // Invalid
        invalid,

        // End of File
        eof,
    };

    tag: Tag,
    // Span of character in the original source
    source_span: []const u8,

    const Self = @This();

    /// Returns the character length of the token
    pub fn size(self: *const Self) usize {
        return self.source_span.len;
    }

    /// Returns starting index of the token in the source text
    pub fn getStartingIndex(self: *const Self, source: []const u8) usize {
        return @intFromPtr(self.source_span.ptr) - @intFromPtr(source.ptr);
    }
};
