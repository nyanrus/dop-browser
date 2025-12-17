"""
    HTMLParser

HTML parsing module providing zero-copy tokenization and string interning.

**DEPRECATED**: This Julia implementation is deprecated in favor of RustParser.
Please use RustParser for production code, which provides:
- HTML parsing using html5ever
- CSS parsing using cssparser  
- Better performance and standards compliance

This module is maintained for compatibility only and will be removed in a future version.

## Migration

```julia
# Old (deprecated):
using DOPBrowser.HTMLParser
pool = StringPool()
tokenizer = Tokenizer(pool)
tokens = tokenize!(tokenizer, "<div><p>Hello</p></div>")

# New (recommended):
using DOPBrowser.RustParser
result = RustParser.parse_html("<div><p>Hello</p></div>")
```
"""
module HTMLParser

@warn "HTMLParser module is deprecated. Please use RustParser instead. This module will be removed in a future version." maxlog=1

include("StringInterner.jl")
include("TokenTape.jl")

using .StringInterner: StringPool, intern!, get_string, get_id
using .TokenTape: TokenType, Token, Tokenizer, tokenize!, reset!, get_tokens,
                  TOKEN_START_TAG, TOKEN_END_TAG, TOKEN_TEXT, TOKEN_COMMENT,
                  TOKEN_DOCTYPE, TOKEN_SELF_CLOSING, TOKEN_ATTRIBUTE

export StringPool, intern!, get_string, get_id
export TokenType, Token, Tokenizer, tokenize!, reset!, get_tokens
export TOKEN_START_TAG, TOKEN_END_TAG, TOKEN_TEXT, TOKEN_COMMENT,
       TOKEN_DOCTYPE, TOKEN_SELF_CLOSING, TOKEN_ATTRIBUTE

export StringInterner, TokenTape

end # module HTMLParser
