"""
    CSSParser

CSS parsing and style computation for the Acid2 test.

Parses inline styles and style blocks, computing final styles for each node.
Supports key CSS properties needed for Acid2:
- position (static, relative, absolute, fixed)
- overflow (visible, hidden)
- display (block, inline, none)
- visibility (visible, hidden)
- background-color
- color
- width, height (px, %)
- margin (top, right, bottom, left)
- padding (top, right, bottom, left)
- top, right, bottom, left
- z-index
"""
module CSSParser

using ..StringInterner: StringPool, intern!, get_string

export CSSStyles, parse_inline_style, parse_color, parse_length
export POSITION_STATIC, POSITION_RELATIVE, POSITION_ABSOLUTE, POSITION_FIXED
export OVERFLOW_VISIBLE, OVERFLOW_HIDDEN
export DISPLAY_BLOCK, DISPLAY_INLINE, DISPLAY_NONE

# Position types
const POSITION_STATIC = UInt8(0)
const POSITION_RELATIVE = UInt8(1)
const POSITION_ABSOLUTE = UInt8(2)
const POSITION_FIXED = UInt8(3)

# Overflow types
const OVERFLOW_VISIBLE = UInt8(0)
const OVERFLOW_HIDDEN = UInt8(1)

# Display types (must match LayoutArrays.jl)
const DISPLAY_NONE = UInt8(0)
const DISPLAY_BLOCK = UInt8(1)
const DISPLAY_INLINE = UInt8(2)

"""
    CSSStyles

Computed CSS styles for a node.
"""
mutable struct CSSStyles
    # Positioning
    position::UInt8  # POSITION_*
    top::Float32
    right::Float32
    bottom::Float32
    left::Float32
    top_auto::Bool
    right_auto::Bool
    bottom_auto::Bool
    left_auto::Bool
    z_index::Int32
    
    # Box model
    width::Float32
    height::Float32
    width_auto::Bool
    height_auto::Bool
    margin_top::Float32
    margin_right::Float32
    margin_bottom::Float32
    margin_left::Float32
    padding_top::Float32
    padding_right::Float32
    padding_bottom::Float32
    padding_left::Float32
    
    # Display & visibility
    display::UInt8  # DISPLAY_*
    visibility::Bool  # true = visible
    overflow::UInt8  # OVERFLOW_*
    
    # Colors (RGBA, 0-255 each component)
    background_r::UInt8
    background_g::UInt8
    background_b::UInt8
    background_a::UInt8
    color_r::UInt8
    color_g::UInt8
    color_b::UInt8
    color_a::UInt8
    has_background::Bool
    
    function CSSStyles()
        new(
            POSITION_STATIC,
            0.0f0, 0.0f0, 0.0f0, 0.0f0,
            true, true, true, true,  # auto for top/right/bottom/left
            Int32(0),
            0.0f0, 0.0f0,
            true, true,  # width/height auto
            0.0f0, 0.0f0, 0.0f0, 0.0f0,  # margins
            0.0f0, 0.0f0, 0.0f0, 0.0f0,  # paddings
            DISPLAY_BLOCK,
            true,  # visible
            OVERFLOW_VISIBLE,
            0xff, 0xff, 0xff, 0x00,  # transparent background
            0x00, 0x00, 0x00, 0xff,  # black text
            false  # no background
        )
    end
end

"""
    parse_color(value::AbstractString) -> Tuple{UInt8, UInt8, UInt8, UInt8}

Parse a CSS color value and return RGBA components.
Supports: hex colors (#rgb, #rrggbb), named colors.
"""
function parse_color(value::AbstractString)::Tuple{UInt8, UInt8, UInt8, UInt8}
    val = strip(lowercase(value))
    
    # Named colors
    named_colors = Dict{String, Tuple{UInt8,UInt8,UInt8,UInt8}}(
        "black" => (0x00, 0x00, 0x00, 0xff),
        "white" => (0xff, 0xff, 0xff, 0xff),
        "red" => (0xff, 0x00, 0x00, 0xff),
        "green" => (0x00, 0x80, 0x00, 0xff),
        "lime" => (0x00, 0xff, 0x00, 0xff),
        "blue" => (0x00, 0x00, 0xff, 0xff),
        "yellow" => (0xff, 0xff, 0x00, 0xff),
        "cyan" => (0x00, 0xff, 0xff, 0xff),
        "magenta" => (0xff, 0x00, 0xff, 0xff),
        "gray" => (0x80, 0x80, 0x80, 0xff),
        "grey" => (0x80, 0x80, 0x80, 0xff),
        "transparent" => (0x00, 0x00, 0x00, 0x00),
        "orange" => (0xff, 0xa5, 0x00, 0xff),
        "purple" => (0x80, 0x00, 0x80, 0xff),
        "navy" => (0x00, 0x00, 0x80, 0xff),
        "maroon" => (0x80, 0x00, 0x00, 0xff),
        "olive" => (0x80, 0x80, 0x00, 0xff),
        "teal" => (0x00, 0x80, 0x80, 0xff),
        "silver" => (0xc0, 0xc0, 0xc0, 0xff),
        "fuchsia" => (0xff, 0x00, 0xff, 0xff),
        "aqua" => (0x00, 0xff, 0xff, 0xff),
    )
    
    if haskey(named_colors, val)
        return named_colors[val]
    end
    
    # Hex color
    if startswith(val, "#")
        hex = val[2:end]
        if length(hex) == 3
            # #rgb -> #rrggbb
            r = parse(UInt8, hex[1:1] * hex[1:1], base=16)
            g = parse(UInt8, hex[2:2] * hex[2:2], base=16)
            b = parse(UInt8, hex[3:3] * hex[3:3], base=16)
            return (r, g, b, 0xff)
        elseif length(hex) == 6
            r = parse(UInt8, hex[1:2], base=16)
            g = parse(UInt8, hex[3:4], base=16)
            b = parse(UInt8, hex[5:6], base=16)
            return (r, g, b, 0xff)
        end
    end
    
    # rgb() and rgba() functions
    if startswith(val, "rgb")
        m = match(r"rgba?\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)(?:\s*,\s*([\d.]+))?\s*\)", val)
        if m !== nothing
            r = parse(UInt8, m.captures[1])
            g = parse(UInt8, m.captures[2])
            b = parse(UInt8, m.captures[3])
            a = m.captures[4] !== nothing ? round(UInt8, parse(Float64, m.captures[4]) * 255) : 0xff
            return (r, g, b, a)
        end
    end
    
    # Default to transparent
    return (0x00, 0x00, 0x00, 0x00)
end

"""
    parse_length(value::AbstractString, container_size::Float32 = 0.0f0) -> Tuple{Float32, Bool}

Parse a CSS length value and return (pixels, is_auto).
Supports: px, %, auto.
"""
function parse_length(value::AbstractString, container_size::Float32 = 0.0f0)::Tuple{Float32, Bool}
    val = strip(lowercase(value))
    
    if val == "auto"
        return (0.0f0, true)
    end
    
    # Percentage
    if endswith(val, "%")
        num = tryparse(Float32, val[1:end-1])
        if num !== nothing
            return (num / 100.0f0 * container_size, false)
        end
    end
    
    # Pixels (default unit)
    num_str = replace(val, r"px$" => "")
    num = tryparse(Float32, num_str)
    if num !== nothing
        return (num, false)
    end
    
    # em units (assume 16px base)
    if endswith(val, "em")
        num = tryparse(Float32, val[1:end-2])
        if num !== nothing
            return (num * 16.0f0, false)
        end
    end
    
    return (0.0f0, true)
end

"""
    parse_inline_style(style_str::AbstractString) -> CSSStyles

Parse an inline style attribute and return computed styles.
"""
function parse_inline_style(style_str::AbstractString)::CSSStyles
    styles = CSSStyles()
    
    # Split by semicolon
    declarations = split(style_str, ";")
    
    for decl in declarations
        decl = strip(decl)
        if isempty(decl)
            continue
        end
        
        # Split by colon
        colon_idx = findfirst(':', decl)
        if colon_idx === nothing
            continue
        end
        
        prop = strip(lowercase(decl[1:colon_idx-1]))
        val = strip(decl[colon_idx+1:end])
        
        apply_property!(styles, prop, val)
    end
    
    return styles
end

"""
    apply_property!(styles::CSSStyles, prop::AbstractString, val::AbstractString)

Apply a CSS property to the styles.
"""
function apply_property!(styles::CSSStyles, prop::AbstractString, val::AbstractString)
    val_lower = lowercase(val)
    
    if prop == "position"
        if val_lower == "static"
            styles.position = POSITION_STATIC
        elseif val_lower == "relative"
            styles.position = POSITION_RELATIVE
        elseif val_lower == "absolute"
            styles.position = POSITION_ABSOLUTE
        elseif val_lower == "fixed"
            styles.position = POSITION_FIXED
        end
        
    elseif prop == "display"
        if val_lower == "block"
            styles.display = DISPLAY_BLOCK
        elseif val_lower == "inline"
            styles.display = DISPLAY_INLINE
        elseif val_lower == "none"
            styles.display = DISPLAY_NONE
        end
        
    elseif prop == "visibility"
        styles.visibility = val_lower != "hidden"
        
    elseif prop == "overflow"
        if val_lower == "hidden"
            styles.overflow = OVERFLOW_HIDDEN
        else
            styles.overflow = OVERFLOW_VISIBLE
        end
        
    elseif prop == "background-color" || prop == "background"
        color = parse_color(val)
        styles.background_r = color[1]
        styles.background_g = color[2]
        styles.background_b = color[3]
        styles.background_a = color[4]
        styles.has_background = color[4] > 0
        
    elseif prop == "color"
        color = parse_color(val)
        styles.color_r = color[1]
        styles.color_g = color[2]
        styles.color_b = color[3]
        styles.color_a = color[4]
        
    elseif prop == "width"
        (px, auto) = parse_length(val)
        styles.width = px
        styles.width_auto = auto
        
    elseif prop == "height"
        (px, auto) = parse_length(val)
        styles.height = px
        styles.height_auto = auto
        
    elseif prop == "top"
        (px, auto) = parse_length(val)
        styles.top = px
        styles.top_auto = auto
        
    elseif prop == "right"
        (px, auto) = parse_length(val)
        styles.right = px
        styles.right_auto = auto
        
    elseif prop == "bottom"
        (px, auto) = parse_length(val)
        styles.bottom = px
        styles.bottom_auto = auto
        
    elseif prop == "left"
        (px, auto) = parse_length(val)
        styles.left = px
        styles.left_auto = auto
        
    elseif prop == "z-index"
        z = tryparse(Int32, val)
        if z !== nothing
            styles.z_index = z
        end
        
    elseif prop == "margin"
        values = parse_margin_shorthand(val)
        styles.margin_top = values[1]
        styles.margin_right = values[2]
        styles.margin_bottom = values[3]
        styles.margin_left = values[4]
        
    elseif prop == "margin-top"
        (px, _) = parse_length(val)
        styles.margin_top = px
        
    elseif prop == "margin-right"
        (px, _) = parse_length(val)
        styles.margin_right = px
        
    elseif prop == "margin-bottom"
        (px, _) = parse_length(val)
        styles.margin_bottom = px
        
    elseif prop == "margin-left"
        (px, _) = parse_length(val)
        styles.margin_left = px
        
    elseif prop == "padding"
        values = parse_margin_shorthand(val)
        styles.padding_top = values[1]
        styles.padding_right = values[2]
        styles.padding_bottom = values[3]
        styles.padding_left = values[4]
        
    elseif prop == "padding-top"
        (px, _) = parse_length(val)
        styles.padding_top = px
        
    elseif prop == "padding-right"
        (px, _) = parse_length(val)
        styles.padding_right = px
        
    elseif prop == "padding-bottom"
        (px, _) = parse_length(val)
        styles.padding_bottom = px
        
    elseif prop == "padding-left"
        (px, _) = parse_length(val)
        styles.padding_left = px
    end
end

"""
    parse_margin_shorthand(val::AbstractString) -> NTuple{4, Float32}

Parse margin/padding shorthand (1-4 values) into top, right, bottom, left.
"""
function parse_margin_shorthand(val::AbstractString)::NTuple{4, Float32}
    parts = split(strip(val))
    values = Float32[]
    
    for part in parts
        (px, _) = parse_length(part)
        push!(values, px)
    end
    
    if length(values) == 1
        return (values[1], values[1], values[1], values[1])
    elseif length(values) == 2
        return (values[1], values[2], values[1], values[2])
    elseif length(values) == 3
        return (values[1], values[2], values[3], values[2])
    elseif length(values) >= 4
        return (values[1], values[2], values[3], values[4])
    end
    
    return (0.0f0, 0.0f0, 0.0f0, 0.0f0)
end

end # module CSSParser
