"""
    CSSCore

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
module CSSCore

export CSSStyles, parse_inline_style, parse_color, parse_length
export POSITION_STATIC, POSITION_RELATIVE, POSITION_ABSOLUTE, POSITION_FIXED
export OVERFLOW_VISIBLE, OVERFLOW_HIDDEN
export DISPLAY_BLOCK, DISPLAY_INLINE, DISPLAY_NONE, DISPLAY_TABLE, DISPLAY_TABLE_CELL, DISPLAY_TABLE_ROW, DISPLAY_INLINE_BLOCK
export FLOAT_NONE, FLOAT_LEFT, FLOAT_RIGHT
export CLEAR_NONE, CLEAR_LEFT, CLEAR_RIGHT, CLEAR_BOTH
export BORDER_STYLE_NONE, BORDER_STYLE_SOLID, BORDER_STYLE_DOTTED, BORDER_STYLE_DASHED

# Position types
const POSITION_STATIC = UInt8(0)
const POSITION_RELATIVE = UInt8(1)
const POSITION_ABSOLUTE = UInt8(2)
const POSITION_FIXED = UInt8(3)

# Float types
const FLOAT_NONE = UInt8(0)
const FLOAT_LEFT = UInt8(1)
const FLOAT_RIGHT = UInt8(2)

# Clear types
const CLEAR_NONE = UInt8(0)
const CLEAR_LEFT = UInt8(1)
const CLEAR_RIGHT = UInt8(2)
const CLEAR_BOTH = UInt8(3)

# Border style types
const BORDER_STYLE_NONE = UInt8(0)
const BORDER_STYLE_SOLID = UInt8(1)
const BORDER_STYLE_DOTTED = UInt8(2)
const BORDER_STYLE_DASHED = UInt8(3)

# Overflow types
const OVERFLOW_VISIBLE = UInt8(0)
const OVERFLOW_HIDDEN = UInt8(1)

# Display types (must match LayoutArrays.jl)
const DISPLAY_NONE = UInt8(0)
const DISPLAY_BLOCK = UInt8(1)
const DISPLAY_INLINE = UInt8(2)
const DISPLAY_TABLE = UInt8(3)
const DISPLAY_TABLE_CELL = UInt8(4)
const DISPLAY_TABLE_ROW = UInt8(5)
const DISPLAY_INLINE_BLOCK = UInt8(6)

"""
    CSSStyles

Computed CSS styles for a node.
"""
mutable struct CSSStyles
    # Positioning
    position::UInt8  # POSITION_*
    float::UInt8  # FLOAT_*
    clear::UInt8  # CLEAR_*
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
    min_width::Float32
    max_width::Float32
    min_height::Float32
    max_height::Float32
    has_min_width::Bool
    has_max_width::Bool
    has_min_height::Bool
    has_max_height::Bool
    margin_top::Float32
    margin_right::Float32
    margin_bottom::Float32
    margin_left::Float32
    padding_top::Float32
    padding_right::Float32
    padding_bottom::Float32
    padding_left::Float32
    
    # Borders
    border_top_width::Float32
    border_right_width::Float32
    border_bottom_width::Float32
    border_left_width::Float32
    border_top_style::UInt8  # BORDER_STYLE_*
    border_right_style::UInt8
    border_bottom_style::UInt8
    border_left_style::UInt8
    border_top_r::UInt8
    border_top_g::UInt8
    border_top_b::UInt8
    border_top_a::UInt8
    border_right_r::UInt8
    border_right_g::UInt8
    border_right_b::UInt8
    border_right_a::UInt8
    border_bottom_r::UInt8
    border_bottom_g::UInt8
    border_bottom_b::UInt8
    border_bottom_a::UInt8
    border_left_r::UInt8
    border_left_g::UInt8
    border_left_b::UInt8
    border_left_a::UInt8
    
    # Display & visibility
    display::UInt8  # DISPLAY_*
    visibility::Bool  # true = visible
    overflow::UInt8  # OVERFLOW_*
    
    # Text properties
    line_height::Float32
    line_height_normal::Bool  # true if line-height is "normal" (auto)
    font_size::Float32
    
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
    
    # Content property for pseudo-elements
    content::String
    has_content::Bool
    
    function CSSStyles()
        new(
            POSITION_STATIC,
            FLOAT_NONE, CLEAR_NONE,
            0.0f0, 0.0f0, 0.0f0, 0.0f0,
            true, true, true, true,  # auto for top/right/bottom/left
            Int32(0),
            0.0f0, 0.0f0,
            true, true,  # width/height auto
            0.0f0, Float32(Inf), 0.0f0, Float32(Inf),  # min/max width/height
            false, false, false, false,  # has_min/max flags
            0.0f0, 0.0f0, 0.0f0, 0.0f0,  # margins
            0.0f0, 0.0f0, 0.0f0, 0.0f0,  # paddings
            0.0f0, 0.0f0, 0.0f0, 0.0f0,  # border widths
            BORDER_STYLE_NONE, BORDER_STYLE_NONE, BORDER_STYLE_NONE, BORDER_STYLE_NONE,
            0x00, 0x00, 0x00, 0x00,  # border top color
            0x00, 0x00, 0x00, 0x00,  # border right color
            0x00, 0x00, 0x00, 0x00,  # border bottom color
            0x00, 0x00, 0x00, 0x00,  # border left color
            DISPLAY_BLOCK,
            true,  # visible
            OVERFLOW_VISIBLE,
            16.0f0, true, 16.0f0,  # line-height (normal), font-size
            0xff, 0xff, 0xff, 0x00,  # transparent background
            0x00, 0x00, 0x00, 0xff,  # black text
            false,  # no background
            "",     # content
            false   # has_content
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
    
    # mm units (1mm = 3.7795275591 pixels at 96 DPI)
    if endswith(val, "mm")
        num = tryparse(Float32, val[1:end-2])
        if num !== nothing
            return (num * 3.7795275591f0, false)
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
        elseif val_lower == "table"
            styles.display = DISPLAY_TABLE
        elseif val_lower == "table-cell"
            styles.display = DISPLAY_TABLE_CELL
        elseif val_lower == "table-row"
            styles.display = DISPLAY_TABLE_ROW
        elseif val_lower == "inline-block"
            styles.display = DISPLAY_INLINE_BLOCK
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
        
    # Float and clear
    elseif prop == "float"
        if val_lower == "left"
            styles.float = FLOAT_LEFT
        elseif val_lower == "right"
            styles.float = FLOAT_RIGHT
        else
            styles.float = FLOAT_NONE
        end
        
    elseif prop == "clear"
        if val_lower == "left"
            styles.clear = CLEAR_LEFT
        elseif val_lower == "right"
            styles.clear = CLEAR_RIGHT
        elseif val_lower == "both"
            styles.clear = CLEAR_BOTH
        else
            styles.clear = CLEAR_NONE
        end
        
    # Min/Max dimensions
    elseif prop == "min-width"
        (px, auto) = parse_length(val)
        if !auto
            styles.min_width = px
            styles.has_min_width = true
        end
        
    elseif prop == "max-width"
        (px, auto) = parse_length(val)
        if !auto
            styles.max_width = px
            styles.has_max_width = true
        end
        
    elseif prop == "min-height"
        (px, auto) = parse_length(val)
        if !auto
            styles.min_height = px
            styles.has_min_height = true
        end
        
    elseif prop == "max-height"
        (px, auto) = parse_length(val)
        if !auto
            styles.max_height = px
            styles.has_max_height = true
        end
        
    # Border properties
    elseif prop == "border" || prop == "border-width"
        # Shorthand for all borders
        if prop == "border"
            # Extract width from border shorthand (e.g., "1px solid black")
            parts = split(strip(val))
            width_val = ""
            style_val = ""
            color_val = ""
            for part in parts
                part_lower = lowercase(part)
                if occursin(r"^\d+", part)
                    width_val = part
                elseif part_lower in ["solid", "dotted", "dashed", "none"]
                    style_val = part_lower
                else
                    color_val = part
                end
            end
            if !isempty(width_val)
                (px, _) = parse_length(width_val)
                styles.border_top_width = px
                styles.border_right_width = px
                styles.border_bottom_width = px
                styles.border_left_width = px
            end
            if !isempty(style_val)
                border_style = parse_border_style(style_val)
                styles.border_top_style = border_style
                styles.border_right_style = border_style
                styles.border_bottom_style = border_style
                styles.border_left_style = border_style
            end
            if !isempty(color_val)
                color = parse_color(color_val)
                styles.border_top_r, styles.border_top_g, styles.border_top_b, styles.border_top_a = color
                styles.border_right_r, styles.border_right_g, styles.border_right_b, styles.border_right_a = color
                styles.border_bottom_r, styles.border_bottom_g, styles.border_bottom_b, styles.border_bottom_a = color
                styles.border_left_r, styles.border_left_g, styles.border_left_b, styles.border_left_a = color
            end
        else
            values = parse_margin_shorthand(val)
            styles.border_top_width = values[1]
            styles.border_right_width = values[2]
            styles.border_bottom_width = values[3]
            styles.border_left_width = values[4]
        end
        
    elseif prop == "border-top" || prop == "border-right" || prop == "border-bottom" || prop == "border-left"
        # Individual border shorthands
        parts = split(strip(val))
        width_val = ""
        style_val = ""
        color_val = ""
        for part in parts
            part_lower = lowercase(part)
            if occursin(r"^\d+", part)
                width_val = part
            elseif part_lower in ["solid", "dotted", "dashed", "none"]
                style_val = part_lower
            else
                color_val = part
            end
        end
        
        if prop == "border-top"
            if !isempty(width_val)
                (px, _) = parse_length(width_val)
                styles.border_top_width = px
            end
            if !isempty(style_val)
                styles.border_top_style = parse_border_style(style_val)
            end
            if !isempty(color_val)
                color = parse_color(color_val)
                styles.border_top_r, styles.border_top_g, styles.border_top_b, styles.border_top_a = color
            end
        elseif prop == "border-right"
            if !isempty(width_val)
                (px, _) = parse_length(width_val)
                styles.border_right_width = px
            end
            if !isempty(style_val)
                styles.border_right_style = parse_border_style(style_val)
            end
            if !isempty(color_val)
                color = parse_color(color_val)
                styles.border_right_r, styles.border_right_g, styles.border_right_b, styles.border_right_a = color
            end
        elseif prop == "border-bottom"
            if !isempty(width_val)
                (px, _) = parse_length(width_val)
                styles.border_bottom_width = px
            end
            if !isempty(style_val)
                styles.border_bottom_style = parse_border_style(style_val)
            end
            if !isempty(color_val)
                color = parse_color(color_val)
                styles.border_bottom_r, styles.border_bottom_g, styles.border_bottom_b, styles.border_bottom_a = color
            end
        elseif prop == "border-left"
            if !isempty(width_val)
                (px, _) = parse_length(width_val)
                styles.border_left_width = px
            end
            if !isempty(style_val)
                styles.border_left_style = parse_border_style(style_val)
            end
            if !isempty(color_val)
                color = parse_color(color_val)
                styles.border_left_r, styles.border_left_g, styles.border_left_b, styles.border_left_a = color
            end
        end
        
    elseif prop == "border-top-width"
        (px, _) = parse_length(val)
        styles.border_top_width = px
        
    elseif prop == "border-right-width"
        (px, _) = parse_length(val)
        styles.border_right_width = px
        
    elseif prop == "border-bottom-width"
        (px, _) = parse_length(val)
        styles.border_bottom_width = px
        
    elseif prop == "border-left-width"
        (px, _) = parse_length(val)
        styles.border_left_width = px
        
    elseif prop == "border-style"
        # All sides
        border_style = parse_border_style(val_lower)
        styles.border_top_style = border_style
        styles.border_right_style = border_style
        styles.border_bottom_style = border_style
        styles.border_left_style = border_style
        
    elseif prop == "border-top-style"
        styles.border_top_style = parse_border_style(val_lower)
        
    elseif prop == "border-right-style"
        styles.border_right_style = parse_border_style(val_lower)
        
    elseif prop == "border-bottom-style"
        styles.border_bottom_style = parse_border_style(val_lower)
        
    elseif prop == "border-left-style"
        styles.border_left_style = parse_border_style(val_lower)
        
    elseif prop == "border-color"
        # All sides
        color = parse_color(val)
        styles.border_top_r, styles.border_top_g, styles.border_top_b, styles.border_top_a = color
        styles.border_right_r, styles.border_right_g, styles.border_right_b, styles.border_right_a = color
        styles.border_bottom_r, styles.border_bottom_g, styles.border_bottom_b, styles.border_bottom_a = color
        styles.border_left_r, styles.border_left_g, styles.border_left_b, styles.border_left_a = color
        
    elseif prop == "border-top-color"
        color = parse_color(val)
        styles.border_top_r, styles.border_top_g, styles.border_top_b, styles.border_top_a = color
        
    elseif prop == "border-right-color"
        color = parse_color(val)
        styles.border_right_r, styles.border_right_g, styles.border_right_b, styles.border_right_a = color
        
    elseif prop == "border-bottom-color"
        color = parse_color(val)
        styles.border_bottom_r, styles.border_bottom_g, styles.border_bottom_b, styles.border_bottom_a = color
        
    elseif prop == "border-left-color"
        color = parse_color(val)
        styles.border_left_r, styles.border_left_g, styles.border_left_b, styles.border_left_a = color
        
    # Text properties
    elseif prop == "line-height"
        if val_lower == "normal"
            styles.line_height_normal = true
        else
            (px, auto) = parse_length(val)
            if !auto
                styles.line_height = px
                styles.line_height_normal = false
            end
        end
        
    elseif prop == "font-size"
        (px, _) = parse_length(val)
        styles.font_size = px
        
    elseif prop == "font"
        # Parse font shorthand: [style] [variant] [weight] size[/line-height] family
        # e.g., "2px/4px serif" or "bold 12px/1.5 Arial"
        parts = split(strip(val))
        for i in 1:length(parts)
            part = parts[i]
            if contains(part, '/')
                # size/line-height format
                size_lh = split(part, '/')
                if length(size_lh) >= 2
                    (px, _) = parse_length(size_lh[1])
                    styles.font_size = px
                    (lh_px, auto) = parse_length(size_lh[2])
                    if !auto
                        styles.line_height = lh_px
                        styles.line_height_normal = false
                    end
                end
            elseif occursin(r"^\d", part) && !occursin(r"^(normal|bold|bolder|lighter|\d{3})$", part)
                # Pure size value
                (px, _) = parse_length(part)
                styles.font_size = px
            end
        end
        
    elseif prop == "content"
        # Parse content property - extract string value from quotes
        content_val = strip(val)
        if content_val == "none" || content_val == "normal"
            styles.has_content = false
            styles.content = ""
        else
            # Extract content from quotes (single or double)
            m = match(r"^['\"](.*)['\"]\s*$", content_val)
            if m !== nothing
                styles.content = m.captures[1]
                styles.has_content = true
            elseif content_val == "''" || content_val == "\"\""
                styles.content = ""
                styles.has_content = true
            end
        end
    end
end

"""
    parse_border_style(val::AbstractString) -> UInt8

Parse a border style value.
"""
function parse_border_style(val::AbstractString)::UInt8
    val_lower = lowercase(strip(val))
    if val_lower == "solid"
        return BORDER_STYLE_SOLID
    elseif val_lower == "dotted"
        return BORDER_STYLE_DOTTED
    elseif val_lower == "dashed"
        return BORDER_STYLE_DASHED
    else
        return BORDER_STYLE_NONE
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

end # module CSSCore
