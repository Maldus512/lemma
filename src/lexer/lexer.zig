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
pub const TokenTag = imports.token.TokenTag;
pub const TokenIndex = usize;

const TokenData = struct {
    token: Token,
    position: usize,
};

pub const ScanResult = struct {
    tokens: TokenList,
    positions: TokenPositions,

    const Self = @This();

    pub fn getToken(self: *const Self, index: TokenIndex) ?Token {
        if (index >= self.tokens.items.len) {
            return null;
        } else {
            return self.tokens.items[index];
        }
    }

    pub fn getTokenPosition(self: *const Self, index: TokenIndex) ?SourceSpan {
        const token = self.getToken(index) orelse return null;

        if (index >= self.positions.items.len) {
            return null;
        } else {
            const position = self.positions.items[index];
            return SourceSpan{ .begin = position, .end = position + token.size() };
        }
    }

    pub fn intoIter(self: *const Self) ScanResultIterator {
        return ScanResultIterator{ .scan_result = self, .next_token = 0 };
    }

    pub fn deinit(self: *Self) void {
        self.tokens.deinit();
        self.positions.deinit();
    }
};

pub const ScanResultIterator = struct {
    scan_result: *const ScanResult,
    next_token: TokenIndex,

    const Self = @This();

    pub fn next(self: *Self) Token {
        if (self.next_token < self.scan_result.tokens.items.len) {
            defer self.next_token += 1;
            return self.scan_result.tokens.items[self.next_token];
        } else {
            return .eof;
        }
    }

    pub fn forward(self: *Self, skip_of: TokenIndex) void {
        if (self.next_token + skip_of - 1 < self.scan_result.tokens.items.len) {
            self.next_token += skip_of;
        }
    }

    pub fn peek(self: *Self, ahead_of: TokenIndex) Token {
        if (self.next_token + ahead_of < self.scan_result.tokens.items.len) {
            return self.scan_result.tokens.items[self.next_token + ahead_of];
        } else {
            return .eof;
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
    var tokens = TokenList.init(allocator);
    errdefer tokens.deinit();
    var positions = TokenPositions.init(allocator);
    errdefer positions.deinit();

    var lexer = Lexer{ .allocator = allocator, .next_char = 0, .source = source };

    while (try lexer.getTokenData()) |token_data| {
        // Scan everything
        try tokens.append(token_data.token);
        try positions.append(token_data.position);
    }
    return ScanResult{ .tokens = tokens, .positions = positions };
}

// TODO: refactor names (getTokenData -> nextTokenData, getToken -> next)
const Lexer = struct {
    allocator: Allocator,
    next_char: usize,
    source: []const u8,

    const Self = @This();

    fn getTokenData(self: *Self) !?TokenData {
        const token = try self.getToken() orelse return null;
        return TokenData{ .token = token, .position = self.next_char -| token.size() };
    }

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
        self.next_char += count;
    }

    fn next(self: *Self) ?u8 {
        if (self.next_char < self.source.len) {
            defer self.next_char += 1;
            return self.source[self.next_char];
        } else {
            return null;
        }
    }

    fn peek(self: *const Self, ahead_of: usize) ?u8 {
        if (self.next_char + ahead_of < self.source.len) {
            return self.source[self.next_char + ahead_of];
        } else {
            return null;
        }
    }

    fn chompPunctuation(self: *Self) ?Token {
        const StringToken = struct {
            string: []const u8,
            token: Token,

            fn new(string: []const u8, token: Token) @This() {
                return @This(){ .string = string, .token = token };
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
                return st.token;
            }
        }

        return Token{ .invalid = self.next() orelse return null };
    }

    fn chompNumber(self: *Self) !?Token {
        var str = String.init(self.allocator);
        errdefer str.deinit();

        if (self.peek(0)) |char| {
            // First symbol should be a character
            if (isDigit(char)) {
                self.consume(1);
                try str.append(char);
            } else {
                return null;
            }
        }

        while (self.peek(0)) |char| {
            if (isDigit(char)) {
                _ = self.next();
                try str.append(char);
            } else if (isWhitespace(char) or isArithmeticSymbol(char)) {
                break;
            } else if (!isWhitespace(char)) {
                return Token{ .invalid = char };
            }
        }

        return Token{ .number = str };
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
        var str = String.init(self.allocator);
        errdefer str.deinit();

        if (self.match('@')) {
            self.consume(1);
        } else {
            return null;
        }

        while (self.peek(0)) |char| {
            if (isAlphaNumeric(char)) {
                self.consume(1);
                try str.append(char);
            } else {
                break;
            }
        }

        return Token{ .atom = str };
    }

    fn chompIdOrKeyword(self: *Self) !?Token {
        var str = String.init(self.allocator);
        errdefer str.deinit();

        if (self.peek(0)) |char| {
            // First symbol should be a character
            if (isCharacter(char)) {
                self.consume(1);
                try str.append(char);
            } else {
                return null;
            }
        }

        while (self.peek(0)) |char| {
            if (isAlphaNumeric(char)) {
                self.consume(1);
                try str.append(char);
            } else {
                break;
            }
        }

        const SymbolTokenTuple = struct {
            chars: []const u8,
            token: Token,
        };
        const tokensSymbols = [_]SymbolTokenTuple{
            .{ .chars = "let", .token = .let },
            .{ .chars = "in", .token = .in },
            .{ .chars = "fn", .token = .lambda },
            .{ .chars = "match", .token = .match },
            .{ .chars = "with", .token = .with },
            .{ .chars = "if", .token = .if_keyword },
            .{ .chars = "then", .token = .then },
            .{ .chars = "else", .token = .else_keyword },
            .{ .chars = "as", .token = .as },
            .{ .chars = "import", .token = .import },
        };

        for (tokensSymbols) |sst| {
            if (str.items.len == sst.chars.len and std.mem.eql(u8, str.items, sst.chars)) {
                return sst.token;
            }
        }

        return Token{ .id = str };
    }

    fn isNameStart(char: u8) bool {
        return isCharacter(char);
    }

    fn isNumberStart(char: u8) bool {
        return isDigit(char);
    }
};

fn isWhitespace(char: u8) bool {
    const WHITESPACE: []const u8 = " \t\n";
    return isInSlice(u8, char, WHITESPACE);
}

fn isArithmeticSymbol(char: u8) bool {
    const WHITESPACE: []const u8 = "+-*/";
    return isInSlice(u8, char, WHITESPACE);
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
