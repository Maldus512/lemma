pub const SourceSpan = struct {
    start: usize,
    length: usize,

    const Self = @This();

    pub fn source_slice(self: *const Self, source: []const u8) []const u8 {
        return source[self.start .. self.start + self.length];
    }
};
