"""
    HTMLParser

HTML parsing module providing zero-copy tokenization and string interning.

This module provides the core infrastructure for parsing HTML documents:
- `StringInterner`: Zero-copy string interning for efficient memory usage
- `TokenTape`: Flat token tape for cache-efficient DOM construction

## Architecture

HTML input → StringInterner (deduplication) → TokenTape (tokenization) → Token stream

## Usage

```julia
using DOPBrowser.HTMLParser

pool = StringPool()
tokenizer = Tokenizer(pool)
tokens = tokenize!(tokenizer, "<div><p>Hello</p></div>")
```
"""
module HTMLParser

# Include the core components
include("StringInterner.jl")
include("TokenTape.jl")

# Re-export from submodules
using .StringInterner: StringPool, intern!, get_string, get_id
using .TokenTape: TokenType, Token, Tokenizer, tokenize!, reset!, get_tokens,
                  TOKEN_START_TAG, TOKEN_END_TAG, TOKEN_TEXT, TOKEN_COMMENT,
                  TOKEN_DOCTYPE, TOKEN_SELF_CLOSING, TOKEN_ATTRIBUTE

# Export all public API
export StringPool, intern!, get_string, get_id
export TokenType, Token, Tokenizer, tokenize!, reset!, get_tokens
export TOKEN_START_TAG, TOKEN_END_TAG, TOKEN_TEXT, TOKEN_COMMENT,
       TOKEN_DOCTYPE, TOKEN_SELF_CLOSING, TOKEN_ATTRIBUTE

# Re-export submodules for direct access
export StringInterner, TokenTape

end # module HTMLParser
