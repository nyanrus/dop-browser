"""
    TokenTape

Flat token tape for HTML parsing.

This module provides HTML tokenization with a flat token tape structure.
For high-performance parsing, consider using RustParser which provides
Rust-based HTML parsing via html5ever.

NOTE: This is a minimal implementation. For production use, prefer RustParser.
"""
module TokenTape

using ..StringInterner: StringPool, intern!

export TokenType, Token, Tokenizer, tokenize!, reset!, get_tokens
export TOKEN_START_TAG, TOKEN_END_TAG, TOKEN_TEXT, TOKEN_COMMENT,
       TOKEN_DOCTYPE, TOKEN_SELF_CLOSING, TOKEN_ATTRIBUTE

"""
    TokenType

Enumeration of HTML token types.
"""
@enum TokenType::UInt8 begin
    TOKEN_START_TAG = 1
    TOKEN_END_TAG = 2
    TOKEN_TEXT = 3
    TOKEN_COMMENT = 4
    TOKEN_DOCTYPE = 5
    TOKEN_SELF_CLOSING = 6
    TOKEN_ATTRIBUTE = 7
end

"""
    Token

A single HTML token in the tape.
"""
struct Token
    type::TokenType
    name_id::UInt32
    value_id::UInt32
    source_offset::UInt32
end

"""
    Tokenizer

HTML tokenizer that produces a flat token tape.
"""
mutable struct Tokenizer
    tokens::Vector{Token}
    strings::StringPool
    
    function Tokenizer(pool::StringPool)
        new(Token[], pool)
    end
end

"""
    reset!(tokenizer::Tokenizer)

Clear the token tape for reuse.
"""
function reset!(tokenizer::Tokenizer)
    empty!(tokenizer.tokens)
    return tokenizer
end

"""
    get_tokens(tokenizer::Tokenizer) -> Vector{Token}

Get the token tape.
"""
function get_tokens(tokenizer::Tokenizer)::Vector{Token}
    return tokenizer.tokens
end

"""
    tokenize!(tokenizer::Tokenizer, html::AbstractString) -> Vector{Token}

Parse HTML into a flat token tape.
"""
function tokenize!(tokenizer::Tokenizer, html::AbstractString)::Vector{Token}
    reset!(tokenizer)
    
    pos = 1
    len = ncodeunits(html)
    
    while pos <= len
        if html[pos] == '<'
            pos = parse_tag!(tokenizer, html, pos, len)
        else
            pos = parse_text!(tokenizer, html, pos, len)
        end
    end
    
    return tokenizer.tokens
end

function parse_tag!(tokenizer::Tokenizer, html::AbstractString, pos::Int, len::Int)::Int
    start_offset = UInt32(pos)
    pos += 1
    
    if pos > len
        return pos
    end
    
    if html[pos] == '!'
        return parse_special_tag!(tokenizer, html, pos, len, start_offset)
    elseif html[pos] == '/'
        return parse_end_tag!(tokenizer, html, pos + 1, len, start_offset)
    else
        return parse_start_tag!(tokenizer, html, pos, len, start_offset)
    end
end

function parse_special_tag!(tokenizer::Tokenizer, html::AbstractString, pos::Int, len::Int, start_offset::UInt32)::Int
    pos += 1
    
    if pos + 1 <= len && html[pos] == '-' && html[pos + 1] == '-'
        pos += 2
        comment_start = pos
        while pos + 2 <= len
            if html[pos] == '-' && html[pos + 1] == '-' && html[pos + 2] == '>'
                comment_text = SubString(html, comment_start, pos - 1)
                value_id = intern!(tokenizer.strings, comment_text)
                push!(tokenizer.tokens, Token(TOKEN_COMMENT, UInt32(0), value_id, start_offset))
                return pos + 3
            end
            pos += 1
        end
        comment_text = SubString(html, comment_start, len)
        value_id = intern!(tokenizer.strings, comment_text)
        push!(tokenizer.tokens, Token(TOKEN_COMMENT, UInt32(0), value_id, start_offset))
        return len + 1
    end
    
    if pos + 6 <= len && uppercase(SubString(html, pos, pos + 6)) == "DOCTYPE"
        pos += 7
        while pos <= len && html[pos] != '>'
            pos += 1
        end
        push!(tokenizer.tokens, Token(TOKEN_DOCTYPE, UInt32(0), UInt32(0), start_offset))
        return pos + 1
    end
    
    while pos <= len && html[pos] != '>'
        pos += 1
    end
    return pos + 1
end

function parse_end_tag!(tokenizer::Tokenizer, html::AbstractString, pos::Int, len::Int, start_offset::UInt32)::Int
    while pos <= len && isspace(html[pos])
        pos += 1
    end
    
    name_start = pos
    while pos <= len && html[pos] != '>' && !isspace(html[pos])
        pos += 1
    end
    
    if name_start < pos
        name = lowercase(SubString(html, name_start, pos - 1))
        name_id = intern!(tokenizer.strings, name)
        push!(tokenizer.tokens, Token(TOKEN_END_TAG, name_id, UInt32(0), start_offset))
    end
    
    while pos <= len && html[pos] != '>'
        pos += 1
    end
    
    return pos + 1
end

function parse_start_tag!(tokenizer::Tokenizer, html::AbstractString, pos::Int, len::Int, start_offset::UInt32)::Int
    name_start = pos
    while pos <= len && html[pos] != '>' && html[pos] != '/' && !isspace(html[pos])
        pos += 1
    end
    
    tag_name = lowercase(SubString(html, name_start, pos - 1))
    tag_name_id = intern!(tokenizer.strings, tag_name)
    
    is_self_closing = false
    attributes = Token[]
    
    while pos <= len
        while pos <= len && isspace(html[pos])
            pos += 1
        end
        
        if pos > len
            break
        end
        
        if html[pos] == '>'
            pos += 1
            break
        end
        
        if html[pos] == '/'
            if pos + 1 <= len && html[pos + 1] == '>'
                is_self_closing = true
                pos += 2
                break
            end
            pos += 1
            continue
        end
        
        attr_name_start = pos
        while pos <= len && html[pos] != '=' && html[pos] != '>' && html[pos] != '/' && !isspace(html[pos])
            pos += 1
        end
        
        if attr_name_start >= pos
            continue
        end
        
        attr_name = lowercase(SubString(html, attr_name_start, pos - 1))
        attr_name_id = intern!(tokenizer.strings, attr_name)
        attr_value_id = UInt32(0)
        
        while pos <= len && isspace(html[pos])
            pos += 1
        end
        
        if pos <= len && html[pos] == '='
            pos += 1
            while pos <= len && isspace(html[pos])
                pos += 1
            end
            
            if pos <= len
                if html[pos] == '"' || html[pos] == '\''
                    quote_char = html[pos]
                    pos += 1
                    value_start = pos
                    while pos <= len && html[pos] != quote_char
                        pos += 1
                    end
                    if value_start <= pos - 1
                        attr_value = SubString(html, value_start, pos - 1)
                        attr_value_id = intern!(tokenizer.strings, attr_value)
                    end
                    pos += 1
                else
                    value_start = pos
                    while pos <= len && html[pos] != '>' && html[pos] != '/' && !isspace(html[pos])
                        pos += 1
                    end
                    if value_start <= pos - 1
                        attr_value = SubString(html, value_start, pos - 1)
                        attr_value_id = intern!(tokenizer.strings, attr_value)
                    end
                end
            end
        end
        
        push!(attributes, Token(TOKEN_ATTRIBUTE, attr_name_id, attr_value_id, start_offset))
    end
    
    token_type = is_self_closing ? TOKEN_SELF_CLOSING : TOKEN_START_TAG
    push!(tokenizer.tokens, Token(token_type, tag_name_id, UInt32(0), start_offset))
    append!(tokenizer.tokens, attributes)
    
    return pos
end

function parse_text!(tokenizer::Tokenizer, html::AbstractString, pos::Int, len::Int)::Int
    start_pos = pos
    start_offset = UInt32(pos)
    
    while pos <= len && html[pos] != '<'
        pos += 1
    end
    
    if start_pos < pos
        text = SubString(html, start_pos, pos - 1)
        stripped = strip(text)
        if !isempty(stripped)
            text_id = intern!(tokenizer.strings, stripped)
            push!(tokenizer.tokens, Token(TOKEN_TEXT, UInt32(0), text_id, start_offset))
        end
    end
    
    return pos
end

end # module TokenTape
