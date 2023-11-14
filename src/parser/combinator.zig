const ParseError = error{
    OutOfMemory,
};

pub fn ParserCombinator(Token: type, Ast: type) type {
    const Result =
        struct {
        ast: Ast,
        consumed: usize,
    };

    const ParseFn = *const fn ([]Token) ParseError!?Result;

    const Parser = struct { parse: ParseFn(Token, Ast) };

    return struct {
        Result: Result,
        ParseFn: ParseFn,
        Parser: Parser,

        pub fn expect(
            token: Token,
        ) Parser {
            const clojure = struct {
                fn parse(tokens: []Token) !?Result {
                    if (tokens[0].is(token)) {
                        return Result{};
                    } else {
                        return null;
                    }
                }
            };

            return Parser{ .parse = &clojure.parse };
        }

        //pub fn either(parsers: []Parser) Parser { return }
    };
}

const Tests = struct {
    test "Literal" {}
};
