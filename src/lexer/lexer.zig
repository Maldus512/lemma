const std = @import("std");
const fmt = @import("std").fmt;

const imports = .{
    .token = @import("token.zig"),
    .common = @import("../common/common.zig"),
    .meta = @import("../common/meta.zig"),
};

const Allocator = std.mem.Allocator;
const String = std.ArrayList(u8);
const TokenList = std.ArrayList(Token);
const TokenPositions = std.ArrayList(usize);

const SourceSpan = imports.meta.SourceSpan;

pub const Token = imports.token.Token;
pub const TokenIndex = usize;

/// Result of the scanning procedure
pub const ScanResult = struct {
    allocator: Allocator,

    /// Reference to the source code
    source: []const u8,

    /// Token list
    tokens: TokenList,

    const Self = @This();

    /// Get a token from the list
    pub fn getToken(self: *const Self, index: TokenIndex) ?Token {
        if (index >= self.tokens.items.len) {
            return null;
        } else {
            return self.tokens.items[index];
        }
    }

    /// Transform this result into a token iterator
    pub fn intoIter(self: *const Self) ScanResultIterator {
        return ScanResultIterator{ .scan_result = self, .next_token = 0 };
    }

    /// Deinitialize
    pub fn deinit(self: *Self) void {
        self.tokens.deinit(self.allocator);
    }
};

/// Iterator struct for the token list
pub const ScanResultIterator = struct {
    scan_result: *const ScanResult,
    next_token: TokenIndex,

    const Self = @This();

    pub fn next(self: *Self) Token {
        if (self.next_token < self.scan_result.tokens.items.len) {
            defer self.next_token += 1;
            return self.scan_result.tokens.items[self.next_token];
        } else {
            return Token{
                .tag = .eof,
                .source_span = self.scan_result.source[self.scan_result.source.len..self.scan_result.source.len],
            };
        }
    }

    pub fn forward(self: *Self, skip_of: TokenIndex) void {
        if (self.next_token + skip_of - 1 < self.scan_result.tokens.items.len) {
            self.next_token += skip_of;
        }
    }

    pub fn peek(self: *const Self, ahead_of: TokenIndex) Token {
        if (self.next_token + ahead_of < self.scan_result.tokens.items.len) {
            return self.scan_result.tokens.items[self.next_token + ahead_of];
        } else {
            return Token{
                .tag = .eof,
                .source_span = self.scan_result.source[self.scan_result.source.len..self.scan_result.source.len],
            };
        }
    }

    pub fn at(self: *const Self) TokenIndex {
        return self.next_token;
    }

    pub fn isDone(self: *const Self) bool {
        return self.next_token >= self.scan_result.tokens.items.len;
    }
};

pub fn scan(allocator: Allocator, source: []const u8) !ScanResult {
    var tokens = TokenList{};
    errdefer tokens.deinit(allocator);

    var lexer = Lexer{ .allocator = allocator, .index = 0, .source = source };

    while (try lexer.getToken()) |token| {
        // Scan everything
        try tokens.append(allocator, token);
    }
    return ScanResult{ .source = source, .tokens = tokens, .allocator = allocator };
}

const Lexer = struct {
    allocator: Allocator,
    index: usize,
    source: []const u8,

    const Self = @This();

    // TODO: optimize, probably with a state machine
    fn getToken(self: *Self) !?Token {
        var comment = false;

        while (true) {
            if (comment) {
                if (self.next()) |char| {
                    // If in comment context ignore everything
                    if (char == '\n') {
                        comment = false;
                    }
                } else {
                    continue;
                }
            }

            while (self.chompWhitespace() orelse break) {
                // Whitespace is insignificant
            }
            if (self.chompComment()) {
                comment = true;
            } else if (try self.chompIdOrKeyword()) |token| {
                return token;
            } else if (try self.chompAtom()) |token| {
                return token;
            } else if (try self.chompNumber()) |token| {
                return token;
            } else if (self.chompPunctuation()) |token| {
                return token;
            } else {
                break;
            }
        }

        return null;
    }

    fn match(self: *Self, expected: u8) bool {
        if (self.peek(0)) |char| {
            return char == expected;
        } else {
            return false;
        }
    }

    fn consume(self: *Self, count: usize) void {
        self.index += count;
    }

    fn next(self: *Self) ?u8 {
        if (self.index < self.source.len) {
            defer self.index += 1;
            return self.source[self.index];
        } else {
            return null;
        }
    }

    fn peek(self: *const Self, ahead_of: usize) ?u8 {
        if (self.index + ahead_of < self.source.len) {
            return self.source[self.index + ahead_of];
        } else {
            return null;
        }
    }

    fn chompPunctuation(self: *Self) ?Token {
        const start = self.index;

        const StringToken = struct {
            string: []const u8,
            token_tag: Token.Tag,

            fn new(string: []const u8, token_tag: Token.Tag) @This() {
                return @This(){ .string = string, .token_tag = token_tag };
            }
        };

        const string_tokens = [_]StringToken{
            StringToken.new("|>", .pipe),
            StringToken.new("->", .single_arrow),
            StringToken.new("=>", .double_arrow),
            StringToken.new(":", .colon),
            StringToken.new(",", .comma),
            StringToken.new(";", .semicolon),
            StringToken.new("=", .assign),
            StringToken.new("(", .left_paren),
            StringToken.new(")", .right_paren),
            StringToken.new("{", .left_curly_brace),
            StringToken.new("}", .right_curly_brace),
            StringToken.new("[", .left_square_bracket),
            StringToken.new("]", .right_square_bracket),
            StringToken.new("+", .plus),
            StringToken.new("-", .minus),
            StringToken.new("/", .slash),
            StringToken.new("*", .star),
        };

        for (string_tokens) |st| {
            var consumed: usize = 0;

            const found = for (st.string) |expected| {
                if (self.peek(consumed)) |char| {
                    if (expected != char) {
                        break false;
                    }
                } else {
                    break false;
                }
                consumed += 1;
            } else end: {
                break :end true;
            };

            if (found) {
                self.consume(consumed);
                return Token{ .tag = st.token_tag, .source_span = self.getSliceFrom(start) };
            }
        }

        return Token{ .tag = .invalid, .source_span = self.getSliceFrom(start) };
    }

    fn chompNumber(self: *Self) !?Token {
        const start = self.index;

        if (self.peek(0)) |char| {
            // First symbol should be a character
            if (isDigit(char)) {
                self.consume(1);
            } else {
                return null;
            }
        }

        while (self.peek(0)) |char| {
            if (isDigit(char)) {
                _ = self.next();
            } else if (isWhitespace(char) or isArithmeticSymbol(char) or isExpressionTerminator(char)) {
                break;
            } else if (!isWhitespace(char)) {
                return Token{
                    .tag = .invalid,
                    .source_span = self.getSliceFrom(start),
                };
            }
        }

        return Token{ .tag = .number, .source_span = self.getSliceFrom(start) };
    }

    fn chompWhitespace(self: *Self) ?bool {
        switch (self.peek(0) orelse return null) {
            '\t',
            '\r',
            ' ',
            '\n',
            => {
                self.consume(1);
                return true;
            },
            else => return false,
        }
    }

    fn chompComment(self: *Self) bool {
        if (self.peek(0)) |char| {
            if (char == '/') {
                if (self.peek(1)) |second_char| {
                    if (second_char == '/') {
                        self.consume(2);
                        return true;
                    }
                }
            }
        }
        return false;
    }

    fn chompAtom(self: *Self) !?Token {
        const start = self.index;

        if (self.match('@')) {
            self.consume(1);
        } else {
            return null;
        }

        while (self.peek(0)) |char| {
            if (isAlphaNumeric(char)) {
                self.consume(1);
            } else {
                break;
            }
        }

        const atom = self.getSliceFrom(start);

        return Token{ .tag = .atom, .source_span = atom };
    }

    fn chompIdOrKeyword(self: *Self) !?Token {
        const start = self.index;

        if (self.peek(0)) |char| {
            // First symbol should be a character
            if (isCharacter(char)) {
                self.consume(1);
            } else {
                return null;
            }
        }

        while (self.peek(0)) |char| {
            if (isAlphaNumeric(char)) {
                self.consume(1);
            } else {
                break;
            }
        }

        const SymbolTokenTuple = struct {
            chars: []const u8,
            token_tag: Token.Tag,
        };
        const tokensSymbols = [_]SymbolTokenTuple{
            .{ .chars = "let", .token_tag = .let },
            .{ .chars = "in", .token_tag = .in },
            .{ .chars = "fn", .token_tag = .lambda },
            .{ .chars = "match", .token_tag = .match },
            .{ .chars = "with", .token_tag = .with },
            .{ .chars = "if", .token_tag = .if_keyword },
            .{ .chars = "then", .token_tag = .then },
            .{ .chars = "else", .token_tag = .else_keyword },
            .{ .chars = "as", .token_tag = .as },
            .{ .chars = "import", .token_tag = .import },
        };

        const string = self.getSliceFrom(start);

        for (tokensSymbols) |sst| {
            if (string.len == sst.chars.len and std.mem.eql(u8, string, sst.chars)) {
                return Token{ .tag = sst.token_tag, .source_span = string };
            }
        }

        return Token{ .tag = .identifier, .source_span = string };
    }

    fn isNameStart(char: u8) bool {
        return isCharacter(char);
    }

    fn isNumberStart(char: u8) bool {
        return isDigit(char);
    }

    fn getSliceFrom(self: *const Self, start: usize) []const u8 {
        return self.source[start..self.index];
    }
};

fn isWhitespace(char: u8) bool {
    const WHITESPACE: []const u8 = " \t\n";
    return isInSlice(u8, char, WHITESPACE);
}

fn isArithmeticSymbol(char: u8) bool {
    const ARITHMETIC: []const u8 = "+-*/";
    return isInSlice(u8, char, ARITHMETIC);
}

fn isExpressionTerminator(char: u8) bool {
    const TERMINATOR: []const u8 = "();,";
    return isInSlice(u8, char, TERMINATOR);
}

fn isAlphaNumeric(char: u8) bool {
    return isCharacter(char) or isDigit(char);
}

fn isCharacter(char: u8) bool {
    const CHARACTERS: []const u8 = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_";
    return isInSlice(u8, char, CHARACTERS);
}

fn isDigit(char: u8) bool {
    const DIGITS: []const u8 = "0123456789";
    return isInSlice(u8, char, DIGITS);
}

fn isInSlice(comptime S: type, elem: S, slice: []const S) bool {
    for (slice) |i| {
        if (elem == i) {
            return true;
        }
    }
    return false;
}
