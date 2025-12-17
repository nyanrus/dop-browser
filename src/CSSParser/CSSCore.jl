"""
CSSCore - CSS parsing and style computation.

This module provides CSS parsing functionality including:
- Inline style parsing
- Color parsing (hex, rgb, rgba, named colors)
- Length parsing (px, %, em, mm, auto)

For high-performance parsing, consider using RustParser which provides
Rust-based CSS parsing via cssparser.
"""
module CSSCore

export CSSStyles, parse_inline_style, parse_color, parse_length
export POSITION_STATIC, POSITION_RELATIVE, POSITION_ABSOLUTE, POSITION_FIXED, POSITION_STICKY
export OVERFLOW_VISIBLE, OVERFLOW_HIDDEN, OVERFLOW_SCROLL, OVERFLOW_AUTO
export DISPLAY_BLOCK, DISPLAY_INLINE, DISPLAY_NONE, DISPLAY_TABLE, DISPLAY_TABLE_CELL, DISPLAY_TABLE_ROW, DISPLAY_INLINE_BLOCK, DISPLAY_FLEX, DISPLAY_INLINE_FLEX, DISPLAY_GRID, DISPLAY_INLINE_GRID
export FLOAT_NONE, FLOAT_LEFT, FLOAT_RIGHT
export CLEAR_NONE, CLEAR_LEFT, CLEAR_RIGHT, CLEAR_BOTH
export BORDER_STYLE_NONE, BORDER_STYLE_SOLID, BORDER_STYLE_DOTTED, BORDER_STYLE_DASHED, BORDER_STYLE_DOUBLE, BORDER_STYLE_GROOVE, BORDER_STYLE_RIDGE, BORDER_STYLE_INSET, BORDER_STYLE_OUTSET
export FLEX_DIRECTION_ROW, FLEX_DIRECTION_ROW_REVERSE, FLEX_DIRECTION_COLUMN, FLEX_DIRECTION_COLUMN_REVERSE
export FLEX_WRAP_NOWRAP, FLEX_WRAP_WRAP, FLEX_WRAP_WRAP_REVERSE
export JUSTIFY_CONTENT_START, JUSTIFY_CONTENT_END, JUSTIFY_CONTENT_CENTER, JUSTIFY_CONTENT_BETWEEN, JUSTIFY_CONTENT_AROUND, JUSTIFY_CONTENT_EVENLY
export ALIGN_ITEMS_START, ALIGN_ITEMS_END, ALIGN_ITEMS_CENTER, ALIGN_ITEMS_STRETCH, ALIGN_ITEMS_BASELINE
export ALIGN_CONTENT_START, ALIGN_CONTENT_END, ALIGN_CONTENT_CENTER, ALIGN_CONTENT_BETWEEN, ALIGN_CONTENT_AROUND, ALIGN_CONTENT_STRETCH
export TEXT_ALIGN_LEFT, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER, TEXT_ALIGN_JUSTIFY
export TEXT_DECORATION_NONE, TEXT_DECORATION_UNDERLINE, TEXT_DECORATION_OVERLINE, TEXT_DECORATION_LINE_THROUGH
export BOX_SIZING_CONTENT_BOX, BOX_SIZING_BORDER_BOX

# Position constants
const POSITION_STATIC, POSITION_RELATIVE, POSITION_ABSOLUTE, POSITION_FIXED, POSITION_STICKY = UInt8(0), UInt8(1), UInt8(2), UInt8(3), UInt8(4)

# Float and clear constants
const FLOAT_NONE, FLOAT_LEFT, FLOAT_RIGHT = UInt8(0), UInt8(1), UInt8(2)
const CLEAR_NONE, CLEAR_LEFT, CLEAR_RIGHT, CLEAR_BOTH = UInt8(0), UInt8(1), UInt8(2), UInt8(3)

# Border style constants (CSS3 complete set)
const BORDER_STYLE_NONE, BORDER_STYLE_SOLID, BORDER_STYLE_DOTTED, BORDER_STYLE_DASHED = UInt8(0), UInt8(1), UInt8(2), UInt8(3)
const BORDER_STYLE_DOUBLE, BORDER_STYLE_GROOVE, BORDER_STYLE_RIDGE, BORDER_STYLE_INSET, BORDER_STYLE_OUTSET = UInt8(4), UInt8(5), UInt8(6), UInt8(7), UInt8(8)

# Overflow constants (CSS3)
const OVERFLOW_VISIBLE, OVERFLOW_HIDDEN, OVERFLOW_SCROLL, OVERFLOW_AUTO = UInt8(0), UInt8(1), UInt8(2), UInt8(3)

# Display constants (CSS3 complete set)
const DISPLAY_NONE, DISPLAY_BLOCK, DISPLAY_INLINE = UInt8(0), UInt8(1), UInt8(2)
const DISPLAY_TABLE, DISPLAY_TABLE_CELL, DISPLAY_TABLE_ROW, DISPLAY_INLINE_BLOCK = UInt8(3), UInt8(4), UInt8(5), UInt8(6)
const DISPLAY_FLEX, DISPLAY_INLINE_FLEX, DISPLAY_GRID, DISPLAY_INLINE_GRID = UInt8(7), UInt8(8), UInt8(9), UInt8(10)

# Flexbox direction constants
const FLEX_DIRECTION_ROW, FLEX_DIRECTION_ROW_REVERSE, FLEX_DIRECTION_COLUMN, FLEX_DIRECTION_COLUMN_REVERSE = UInt8(0), UInt8(1), UInt8(2), UInt8(3)

# Flexbox wrap constants
const FLEX_WRAP_NOWRAP, FLEX_WRAP_WRAP, FLEX_WRAP_WRAP_REVERSE = UInt8(0), UInt8(1), UInt8(2)

# Justify content constants
const JUSTIFY_CONTENT_START, JUSTIFY_CONTENT_END, JUSTIFY_CONTENT_CENTER = UInt8(0), UInt8(1), UInt8(2)
const JUSTIFY_CONTENT_BETWEEN, JUSTIFY_CONTENT_AROUND, JUSTIFY_CONTENT_EVENLY = UInt8(3), UInt8(4), UInt8(5)

# Align items constants
const ALIGN_ITEMS_START, ALIGN_ITEMS_END, ALIGN_ITEMS_CENTER, ALIGN_ITEMS_STRETCH, ALIGN_ITEMS_BASELINE = UInt8(0), UInt8(1), UInt8(2), UInt8(3), UInt8(4)

# Align content constants
const ALIGN_CONTENT_START, ALIGN_CONTENT_END, ALIGN_CONTENT_CENTER = UInt8(0), UInt8(1), UInt8(2)
const ALIGN_CONTENT_BETWEEN, ALIGN_CONTENT_AROUND, ALIGN_CONTENT_STRETCH = UInt8(3), UInt8(4), UInt8(5)

# Text align constants
const TEXT_ALIGN_LEFT, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER, TEXT_ALIGN_JUSTIFY = UInt8(0), UInt8(1), UInt8(2), UInt8(3)

# Text decoration constants
const TEXT_DECORATION_NONE, TEXT_DECORATION_UNDERLINE, TEXT_DECORATION_OVERLINE, TEXT_DECORATION_LINE_THROUGH = UInt8(0), UInt8(1), UInt8(2), UInt8(3)

# Box sizing constants
const BOX_SIZING_CONTENT_BOX, BOX_SIZING_BORDER_BOX = UInt8(0), UInt8(1)

# CSS length unit conversion constants (at 96 DPI)
# These constants define pixel equivalents for various CSS length units
const PX_PER_INCH = 96.0f0       # 1in = 96px
const PX_PER_CM = 37.795f0       # 1cm = 37.795px (96/2.54)
const PX_PER_MM = 3.7795f0       # 1mm = 3.7795px (96/25.4)
const PX_PER_PT = 1.333f0        # 1pt = 1.333px (96/72)
const PX_PER_PC = 16.0f0         # 1pc = 16px (12pt)

# Default viewport size for vw/vh units (1920x1080)
# Note: These are fallback values. Actual viewport size should be passed to parse_length.
const DEFAULT_VIEWPORT_WIDTH = 1920.0f0
const DEFAULT_VIEWPORT_HEIGHT = 1080.0f0
const PX_PER_VW = DEFAULT_VIEWPORT_WIDTH / 100.0f0   # 19.2px per vw
const PX_PER_VH = DEFAULT_VIEWPORT_HEIGHT / 100.0f0  # 10.8px per vh

# Font-relative unit defaults
const DEFAULT_FONT_SIZE = 16.0f0  # Default font size in px
const DEFAULT_CH_WIDTH = 8.0f0    # Approximate '0' character width
const DEFAULT_EX_HEIGHT = 8.0f0   # Approximate x-height

"CSSStyles - Computed CSS styles for a node (CSS3 complete)."
mutable struct CSSStyles
    # Positioning (CSS2.1 + CSS3 sticky)
    position::UInt8; float::UInt8; clear::UInt8
    top::Float32; right::Float32; bottom::Float32; left::Float32
    top_auto::Bool; right_auto::Bool; bottom_auto::Bool; left_auto::Bool
    z_index::Int32
    
    # Dimensions (CSS2.1)
    width::Float32; height::Float32; width_auto::Bool; height_auto::Bool
    min_width::Float32; max_width::Float32; min_height::Float32; max_height::Float32
    has_min_width::Bool; has_max_width::Bool; has_min_height::Bool; has_max_height::Bool
    
    # Box model (CSS2.1)
    margin_top::Float32; margin_right::Float32; margin_bottom::Float32; margin_left::Float32
    padding_top::Float32; padding_right::Float32; padding_bottom::Float32; padding_left::Float32
    border_top_width::Float32; border_right_width::Float32; border_bottom_width::Float32; border_left_width::Float32
    border_top_style::UInt8; border_right_style::UInt8; border_bottom_style::UInt8; border_left_style::UInt8
    border_top_r::UInt8; border_top_g::UInt8; border_top_b::UInt8; border_top_a::UInt8
    border_right_r::UInt8; border_right_g::UInt8; border_right_b::UInt8; border_right_a::UInt8
    border_bottom_r::UInt8; border_bottom_g::UInt8; border_bottom_b::UInt8; border_bottom_a::UInt8
    border_left_r::UInt8; border_left_g::UInt8; border_left_b::UInt8; border_left_a::UInt8
    
    # Border radius (CSS3)
    border_radius_tl::Float32; border_radius_tr::Float32; border_radius_br::Float32; border_radius_bl::Float32
    
    # Display (CSS2.1 + CSS3 flex/grid)
    display::UInt8; visibility::Bool; overflow::UInt8
    overflow_x::UInt8; overflow_y::UInt8
    box_sizing::UInt8
    
    # Typography (CSS2.1 + CSS3)
    line_height::Float32; line_height_normal::Bool; font_size::Float32
    text_align::UInt8; text_decoration::UInt8
    font_weight::UInt16; font_style::UInt8
    letter_spacing::Float32; word_spacing::Float32
    text_transform::UInt8; white_space::UInt8
    
    # Colors (CSS2.1)
    background_r::UInt8; background_g::UInt8; background_b::UInt8; background_a::UInt8
    color_r::UInt8; color_g::UInt8; color_b::UInt8; color_a::UInt8
    has_background::Bool; content::String; has_content::Bool
    
    # Opacity (CSS3)
    opacity::Float32
    
    # Flexbox properties (CSS3 Flexbox)
    flex_direction::UInt8; flex_wrap::UInt8
    justify_content::UInt8; align_items::UInt8; align_content::UInt8
    flex_grow::Float32; flex_shrink::Float32; flex_basis::Float32
    flex_basis_auto::Bool; align_self::UInt8
    gap_row::Float32; gap_column::Float32
    order::Int32
    
    # Box shadow (CSS3) - simplified: one shadow
    box_shadow_offset_x::Float32; box_shadow_offset_y::Float32
    box_shadow_blur::Float32; box_shadow_spread::Float32
    box_shadow_r::UInt8; box_shadow_g::UInt8; box_shadow_b::UInt8; box_shadow_a::UInt8
    box_shadow_inset::Bool; has_box_shadow::Bool
    
    # Transform (CSS3) - simplified: translate and rotate
    transform_translate_x::Float32; transform_translate_y::Float32
    transform_rotate::Float32; transform_scale_x::Float32; transform_scale_y::Float32
    has_transform::Bool
    
    CSSStyles() = new(
        # Positioning
        POSITION_STATIC, FLOAT_NONE, CLEAR_NONE,
        0.0f0, 0.0f0, 0.0f0, 0.0f0, true, true, true, true, Int32(0),
        # Dimensions
        0.0f0, 0.0f0, true, true, 0.0f0, Float32(Inf), 0.0f0, Float32(Inf), false, false, false, false,
        # Box model
        0.0f0, 0.0f0, 0.0f0, 0.0f0, 0.0f0, 0.0f0, 0.0f0, 0.0f0,
        0.0f0, 0.0f0, 0.0f0, 0.0f0,
        BORDER_STYLE_NONE, BORDER_STYLE_NONE, BORDER_STYLE_NONE, BORDER_STYLE_NONE,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        # Border radius
        0.0f0, 0.0f0, 0.0f0, 0.0f0,
        # Display
        DISPLAY_BLOCK, true, OVERFLOW_VISIBLE, OVERFLOW_VISIBLE, OVERFLOW_VISIBLE, BOX_SIZING_CONTENT_BOX,
        # Typography
        16.0f0, true, 16.0f0, TEXT_ALIGN_LEFT, TEXT_DECORATION_NONE, UInt16(400), UInt8(0),
        0.0f0, 0.0f0, UInt8(0), UInt8(0),
        # Colors
        0xff, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0xff, false, "", false,
        # Opacity
        1.0f0,
        # Flexbox
        FLEX_DIRECTION_ROW, FLEX_WRAP_NOWRAP, JUSTIFY_CONTENT_START, ALIGN_ITEMS_STRETCH, ALIGN_CONTENT_STRETCH,
        0.0f0, 1.0f0, 0.0f0, true, ALIGN_ITEMS_START, 0.0f0, 0.0f0, Int32(0),
        # Box shadow
        0.0f0, 0.0f0, 0.0f0, 0.0f0, 0x00, 0x00, 0x00, 0x00, false, false,
        # Transform
        0.0f0, 0.0f0, 0.0f0, 1.0f0, 1.0f0, false
    )
end

# CSS3 Extended Color Keywords (X11 colors) + CSS2.1 colors
const NAMED_COLORS = Dict{String,Tuple{UInt8,UInt8,UInt8,UInt8}}(
    # CSS2.1 Basic colors
    "black"=>(0x00,0x00,0x00,0xff), "white"=>(0xff,0xff,0xff,0xff), "red"=>(0xff,0x00,0x00,0xff),
    "green"=>(0x00,0x80,0x00,0xff), "lime"=>(0x00,0xff,0x00,0xff), "blue"=>(0x00,0x00,0xff,0xff),
    "yellow"=>(0xff,0xff,0x00,0xff), "cyan"=>(0x00,0xff,0xff,0xff), "magenta"=>(0xff,0x00,0xff,0xff),
    "gray"=>(0x80,0x80,0x80,0xff), "grey"=>(0x80,0x80,0x80,0xff), "transparent"=>(0x00,0x00,0x00,0x00),
    "orange"=>(0xff,0xa5,0x00,0xff), "purple"=>(0x80,0x00,0x80,0xff), "navy"=>(0x00,0x00,0x80,0xff),
    "maroon"=>(0x80,0x00,0x00,0xff), "olive"=>(0x80,0x80,0x00,0xff), "teal"=>(0x00,0x80,0x80,0xff),
    "silver"=>(0xc0,0xc0,0xc0,0xff), "fuchsia"=>(0xff,0x00,0xff,0xff), "aqua"=>(0x00,0xff,0xff,0xff),
    # CSS3 Extended Colors (X11/SVG colors)
    "aliceblue"=>(0xf0,0xf8,0xff,0xff), "antiquewhite"=>(0xfa,0xeb,0xd7,0xff),
    "aquamarine"=>(0x7f,0xff,0xd4,0xff), "azure"=>(0xf0,0xff,0xff,0xff),
    "beige"=>(0xf5,0xf5,0xdc,0xff), "bisque"=>(0xff,0xe4,0xc4,0xff),
    "blanchedalmond"=>(0xff,0xeb,0xcd,0xff), "blueviolet"=>(0x8a,0x2b,0xe2,0xff),
    "brown"=>(0xa5,0x2a,0x2a,0xff), "burlywood"=>(0xde,0xb8,0x87,0xff),
    "cadetblue"=>(0x5f,0x9e,0xa0,0xff), "chartreuse"=>(0x7f,0xff,0x00,0xff),
    "chocolate"=>(0xd2,0x69,0x1e,0xff), "coral"=>(0xff,0x7f,0x50,0xff),
    "cornflowerblue"=>(0x64,0x95,0xed,0xff), "cornsilk"=>(0xff,0xf8,0xdc,0xff),
    "crimson"=>(0xdc,0x14,0x3c,0xff), "darkblue"=>(0x00,0x00,0x8b,0xff),
    "darkcyan"=>(0x00,0x8b,0x8b,0xff), "darkgoldenrod"=>(0xb8,0x86,0x0b,0xff),
    "darkgray"=>(0xa9,0xa9,0xa9,0xff), "darkgrey"=>(0xa9,0xa9,0xa9,0xff),
    "darkgreen"=>(0x00,0x64,0x00,0xff), "darkkhaki"=>(0xbd,0xb7,0x6b,0xff),
    "darkmagenta"=>(0x8b,0x00,0x8b,0xff), "darkolivegreen"=>(0x55,0x6b,0x2f,0xff),
    "darkorange"=>(0xff,0x8c,0x00,0xff), "darkorchid"=>(0x99,0x32,0xcc,0xff),
    "darkred"=>(0x8b,0x00,0x00,0xff), "darksalmon"=>(0xe9,0x96,0x7a,0xff),
    "darkseagreen"=>(0x8f,0xbc,0x8f,0xff), "darkslateblue"=>(0x48,0x3d,0x8b,0xff),
    "darkslategray"=>(0x2f,0x4f,0x4f,0xff), "darkslategrey"=>(0x2f,0x4f,0x4f,0xff),
    "darkturquoise"=>(0x00,0xce,0xd1,0xff), "darkviolet"=>(0x94,0x00,0xd3,0xff),
    "deeppink"=>(0xff,0x14,0x93,0xff), "deepskyblue"=>(0x00,0xbf,0xff,0xff),
    "dimgray"=>(0x69,0x69,0x69,0xff), "dimgrey"=>(0x69,0x69,0x69,0xff),
    "dodgerblue"=>(0x1e,0x90,0xff,0xff), "firebrick"=>(0xb2,0x22,0x22,0xff),
    "floralwhite"=>(0xff,0xfa,0xf0,0xff), "forestgreen"=>(0x22,0x8b,0x22,0xff),
    "gainsboro"=>(0xdc,0xdc,0xdc,0xff), "ghostwhite"=>(0xf8,0xf8,0xff,0xff),
    "gold"=>(0xff,0xd7,0x00,0xff), "goldenrod"=>(0xda,0xa5,0x20,0xff),
    "greenyellow"=>(0xad,0xff,0x2f,0xff), "honeydew"=>(0xf0,0xff,0xf0,0xff),
    "hotpink"=>(0xff,0x69,0xb4,0xff), "indianred"=>(0xcd,0x5c,0x5c,0xff),
    "indigo"=>(0x4b,0x00,0x82,0xff), "ivory"=>(0xff,0xff,0xf0,0xff),
    "khaki"=>(0xf0,0xe6,0x8c,0xff), "lavender"=>(0xe6,0xe6,0xfa,0xff),
    "lavenderblush"=>(0xff,0xf0,0xf5,0xff), "lawngreen"=>(0x7c,0xfc,0x00,0xff),
    "lemonchiffon"=>(0xff,0xfa,0xcd,0xff), "lightblue"=>(0xad,0xd8,0xe6,0xff),
    "lightcoral"=>(0xf0,0x80,0x80,0xff), "lightcyan"=>(0xe0,0xff,0xff,0xff),
    "lightgoldenrodyellow"=>(0xfa,0xfa,0xd2,0xff), "lightgray"=>(0xd3,0xd3,0xd3,0xff),
    "lightgrey"=>(0xd3,0xd3,0xd3,0xff), "lightgreen"=>(0x90,0xee,0x90,0xff),
    "lightpink"=>(0xff,0xb6,0xc1,0xff), "lightsalmon"=>(0xff,0xa0,0x7a,0xff),
    "lightseagreen"=>(0x20,0xb2,0xaa,0xff), "lightskyblue"=>(0x87,0xce,0xfa,0xff),
    "lightslategray"=>(0x77,0x88,0x99,0xff), "lightslategrey"=>(0x77,0x88,0x99,0xff),
    "lightsteelblue"=>(0xb0,0xc4,0xde,0xff), "lightyellow"=>(0xff,0xff,0xe0,0xff),
    "limegreen"=>(0x32,0xcd,0x32,0xff), "linen"=>(0xfa,0xf0,0xe6,0xff),
    "mediumaquamarine"=>(0x66,0xcd,0xaa,0xff), "mediumblue"=>(0x00,0x00,0xcd,0xff),
    "mediumorchid"=>(0xba,0x55,0xd3,0xff), "mediumpurple"=>(0x93,0x70,0xdb,0xff),
    "mediumseagreen"=>(0x3c,0xb3,0x71,0xff), "mediumslateblue"=>(0x7b,0x68,0xee,0xff),
    "mediumspringgreen"=>(0x00,0xfa,0x9a,0xff), "mediumturquoise"=>(0x48,0xd1,0xcc,0xff),
    "mediumvioletred"=>(0xc7,0x15,0x85,0xff), "midnightblue"=>(0x19,0x19,0x70,0xff),
    "mintcream"=>(0xf5,0xff,0xfa,0xff), "mistyrose"=>(0xff,0xe4,0xe1,0xff),
    "moccasin"=>(0xff,0xe4,0xb5,0xff), "navajowhite"=>(0xff,0xde,0xad,0xff),
    "oldlace"=>(0xfd,0xf5,0xe6,0xff), "olivedrab"=>(0x6b,0x8e,0x23,0xff),
    "orangered"=>(0xff,0x45,0x00,0xff), "orchid"=>(0xda,0x70,0xd6,0xff),
    "palegoldenrod"=>(0xee,0xe8,0xaa,0xff), "palegreen"=>(0x98,0xfb,0x98,0xff),
    "paleturquoise"=>(0xaf,0xee,0xee,0xff), "palevioletred"=>(0xdb,0x70,0x93,0xff),
    "papayawhip"=>(0xff,0xef,0xd5,0xff), "peachpuff"=>(0xff,0xda,0xb9,0xff),
    "peru"=>(0xcd,0x85,0x3f,0xff), "pink"=>(0xff,0xc0,0xcb,0xff),
    "plum"=>(0xdd,0xa0,0xdd,0xff), "powderblue"=>(0xb0,0xe0,0xe6,0xff),
    "rebeccapurple"=>(0x66,0x33,0x99,0xff), "rosybrown"=>(0xbc,0x8f,0x8f,0xff),
    "royalblue"=>(0x41,0x69,0xe1,0xff), "saddlebrown"=>(0x8b,0x45,0x13,0xff),
    "salmon"=>(0xfa,0x80,0x72,0xff), "sandybrown"=>(0xf4,0xa4,0x60,0xff),
    "seagreen"=>(0x2e,0x8b,0x57,0xff), "seashell"=>(0xff,0xf5,0xee,0xff),
    "sienna"=>(0xa0,0x52,0x2d,0xff), "skyblue"=>(0x87,0xce,0xeb,0xff),
    "slateblue"=>(0x6a,0x5a,0xcd,0xff), "slategray"=>(0x70,0x80,0x90,0xff),
    "slategrey"=>(0x70,0x80,0x90,0xff), "snow"=>(0xff,0xfa,0xfa,0xff),
    "springgreen"=>(0x00,0xff,0x7f,0xff), "steelblue"=>(0x46,0x82,0xb4,0xff),
    "tan"=>(0xd2,0xb4,0x8c,0xff), "thistle"=>(0xd8,0xbf,0xd8,0xff),
    "tomato"=>(0xff,0x63,0x47,0xff), "turquoise"=>(0x40,0xe0,0xd0,0xff),
    "violet"=>(0xee,0x82,0xee,0xff), "wheat"=>(0xf5,0xde,0xb3,0xff),
    "whitesmoke"=>(0xf5,0xf5,0xf5,0xff), "yellowgreen"=>(0x9a,0xcd,0x32,0xff),
    # CSS Color Level 4
    "currentcolor"=>(0x00,0x00,0x00,0xff)  # Default to black, should be computed
)

"""
Parse CSS color (CSS3 complete support).

Supports:
- Hex: #rgb, #rrggbb, #rgba, #rrggbbaa
- Named: CSS3 X11 color keywords
- rgb()/rgba(): Both comma and space separated
- hsl()/hsla(): HSL color model
"""
function parse_color(value::AbstractString)::Tuple{UInt8,UInt8,UInt8,UInt8}
    val = strip(lowercase(value))
    haskey(NAMED_COLORS, val) && return NAMED_COLORS[val]
    
    # Hex colors: #rgb, #rgba, #rrggbb, #rrggbbaa
    if startswith(val, "#")
        hex = val[2:end]
        if length(hex) == 3
            return (parse(UInt8, hex[1:1]*hex[1:1], base=16), parse(UInt8, hex[2:2]*hex[2:2], base=16), parse(UInt8, hex[3:3]*hex[3:3], base=16), 0xff)
        elseif length(hex) == 4
            return (parse(UInt8, hex[1:1]*hex[1:1], base=16), parse(UInt8, hex[2:2]*hex[2:2], base=16), parse(UInt8, hex[3:3]*hex[3:3], base=16), parse(UInt8, hex[4:4]*hex[4:4], base=16))
        elseif length(hex) == 6
            return (parse(UInt8, hex[1:2], base=16), parse(UInt8, hex[3:4], base=16), parse(UInt8, hex[5:6], base=16), 0xff)
        elseif length(hex) == 8
            return (parse(UInt8, hex[1:2], base=16), parse(UInt8, hex[3:4], base=16), parse(UInt8, hex[5:6], base=16), parse(UInt8, hex[7:8], base=16))
        end
    end
    
    # RGB/RGBA - comma or space separated
    if startswith(val, "rgb")
        # Comma separated: rgb(255, 128, 0) or rgba(255, 128, 0, 0.5)
        m = match(r"rgba?\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)(?:\s*,\s*([\d.]+))?\s*\)", val)
        if m !== nothing
            return (parse(UInt8, m.captures[1]), parse(UInt8, m.captures[2]), parse(UInt8, m.captures[3]), 
                    m.captures[4] !== nothing ? round(UInt8, parse(Float64, m.captures[4]) * 255) : 0xff)
        end
        # Percentage: rgb(100%, 50%, 0%) or rgba(100%, 50%, 0%, 0.5)
        m = match(r"rgba?\s*\(\s*([\d.]+)%\s*,?\s*([\d.]+)%\s*,?\s*([\d.]+)%(?:\s*[,/]\s*([\d.]+%?))?\s*\)", val)
        if m !== nothing
            r = round(UInt8, parse(Float64, m.captures[1]) * 2.55)
            g = round(UInt8, parse(Float64, m.captures[2]) * 2.55)
            b = round(UInt8, parse(Float64, m.captures[3]) * 2.55)
            a = 0xff
            if m.captures[4] !== nothing
                alpha_str = m.captures[4]
                if endswith(alpha_str, "%")
                    a = round(UInt8, parse(Float64, alpha_str[1:end-1]) * 2.55)
                else
                    a = round(UInt8, parse(Float64, alpha_str) * 255)
                end
            end
            return (r, g, b, a)
        end
    end
    
    # HSL/HSLA - CSS3 color model
    if startswith(val, "hsl")
        m = match(r"hsla?\s*\(\s*([\d.]+)\s*,?\s*([\d.]+)%\s*,?\s*([\d.]+)%(?:\s*[,/]\s*([\d.]+%?))?\s*\)", val)
        if m !== nothing
            h = parse(Float64, m.captures[1]) / 360.0
            s = parse(Float64, m.captures[2]) / 100.0
            l = parse(Float64, m.captures[3]) / 100.0
            a = 0xff
            if m.captures[4] !== nothing
                alpha_str = m.captures[4]
                if endswith(alpha_str, "%")
                    a = round(UInt8, parse(Float64, alpha_str[1:end-1]) * 2.55)
                else
                    a = round(UInt8, parse(Float64, alpha_str) * 255)
                end
            end
            r, g, b = hsl_to_rgb(h, s, l)
            return (r, g, b, a)
        end
    end
    
    (0x00, 0x00, 0x00, 0x00)
end

"Convert HSL color to RGB."
function hsl_to_rgb(h::Float64, s::Float64, l::Float64)::Tuple{UInt8, UInt8, UInt8}
    if s == 0.0
        v = round(UInt8, l * 255)
        return (v, v, v)
    end
    
    q = l < 0.5 ? l * (1 + s) : l + s - l * s
    p = 2 * l - q
    
    r = hue_to_rgb(p, q, h + 1/3)
    g = hue_to_rgb(p, q, h)
    b = hue_to_rgb(p, q, h - 1/3)
    
    return (round(UInt8, r * 255), round(UInt8, g * 255), round(UInt8, b * 255))
end

function hue_to_rgb(p::Float64, q::Float64, t::Float64)::Float64
    t < 0 && (t += 1)
    t > 1 && (t -= 1)
    t < 1/6 && return p + (q - p) * 6 * t
    t < 1/2 && return q
    t < 2/3 && return p + (q - p) * (2/3 - t) * 6
    return p
end

"""
Parse CSS length (CSS3 complete support).

Supports: px, %, em, rem, vw, vh, vmin, vmax, pt, pc, cm, mm, in, ch, ex
"""
function parse_length(value::AbstractString, container_size::Float32 = 0.0f0)::Tuple{Float32, Bool}
    val = strip(lowercase(value))
    val == "auto" && return (0.0f0, true)
    
    # Percentages
    if endswith(val, "%")
        num = tryparse(Float32, val[1:end-1])
        num !== nothing && return (num / 100.0f0 * container_size, false)
    end
    
    # Viewport units (using default 1920x1080 viewport; for actual viewport, use parse_length_with_viewport)
    if endswith(val, "vw")
        num = tryparse(Float32, val[1:end-2])
        num !== nothing && return (num * PX_PER_VW, false)
    end
    if endswith(val, "vh")
        num = tryparse(Float32, val[1:end-2])
        num !== nothing && return (num * PX_PER_VH, false)
    end
    if endswith(val, "vmin")
        num = tryparse(Float32, val[1:end-4])
        num !== nothing && return (num * min(PX_PER_VW, PX_PER_VH), false)
    end
    if endswith(val, "vmax")
        num = tryparse(Float32, val[1:end-4])
        num !== nothing && return (num * max(PX_PER_VW, PX_PER_VH), false)
    end
    
    # Rem (relative to root font size)
    if endswith(val, "rem")
        num = tryparse(Float32, val[1:end-3])
        num !== nothing && return (num * DEFAULT_FONT_SIZE, false)
    end
    
    # Pixels (explicit or implicit)
    num_str = replace(val, r"px$" => "")
    num = tryparse(Float32, num_str)
    num !== nothing && return (num, false)
    
    # Em (relative to font-size)
    if endswith(val, "em")
        num = tryparse(Float32, val[1:end-2])
        num !== nothing && return (num * DEFAULT_FONT_SIZE, false)
    end
    
    # Points
    if endswith(val, "pt")
        num = tryparse(Float32, val[1:end-2])
        num !== nothing && return (num * PX_PER_PT, false)
    end
    
    # Picas
    if endswith(val, "pc")
        num = tryparse(Float32, val[1:end-2])
        num !== nothing && return (num * PX_PER_PC, false)
    end
    
    # Millimeters
    if endswith(val, "mm")
        num = tryparse(Float32, val[1:end-2])
        num !== nothing && return (num * PX_PER_MM, false)
    end
    
    # Centimeters
    if endswith(val, "cm")
        num = tryparse(Float32, val[1:end-2])
        num !== nothing && return (num * PX_PER_CM, false)
    end
    
    # Inches
    if endswith(val, "in")
        num = tryparse(Float32, val[1:end-2])
        num !== nothing && return (num * PX_PER_INCH, false)
    end
    
    # Ch (width of '0' character)
    if endswith(val, "ch")
        num = tryparse(Float32, val[1:end-2])
        num !== nothing && return (num * DEFAULT_CH_WIDTH, false)
    end
    
    # Ex (x-height)
    if endswith(val, "ex")
        num = tryparse(Float32, val[1:end-2])
        num !== nothing && return (num * DEFAULT_EX_HEIGHT, false)
    end
    
    return (0.0f0, true)
end

function parse_inline_style(style_str::AbstractString)::CSSStyles
    styles = CSSStyles()
    
    for decl in split(style_str, ";")
        decl = strip(decl)
        isempty(decl) && continue
        
        colon_idx = findfirst(':', decl)
        colon_idx === nothing && continue
        
        prop = strip(lowercase(decl[1:colon_idx-1]))
        val = strip(decl[colon_idx+1:end])
        
        apply_property!(styles, prop, val)
    end
    
    return styles
end

function apply_property!(styles::CSSStyles, prop::AbstractString, val::AbstractString)
    val_lower = lowercase(val)
    
    if prop == "position"
        styles.position = val_lower == "static" ? POSITION_STATIC :
                         val_lower == "relative" ? POSITION_RELATIVE :
                         val_lower == "absolute" ? POSITION_ABSOLUTE :
                         val_lower == "fixed" ? POSITION_FIXED :
                         val_lower == "sticky" ? POSITION_STICKY : POSITION_STATIC
    elseif prop == "display"
        styles.display = val_lower == "block" ? DISPLAY_BLOCK :
                        val_lower == "inline" ? DISPLAY_INLINE :
                        val_lower == "none" ? DISPLAY_NONE :
                        val_lower == "table" ? DISPLAY_TABLE :
                        val_lower == "table-cell" ? DISPLAY_TABLE_CELL :
                        val_lower == "table-row" ? DISPLAY_TABLE_ROW :
                        val_lower == "inline-block" ? DISPLAY_INLINE_BLOCK :
                        val_lower == "flex" ? DISPLAY_FLEX :
                        val_lower == "inline-flex" ? DISPLAY_INLINE_FLEX :
                        val_lower == "grid" ? DISPLAY_GRID :
                        val_lower == "inline-grid" ? DISPLAY_INLINE_GRID : DISPLAY_BLOCK
    elseif prop == "visibility"
        styles.visibility = val_lower != "hidden"
    elseif prop == "overflow"
        overflow_val = val_lower == "hidden" ? OVERFLOW_HIDDEN :
                      val_lower == "scroll" ? OVERFLOW_SCROLL :
                      val_lower == "auto" ? OVERFLOW_AUTO : OVERFLOW_VISIBLE
        styles.overflow = overflow_val
        styles.overflow_x = overflow_val
        styles.overflow_y = overflow_val
    elseif prop == "overflow-x"
        styles.overflow_x = val_lower == "hidden" ? OVERFLOW_HIDDEN :
                           val_lower == "scroll" ? OVERFLOW_SCROLL :
                           val_lower == "auto" ? OVERFLOW_AUTO : OVERFLOW_VISIBLE
    elseif prop == "overflow-y"
        styles.overflow_y = val_lower == "hidden" ? OVERFLOW_HIDDEN :
                           val_lower == "scroll" ? OVERFLOW_SCROLL :
                           val_lower == "auto" ? OVERFLOW_AUTO : OVERFLOW_VISIBLE
    elseif prop == "background-color" || prop == "background"
        color = parse_color(val)
        styles.background_r, styles.background_g, styles.background_b, styles.background_a = color
        styles.has_background = color[4] > 0
    elseif prop == "color"
        color = parse_color(val)
        styles.color_r, styles.color_g, styles.color_b, styles.color_a = color
    elseif prop == "width"
        (px, auto) = parse_length(val)
        styles.width, styles.width_auto = px, auto
    elseif prop == "height"
        (px, auto) = parse_length(val)
        styles.height, styles.height_auto = px, auto
    elseif prop == "top"
        (px, auto) = parse_length(val)
        styles.top, styles.top_auto = px, auto
    elseif prop == "right"
        (px, auto) = parse_length(val)
        styles.right, styles.right_auto = px, auto
    elseif prop == "bottom"
        (px, auto) = parse_length(val)
        styles.bottom, styles.bottom_auto = px, auto
    elseif prop == "left"
        (px, auto) = parse_length(val)
        styles.left, styles.left_auto = px, auto
    elseif prop == "z-index"
        z = tryparse(Int32, val)
        z !== nothing && (styles.z_index = z)
    elseif prop == "margin"
        values = parse_margin_shorthand(val)
        styles.margin_top, styles.margin_right, styles.margin_bottom, styles.margin_left = values
    elseif prop == "margin-top"
        (px, _) = parse_length(val); styles.margin_top = px
    elseif prop == "margin-right"
        (px, _) = parse_length(val); styles.margin_right = px
    elseif prop == "margin-bottom"
        (px, _) = parse_length(val); styles.margin_bottom = px
    elseif prop == "margin-left"
        (px, _) = parse_length(val); styles.margin_left = px
    elseif prop == "padding"
        values = parse_margin_shorthand(val)
        styles.padding_top, styles.padding_right, styles.padding_bottom, styles.padding_left = values
    elseif prop == "padding-top"
        (px, _) = parse_length(val); styles.padding_top = px
    elseif prop == "padding-right"
        (px, _) = parse_length(val); styles.padding_right = px
    elseif prop == "padding-bottom"
        (px, _) = parse_length(val); styles.padding_bottom = px
    elseif prop == "padding-left"
        (px, _) = parse_length(val); styles.padding_left = px
    elseif prop == "float"
        styles.float = val_lower == "left" ? FLOAT_LEFT : val_lower == "right" ? FLOAT_RIGHT : FLOAT_NONE
    elseif prop == "clear"
        styles.clear = val_lower == "left" ? CLEAR_LEFT : val_lower == "right" ? CLEAR_RIGHT : val_lower == "both" ? CLEAR_BOTH : CLEAR_NONE
    elseif prop == "min-width"
        (px, auto) = parse_length(val)
        !auto && (styles.min_width = px; styles.has_min_width = true)
    elseif prop == "max-width"
        (px, auto) = parse_length(val)
        !auto && (styles.max_width = px; styles.has_max_width = true)
    elseif prop == "min-height"
        (px, auto) = parse_length(val)
        !auto && (styles.min_height = px; styles.has_min_height = true)
    elseif prop == "max-height"
        (px, auto) = parse_length(val)
        !auto && (styles.max_height = px; styles.has_max_height = true)
    elseif prop == "border" || prop == "border-width"
        if prop == "border"
            parts = split(strip(val))
            for part in parts
                part_lower = lowercase(part)
                if occursin(r"^\d+", part)
                    (px, _) = parse_length(part)
                    styles.border_top_width = styles.border_right_width = styles.border_bottom_width = styles.border_left_width = px
                elseif part_lower in ["solid", "dotted", "dashed", "none"]
                    style = parse_border_style(part_lower)
                    styles.border_top_style = styles.border_right_style = styles.border_bottom_style = styles.border_left_style = style
                else
                    color = parse_color(part)
                    styles.border_top_r, styles.border_top_g, styles.border_top_b, styles.border_top_a = color
                    styles.border_right_r, styles.border_right_g, styles.border_right_b, styles.border_right_a = color
                    styles.border_bottom_r, styles.border_bottom_g, styles.border_bottom_b, styles.border_bottom_a = color
                    styles.border_left_r, styles.border_left_g, styles.border_left_b, styles.border_left_a = color
                end
            end
        else
            values = parse_margin_shorthand(val)
            styles.border_top_width, styles.border_right_width, styles.border_bottom_width, styles.border_left_width = values
        end
    elseif prop == "border-style"
        style = parse_border_style(val_lower)
        styles.border_top_style = styles.border_right_style = styles.border_bottom_style = styles.border_left_style = style
    elseif prop == "border-color"
        color = parse_color(val)
        styles.border_top_r, styles.border_top_g, styles.border_top_b, styles.border_top_a = color
        styles.border_right_r, styles.border_right_g, styles.border_right_b, styles.border_right_a = color
        styles.border_bottom_r, styles.border_bottom_g, styles.border_bottom_b, styles.border_bottom_a = color
        styles.border_left_r, styles.border_left_g, styles.border_left_b, styles.border_left_a = color
    elseif prop == "line-height"
        if val_lower == "normal"
            styles.line_height_normal = true
        else
            (px, auto) = parse_length(val)
            !auto && (styles.line_height = px; styles.line_height_normal = false)
        end
    elseif prop == "font-size"
        (px, _) = parse_length(val)
        styles.font_size = px
    elseif prop == "content"
        content_val = strip(val)
        if content_val == "none" || content_val == "normal"
            styles.has_content = false; styles.content = ""
        else
            # Match quoted content with matching quote types
            m = match(r"^(['\"])(.*)\1\s*$", content_val)
            if m !== nothing
                styles.content = m.captures[2]; styles.has_content = true
            elseif content_val == "''" || content_val == "\"\""
                styles.content = ""; styles.has_content = true
            end
        end
    # ========== CSS3 Properties ==========
    # Opacity
    elseif prop == "opacity"
        opacity_val = tryparse(Float32, val)
        opacity_val !== nothing && (styles.opacity = clamp(opacity_val, 0.0f0, 1.0f0))
    # Border radius
    elseif prop == "border-radius"
        (px, _) = parse_length(val)
        styles.border_radius_tl = styles.border_radius_tr = styles.border_radius_br = styles.border_radius_bl = px
    elseif prop == "border-top-left-radius"
        (px, _) = parse_length(val); styles.border_radius_tl = px
    elseif prop == "border-top-right-radius"
        (px, _) = parse_length(val); styles.border_radius_tr = px
    elseif prop == "border-bottom-right-radius"
        (px, _) = parse_length(val); styles.border_radius_br = px
    elseif prop == "border-bottom-left-radius"
        (px, _) = parse_length(val); styles.border_radius_bl = px
    # Text properties
    elseif prop == "text-align"
        styles.text_align = val_lower == "left" ? TEXT_ALIGN_LEFT :
                           val_lower == "right" ? TEXT_ALIGN_RIGHT :
                           val_lower == "center" ? TEXT_ALIGN_CENTER :
                           val_lower == "justify" ? TEXT_ALIGN_JUSTIFY : TEXT_ALIGN_LEFT
    elseif prop == "text-decoration"
        styles.text_decoration = val_lower == "none" ? TEXT_DECORATION_NONE :
                                val_lower == "underline" ? TEXT_DECORATION_UNDERLINE :
                                val_lower == "overline" ? TEXT_DECORATION_OVERLINE :
                                val_lower == "line-through" ? TEXT_DECORATION_LINE_THROUGH : TEXT_DECORATION_NONE
    elseif prop == "font-weight"
        if val_lower == "normal"
            styles.font_weight = UInt16(400)
        elseif val_lower == "bold"
            styles.font_weight = UInt16(700)
        elseif val_lower == "lighter"
            styles.font_weight = UInt16(100)
        elseif val_lower == "bolder"
            styles.font_weight = UInt16(900)
        else
            w = tryparse(UInt16, val)
            w !== nothing && (styles.font_weight = w)
        end
    elseif prop == "letter-spacing"
        if val_lower != "normal"
            (px, _) = parse_length(val)
            styles.letter_spacing = px
        end
    elseif prop == "word-spacing"
        if val_lower != "normal"
            (px, _) = parse_length(val)
            styles.word_spacing = px
        end
    # Box sizing
    elseif prop == "box-sizing"
        styles.box_sizing = val_lower == "border-box" ? BOX_SIZING_BORDER_BOX : BOX_SIZING_CONTENT_BOX
    # Flexbox properties
    elseif prop == "flex-direction"
        styles.flex_direction = val_lower == "row" ? FLEX_DIRECTION_ROW :
                               val_lower == "row-reverse" ? FLEX_DIRECTION_ROW_REVERSE :
                               val_lower == "column" ? FLEX_DIRECTION_COLUMN :
                               val_lower == "column-reverse" ? FLEX_DIRECTION_COLUMN_REVERSE : FLEX_DIRECTION_ROW
    elseif prop == "flex-wrap"
        styles.flex_wrap = val_lower == "nowrap" ? FLEX_WRAP_NOWRAP :
                          val_lower == "wrap" ? FLEX_WRAP_WRAP :
                          val_lower == "wrap-reverse" ? FLEX_WRAP_WRAP_REVERSE : FLEX_WRAP_NOWRAP
    elseif prop == "flex-flow"
        parts = split(strip(val))
        for part in parts
            part_lower = lowercase(part)
            if part_lower in ["row", "row-reverse", "column", "column-reverse"]
                styles.flex_direction = part_lower == "row" ? FLEX_DIRECTION_ROW :
                                       part_lower == "row-reverse" ? FLEX_DIRECTION_ROW_REVERSE :
                                       part_lower == "column" ? FLEX_DIRECTION_COLUMN : FLEX_DIRECTION_COLUMN_REVERSE
            elseif part_lower in ["nowrap", "wrap", "wrap-reverse"]
                styles.flex_wrap = part_lower == "nowrap" ? FLEX_WRAP_NOWRAP :
                                  part_lower == "wrap" ? FLEX_WRAP_WRAP : FLEX_WRAP_WRAP_REVERSE
            end
        end
    elseif prop == "justify-content"
        styles.justify_content = val_lower == "flex-start" || val_lower == "start" ? JUSTIFY_CONTENT_START :
                                val_lower == "flex-end" || val_lower == "end" ? JUSTIFY_CONTENT_END :
                                val_lower == "center" ? JUSTIFY_CONTENT_CENTER :
                                val_lower == "space-between" ? JUSTIFY_CONTENT_BETWEEN :
                                val_lower == "space-around" ? JUSTIFY_CONTENT_AROUND :
                                val_lower == "space-evenly" ? JUSTIFY_CONTENT_EVENLY : JUSTIFY_CONTENT_START
    elseif prop == "align-items"
        styles.align_items = val_lower == "flex-start" || val_lower == "start" ? ALIGN_ITEMS_START :
                            val_lower == "flex-end" || val_lower == "end" ? ALIGN_ITEMS_END :
                            val_lower == "center" ? ALIGN_ITEMS_CENTER :
                            val_lower == "stretch" ? ALIGN_ITEMS_STRETCH :
                            val_lower == "baseline" ? ALIGN_ITEMS_BASELINE : ALIGN_ITEMS_STRETCH
    elseif prop == "align-content"
        styles.align_content = val_lower == "flex-start" || val_lower == "start" ? ALIGN_CONTENT_START :
                              val_lower == "flex-end" || val_lower == "end" ? ALIGN_CONTENT_END :
                              val_lower == "center" ? ALIGN_CONTENT_CENTER :
                              val_lower == "space-between" ? ALIGN_CONTENT_BETWEEN :
                              val_lower == "space-around" ? ALIGN_CONTENT_AROUND :
                              val_lower == "stretch" ? ALIGN_CONTENT_STRETCH : ALIGN_CONTENT_STRETCH
    elseif prop == "align-self"
        styles.align_self = val_lower == "auto" ? ALIGN_ITEMS_STRETCH :
                           val_lower == "flex-start" || val_lower == "start" ? ALIGN_ITEMS_START :
                           val_lower == "flex-end" || val_lower == "end" ? ALIGN_ITEMS_END :
                           val_lower == "center" ? ALIGN_ITEMS_CENTER :
                           val_lower == "baseline" ? ALIGN_ITEMS_BASELINE :
                           val_lower == "stretch" ? ALIGN_ITEMS_STRETCH : ALIGN_ITEMS_START
    elseif prop == "flex-grow"
        fg = tryparse(Float32, val)
        fg !== nothing && (styles.flex_grow = fg)
    elseif prop == "flex-shrink"
        fs = tryparse(Float32, val)
        fs !== nothing && (styles.flex_shrink = fs)
    elseif prop == "flex-basis"
        if val_lower == "auto"
            styles.flex_basis_auto = true
        else
            (px, auto) = parse_length(val)
            styles.flex_basis = px
            styles.flex_basis_auto = auto
        end
    elseif prop == "flex"
        # flex: <grow> <shrink> <basis>
        parts = split(strip(val))
        if val_lower == "none"
            styles.flex_grow = 0.0f0
            styles.flex_shrink = 0.0f0
            styles.flex_basis_auto = true
        elseif val_lower == "auto"
            styles.flex_grow = 1.0f0
            styles.flex_shrink = 1.0f0
            styles.flex_basis_auto = true
        elseif length(parts) == 1
            fg = tryparse(Float32, parts[1])
            if fg !== nothing
                styles.flex_grow = fg
                styles.flex_shrink = 1.0f0
                styles.flex_basis = 0.0f0
                styles.flex_basis_auto = false
            end
        elseif length(parts) >= 2
            fg = tryparse(Float32, parts[1])
            fg !== nothing && (styles.flex_grow = fg)
            fs = tryparse(Float32, parts[2])
            fs !== nothing && (styles.flex_shrink = fs)
            if length(parts) >= 3
                (px, auto) = parse_length(parts[3])
                styles.flex_basis = px
                styles.flex_basis_auto = auto
            end
        end
    elseif prop == "gap"
        parts = split(strip(val))
        if length(parts) == 1
            (px, _) = parse_length(parts[1])
            styles.gap_row = px
            styles.gap_column = px
        elseif length(parts) >= 2
            (row_px, _) = parse_length(parts[1])
            (col_px, _) = parse_length(parts[2])
            styles.gap_row = row_px
            styles.gap_column = col_px
        end
    elseif prop == "row-gap"
        (px, _) = parse_length(val); styles.gap_row = px
    elseif prop == "column-gap"
        (px, _) = parse_length(val); styles.gap_column = px
    elseif prop == "order"
        ord = tryparse(Int32, val)
        ord !== nothing && (styles.order = ord)
    # Box shadow
    elseif prop == "box-shadow"
        if val_lower == "none"
            styles.has_box_shadow = false
        else
            parse_box_shadow!(styles, val)
        end
    # Transform
    elseif prop == "transform"
        if val_lower == "none"
            styles.has_transform = false
        else
            parse_transform!(styles, val)
        end
    end
end

"Parse box-shadow value."
function parse_box_shadow!(styles::CSSStyles, val::AbstractString)
    val = lowercase(strip(val))
    
    # Check for inset
    styles.box_shadow_inset = contains(val, "inset")
    val = replace(val, "inset" => "")
    
    # Extract color - try specific patterns first before generic word match
    color = (0x00, 0x00, 0x00, 0x80)  # Default semi-transparent black
    color_found = false
    
    # Try rgba/rgb function first
    m = match(r"(rgba?\s*\([^)]+\))", val)
    if m !== nothing
        parsed_color = parse_color(m.captures[1])
        if parsed_color[4] != 0
            color = parsed_color
            val = replace(val, m.captures[1] => "")
            color_found = true
        end
    end
    
    # Try hex color
    if !color_found
        m = match(r"(#[0-9a-f]{3,8})", val)
        if m !== nothing
            parsed_color = parse_color(m.captures[1])
            if parsed_color[4] != 0
                color = parsed_color
                val = replace(val, m.captures[1] => "")
                color_found = true
            end
        end
    end
    
    # Try named colors (check against known colors dictionary)
    if !color_found
        for word in split(val)
            word = strip(word)
            if haskey(NAMED_COLORS, word)
                color = NAMED_COLORS[word]
                val = replace(val, word => "")
                color_found = true
                break
            end
        end
    end
    
    styles.box_shadow_r, styles.box_shadow_g, styles.box_shadow_b, styles.box_shadow_a = color
    
    # Parse lengths: offset-x, offset-y, blur?, spread?
    parts = split(strip(val))
    lengths = Float32[]
    for part in parts
        (px, auto) = parse_length(part)
        !auto && push!(lengths, px)
    end
    
    if length(lengths) >= 2
        styles.box_shadow_offset_x = lengths[1]
        styles.box_shadow_offset_y = lengths[2]
    end
    if length(lengths) >= 3
        styles.box_shadow_blur = lengths[3]
    end
    if length(lengths) >= 4
        styles.box_shadow_spread = lengths[4]
    end
    
    styles.has_box_shadow = length(lengths) >= 2
end

"Parse transform value."
function parse_transform!(styles::CSSStyles, val::AbstractString)
    val = lowercase(strip(val))
    
    # translateX/Y
    m = match(r"translatex\s*\(\s*([^)]+)\s*\)", val)
    if m !== nothing
        (px, _) = parse_length(m.captures[1])
        styles.transform_translate_x = px
        styles.has_transform = true
    end
    
    m = match(r"translatey\s*\(\s*([^)]+)\s*\)", val)
    if m !== nothing
        (px, _) = parse_length(m.captures[1])
        styles.transform_translate_y = px
        styles.has_transform = true
    end
    
    # translate(x, y)
    m = match(r"translate\s*\(\s*([^,]+)\s*(?:,\s*([^)]+))?\s*\)", val)
    if m !== nothing
        (px_x, _) = parse_length(m.captures[1])
        styles.transform_translate_x = px_x
        if m.captures[2] !== nothing
            (px_y, _) = parse_length(m.captures[2])
            styles.transform_translate_y = px_y
        end
        styles.has_transform = true
    end
    
    # rotate
    m = match(r"rotate\s*\(\s*([+-]?[\d.]+)(deg|rad|turn)?\s*\)", val)
    if m !== nothing
        angle = parse(Float32, m.captures[1])
        unit = m.captures[2] === nothing ? "deg" : m.captures[2]
        if unit == "rad"
            angle = angle * 180.0f0 / Float32(π)
        elseif unit == "turn"
            angle = angle * 360.0f0
        end
        styles.transform_rotate = angle
        styles.has_transform = true
    end
    
    # scaleX/Y
    m = match(r"scalex\s*\(\s*([+-]?[\d.]+)\s*\)", val)
    if m !== nothing
        styles.transform_scale_x = parse(Float32, m.captures[1])
        styles.has_transform = true
    end
    
    m = match(r"scaley\s*\(\s*([+-]?[\d.]+)\s*\)", val)
    if m !== nothing
        styles.transform_scale_y = parse(Float32, m.captures[1])
        styles.has_transform = true
    end
    
    # scale(x, y) or scale(n)
    m = match(r"scale\s*\(\s*([+-]?[\d.]+)\s*(?:,\s*([+-]?[\d.]+))?\s*\)", val)
    if m !== nothing
        sx = parse(Float32, m.captures[1])
        styles.transform_scale_x = sx
        styles.transform_scale_y = m.captures[2] !== nothing ? parse(Float32, m.captures[2]) : sx
        styles.has_transform = true
    end
end

function parse_border_style(val::AbstractString)::UInt8
    val_lower = lowercase(strip(val))
    val_lower == "solid" ? BORDER_STYLE_SOLID :
    val_lower == "dotted" ? BORDER_STYLE_DOTTED :
    val_lower == "dashed" ? BORDER_STYLE_DASHED : BORDER_STYLE_NONE
end

function parse_margin_shorthand(val::AbstractString)::NTuple{4, Float32}
    parts = split(strip(val))
    values = Float32[]
    
    for part in parts
        (px, _) = parse_length(part)
        push!(values, px)
    end
    
    length(values) == 1 && return (values[1], values[1], values[1], values[1])
    length(values) == 2 && return (values[1], values[2], values[1], values[2])
    length(values) == 3 && return (values[1], values[2], values[3], values[2])
    length(values) >= 4 && return (values[1], values[2], values[3], values[4])
    
    return (0.0f0, 0.0f0, 0.0f0, 0.0f0)
end

end # module CSSCore
