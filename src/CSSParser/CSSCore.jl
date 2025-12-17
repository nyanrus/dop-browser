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
export POSITION_STATIC, POSITION_RELATIVE, POSITION_ABSOLUTE, POSITION_FIXED
export OVERFLOW_VISIBLE, OVERFLOW_HIDDEN
export DISPLAY_BLOCK, DISPLAY_INLINE, DISPLAY_NONE, DISPLAY_TABLE, DISPLAY_TABLE_CELL, DISPLAY_TABLE_ROW, DISPLAY_INLINE_BLOCK
export FLOAT_NONE, FLOAT_LEFT, FLOAT_RIGHT
export CLEAR_NONE, CLEAR_LEFT, CLEAR_RIGHT, CLEAR_BOTH
export BORDER_STYLE_NONE, BORDER_STYLE_SOLID, BORDER_STYLE_DOTTED, BORDER_STYLE_DASHED

# Constants
const POSITION_STATIC, POSITION_RELATIVE, POSITION_ABSOLUTE, POSITION_FIXED = UInt8(0), UInt8(1), UInt8(2), UInt8(3)
const FLOAT_NONE, FLOAT_LEFT, FLOAT_RIGHT = UInt8(0), UInt8(1), UInt8(2)
const CLEAR_NONE, CLEAR_LEFT, CLEAR_RIGHT, CLEAR_BOTH = UInt8(0), UInt8(1), UInt8(2), UInt8(3)
const BORDER_STYLE_NONE, BORDER_STYLE_SOLID, BORDER_STYLE_DOTTED, BORDER_STYLE_DASHED = UInt8(0), UInt8(1), UInt8(2), UInt8(3)
const OVERFLOW_VISIBLE, OVERFLOW_HIDDEN = UInt8(0), UInt8(1)
const DISPLAY_NONE, DISPLAY_BLOCK, DISPLAY_INLINE = UInt8(0), UInt8(1), UInt8(2)
const DISPLAY_TABLE, DISPLAY_TABLE_CELL, DISPLAY_TABLE_ROW, DISPLAY_INLINE_BLOCK = UInt8(3), UInt8(4), UInt8(5), UInt8(6)

"CSSStyles - Computed CSS styles for a node."
mutable struct CSSStyles
    position::UInt8; float::UInt8; clear::UInt8
    top::Float32; right::Float32; bottom::Float32; left::Float32
    top_auto::Bool; right_auto::Bool; bottom_auto::Bool; left_auto::Bool
    z_index::Int32
    width::Float32; height::Float32; width_auto::Bool; height_auto::Bool
    min_width::Float32; max_width::Float32; min_height::Float32; max_height::Float32
    has_min_width::Bool; has_max_width::Bool; has_min_height::Bool; has_max_height::Bool
    margin_top::Float32; margin_right::Float32; margin_bottom::Float32; margin_left::Float32
    padding_top::Float32; padding_right::Float32; padding_bottom::Float32; padding_left::Float32
    border_top_width::Float32; border_right_width::Float32; border_bottom_width::Float32; border_left_width::Float32
    border_top_style::UInt8; border_right_style::UInt8; border_bottom_style::UInt8; border_left_style::UInt8
    border_top_r::UInt8; border_top_g::UInt8; border_top_b::UInt8; border_top_a::UInt8
    border_right_r::UInt8; border_right_g::UInt8; border_right_b::UInt8; border_right_a::UInt8
    border_bottom_r::UInt8; border_bottom_g::UInt8; border_bottom_b::UInt8; border_bottom_a::UInt8
    border_left_r::UInt8; border_left_g::UInt8; border_left_b::UInt8; border_left_a::UInt8
    display::UInt8; visibility::Bool; overflow::UInt8
    line_height::Float32; line_height_normal::Bool; font_size::Float32
    background_r::UInt8; background_g::UInt8; background_b::UInt8; background_a::UInt8
    color_r::UInt8; color_g::UInt8; color_b::UInt8; color_a::UInt8
    has_background::Bool; content::String; has_content::Bool
    
    CSSStyles() = new(
        POSITION_STATIC, FLOAT_NONE, CLEAR_NONE,
        0.0f0, 0.0f0, 0.0f0, 0.0f0, true, true, true, true, Int32(0),
        0.0f0, 0.0f0, true, true, 0.0f0, Float32(Inf), 0.0f0, Float32(Inf), false, false, false, false,
        0.0f0, 0.0f0, 0.0f0, 0.0f0, 0.0f0, 0.0f0, 0.0f0, 0.0f0,
        0.0f0, 0.0f0, 0.0f0, 0.0f0,
        BORDER_STYLE_NONE, BORDER_STYLE_NONE, BORDER_STYLE_NONE, BORDER_STYLE_NONE,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        DISPLAY_BLOCK, true, OVERFLOW_VISIBLE, 16.0f0, true, 16.0f0,
        0xff, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0xff, false, "", false
    )
end

const NAMED_COLORS = Dict{String,Tuple{UInt8,UInt8,UInt8,UInt8}}(
    "black"=>(0x00,0x00,0x00,0xff), "white"=>(0xff,0xff,0xff,0xff), "red"=>(0xff,0x00,0x00,0xff),
    "green"=>(0x00,0x80,0x00,0xff), "lime"=>(0x00,0xff,0x00,0xff), "blue"=>(0x00,0x00,0xff,0xff),
    "yellow"=>(0xff,0xff,0x00,0xff), "cyan"=>(0x00,0xff,0xff,0xff), "magenta"=>(0xff,0x00,0xff,0xff),
    "gray"=>(0x80,0x80,0x80,0xff), "grey"=>(0x80,0x80,0x80,0xff), "transparent"=>(0x00,0x00,0x00,0x00),
    "orange"=>(0xff,0xa5,0x00,0xff), "purple"=>(0x80,0x00,0x80,0xff), "navy"=>(0x00,0x00,0x80,0xff),
    "maroon"=>(0x80,0x00,0x00,0xff), "olive"=>(0x80,0x80,0x00,0xff), "teal"=>(0x00,0x80,0x80,0xff),
    "silver"=>(0xc0,0xc0,0xc0,0xff), "fuchsia"=>(0xff,0x00,0xff,0xff), "aqua"=>(0x00,0xff,0xff,0xff)
)

"Parse CSS color (hex #rgb/#rrggbb, named, rgb()/rgba())."
function parse_color(value::AbstractString)::Tuple{UInt8,UInt8,UInt8,UInt8}
    val = strip(lowercase(value))
    haskey(NAMED_COLORS, val) && return NAMED_COLORS[val]
    if startswith(val, "#")
        hex = val[2:end]
        if length(hex) == 3
            return (parse(UInt8, hex[1:1]*hex[1:1], base=16), parse(UInt8, hex[2:2]*hex[2:2], base=16), parse(UInt8, hex[3:3]*hex[3:3], base=16), 0xff)
        elseif length(hex) == 6
            return (parse(UInt8, hex[1:2], base=16), parse(UInt8, hex[3:4], base=16), parse(UInt8, hex[5:6], base=16), 0xff)
        end
    end
    if startswith(val, "rgb")
        m = match(r"rgba?\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)(?:\s*,\s*([\d.]+))?\s*\)", val)
        m !== nothing && return (parse(UInt8, m.captures[1]), parse(UInt8, m.captures[2]), parse(UInt8, m.captures[3]), 
                                  m.captures[4] !== nothing ? round(UInt8, parse(Float64, m.captures[4]) * 255) : 0xff)
    end
    (0x00, 0x00, 0x00, 0x00)
end

"Parse CSS length (px, %, em, mm, auto)."
function parse_length(value::AbstractString, container_size::Float32 = 0.0f0)::Tuple{Float32, Bool}
    val = strip(lowercase(value))
    val == "auto" && return (0.0f0, true)
    
    if endswith(val, "%")
        num = tryparse(Float32, val[1:end-1])
        num !== nothing && return (num / 100.0f0 * container_size, false)
    end
    
    num_str = replace(val, r"px$" => "")
    num = tryparse(Float32, num_str)
    num !== nothing && return (num, false)
    
    if endswith(val, "em")
        num = tryparse(Float32, val[1:end-2])
        num !== nothing && return (num * 16.0f0, false)
    end
    
    if endswith(val, "mm")
        num = tryparse(Float32, val[1:end-2])
        num !== nothing && return (num * 3.7795275591f0, false)
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
                         val_lower == "fixed" ? POSITION_FIXED : POSITION_STATIC
    elseif prop == "display"
        styles.display = val_lower == "block" ? DISPLAY_BLOCK :
                        val_lower == "inline" ? DISPLAY_INLINE :
                        val_lower == "none" ? DISPLAY_NONE :
                        val_lower == "table" ? DISPLAY_TABLE :
                        val_lower == "table-cell" ? DISPLAY_TABLE_CELL :
                        val_lower == "table-row" ? DISPLAY_TABLE_ROW :
                        val_lower == "inline-block" ? DISPLAY_INLINE_BLOCK : DISPLAY_BLOCK
    elseif prop == "visibility"
        styles.visibility = val_lower != "hidden"
    elseif prop == "overflow"
        styles.overflow = val_lower == "hidden" ? OVERFLOW_HIDDEN : OVERFLOW_VISIBLE
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
