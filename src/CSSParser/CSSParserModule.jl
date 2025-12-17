"""
    CSSParserModule

CSS parsing module providing style computation and property parsing.

This module provides:
- CSS style parsing (inline and block)
- Color parsing (hex, rgb, rgba, named colors)
- Length parsing (px, %, em, mm, auto)
- Comprehensive CSS property support

For high-performance parsing, consider using RustParser which provides
Rust-based CSS parsing via cssparser.

## Usage

```julia
using DOPBrowser.CSSParserModule

styles = parse_inline_style("width: 100px; background-color: red;")
color = parse_color("#ff0000")
(px, is_auto) = parse_length("50%", 800.0f0)
```
"""
module CSSParserModule

include("CSSCore.jl")

using .CSSCore: CSSStyles, parse_inline_style, parse_color, parse_length,
                POSITION_STATIC, POSITION_RELATIVE, POSITION_ABSOLUTE, POSITION_FIXED,
                OVERFLOW_VISIBLE, OVERFLOW_HIDDEN,
                DISPLAY_BLOCK, DISPLAY_INLINE, DISPLAY_NONE, DISPLAY_TABLE, 
                DISPLAY_TABLE_CELL, DISPLAY_TABLE_ROW, DISPLAY_INLINE_BLOCK,
                FLOAT_NONE, FLOAT_LEFT, FLOAT_RIGHT,
                CLEAR_NONE, CLEAR_LEFT, CLEAR_RIGHT, CLEAR_BOTH,
                BORDER_STYLE_NONE, BORDER_STYLE_SOLID, BORDER_STYLE_DOTTED, BORDER_STYLE_DASHED

export CSSStyles, parse_inline_style, parse_color, parse_length
export POSITION_STATIC, POSITION_RELATIVE, POSITION_ABSOLUTE, POSITION_FIXED
export OVERFLOW_VISIBLE, OVERFLOW_HIDDEN
export DISPLAY_BLOCK, DISPLAY_INLINE, DISPLAY_NONE, DISPLAY_TABLE, 
       DISPLAY_TABLE_CELL, DISPLAY_TABLE_ROW, DISPLAY_INLINE_BLOCK
export FLOAT_NONE, FLOAT_LEFT, FLOAT_RIGHT
export CLEAR_NONE, CLEAR_LEFT, CLEAR_RIGHT, CLEAR_BOTH
export BORDER_STYLE_NONE, BORDER_STYLE_SOLID, BORDER_STYLE_DOTTED, BORDER_STYLE_DASHED

export CSSCore

end # module CSSParserModule
