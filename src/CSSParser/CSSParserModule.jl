"""
    CSSParserModule

CSS parsing module providing style computation and property parsing.

**DEPRECATED**: This Julia implementation is deprecated in favor of RustParser.
Please use RustParser for production code, which provides:
- CSS parsing using cssparser crate
- Better performance and standards compliance

This module is maintained for compatibility only and will be removed in a future version.

## Migration

```julia
# Old (deprecated):
using DOPBrowser.CSSParserModule
styles = parse_inline_style("width: 100px; background-color: red;")

# New (recommended):
using DOPBrowser.RustParser
styles = RustParser.parse_inline_style("width: 100px; background-color: red;")
```
"""
module CSSParserModule

@warn "CSSParserModule is deprecated. Please use RustParser instead. This module will be removed in a future version." maxlog=1

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
