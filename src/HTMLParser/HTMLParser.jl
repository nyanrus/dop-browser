"""
    HTMLParser

HTML parsing module providing zero-copy tokenization and string interning.

**INTERNAL USE ONLY**: This Julia implementation is used internally by legacy modules.
For new code, use RustParser which provides:
- HTML parsing using html5ever
- CSS parsing using cssparser  
- Better performance and standards compliance

This module is maintained for internal compatibility only.
"""
module HTMLParser

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
