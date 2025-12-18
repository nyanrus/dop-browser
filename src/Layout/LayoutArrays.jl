"""
    LayoutArrays

SIMD-friendly layout computation using contiguous float arrays.
Layout data is stored in Structure of Arrays format for vectorized computation.
"""
module LayoutArrays

export LayoutData, resize_layout!, set_bounds!, get_bounds, set_position!, get_position, compute_layout!
export set_css_position!, set_offsets!, set_margins!, set_paddings!, set_overflow!, set_visibility!, set_z_index!
export set_background_color!, get_background_color, set_borders!, has_border, set_float!, set_clear!

# Constants (position, overflow, display, float, clear)
const POSITION_STATIC, POSITION_RELATIVE, POSITION_ABSOLUTE, POSITION_FIXED = UInt8(0), UInt8(1), UInt8(2), UInt8(3)
const OVERFLOW_VISIBLE, OVERFLOW_HIDDEN = UInt8(0), UInt8(1)
const DISPLAY_NONE, DISPLAY_BLOCK, DISPLAY_INLINE = UInt8(0), UInt8(1), UInt8(2)
const DISPLAY_TABLE, DISPLAY_TABLE_CELL, DISPLAY_TABLE_ROW, DISPLAY_INLINE_BLOCK = UInt8(3), UInt8(4), UInt8(5), UInt8(6)
const DISPLAY_FLEX, DISPLAY_INLINE_FLEX, DISPLAY_GRID, DISPLAY_INLINE_GRID = UInt8(7), UInt8(8), UInt8(9), UInt8(10)
const FLOAT_NONE, FLOAT_LEFT, FLOAT_RIGHT = UInt8(0), UInt8(1), UInt8(2)
const CLEAR_NONE, CLEAR_LEFT, CLEAR_RIGHT, CLEAR_BOTH = UInt8(0), UInt8(1), UInt8(2), UInt8(3)

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

"""
    LayoutData

Contiguous arrays for layout computation, designed for SIMD/AVX operations.

Each node's layout is stored at the corresponding index in each array.
All arrays are pre-allocated and resized together.

## Mathematical Model (Box Model)

    +--------------------------------------------------+
    |                    margin_top                    |
    |   +------------------------------------------+   |
    |   |              border_top                  |   |
    | m |   +----------------------------------+   | m |
    | a | b |           padding_top            | b | a |
    | r | o |   +------------------------+     | o | r |
    | g | r |   |                        |     | r | g |
    | i | d | p |      CONTENT BOX       | p | d | i |
    | n | e | a |      (x, y, w, h)      | a | e | n |
    |   | r | d |                        | d | r |   |
    | l |   | d +------------------------+ d |   | r |
    | e | l | i |                        | i | r | i |
    | f | e | n +------------------------+ n | i | g |
    | t | f | g           padding_bottom   g | g | h |
    |   | t +----------------------------------+ h | t |
    |   |              border_bottom           | t |   |
    |   +------------------------------------------+   |
    |                    margin_bottom                 |
    +--------------------------------------------------+
"""

# Field specifications: (name, type, default_value)
const LAYOUT_FIELDS = [
    # Position & dimensions
    (:x, Float32, 0.0f0), (:y, Float32, 0.0f0), (:width, Float32, 0.0f0), (:height, Float32, 0.0f0),
    (:content_width, Float32, 0.0f0), (:content_height, Float32, 0.0f0),
    # Margins
    (:margin_top, Float32, 0.0f0), (:margin_right, Float32, 0.0f0), 
    (:margin_bottom, Float32, 0.0f0), (:margin_left, Float32, 0.0f0),
    # Paddings
    (:padding_top, Float32, 0.0f0), (:padding_right, Float32, 0.0f0),
    (:padding_bottom, Float32, 0.0f0), (:padding_left, Float32, 0.0f0),
    # Border widths
    (:border_top_width, Float32, 0.0f0), (:border_right_width, Float32, 0.0f0),
    (:border_bottom_width, Float32, 0.0f0), (:border_left_width, Float32, 0.0f0),
    # Border styles
    (:border_top_style, UInt8, 0x00), (:border_right_style, UInt8, 0x00),
    (:border_bottom_style, UInt8, 0x00), (:border_left_style, UInt8, 0x00),
    # Border colors (top, right, bottom, left - RGBA each)
    (:border_top_r, UInt8, 0x00), (:border_top_g, UInt8, 0x00), (:border_top_b, UInt8, 0x00), (:border_top_a, UInt8, 0x00),
    (:border_right_r, UInt8, 0x00), (:border_right_g, UInt8, 0x00), (:border_right_b, UInt8, 0x00), (:border_right_a, UInt8, 0x00),
    (:border_bottom_r, UInt8, 0x00), (:border_bottom_g, UInt8, 0x00), (:border_bottom_b, UInt8, 0x00), (:border_bottom_a, UInt8, 0x00),
    (:border_left_r, UInt8, 0x00), (:border_left_g, UInt8, 0x00), (:border_left_b, UInt8, 0x00), (:border_left_a, UInt8, 0x00),
    # CSS positioning
    (:position_type, UInt8, POSITION_STATIC), (:offset_top, Float32, 0.0f0), (:offset_right, Float32, 0.0f0),
    (:offset_bottom, Float32, 0.0f0), (:offset_left, Float32, 0.0f0),
    (:offset_top_auto, Bool, true), (:offset_right_auto, Bool, true), (:offset_bottom_auto, Bool, true), (:offset_left_auto, Bool, true),
    (:z_index, Int32, Int32(0)),
    # Float and clear
    (:float_type, UInt8, 0x00), (:clear_type, UInt8, 0x00),
    # Display & visibility  
    (:display, UInt8, DISPLAY_BLOCK), (:visibility, Bool, true), (:overflow, UInt8, OVERFLOW_VISIBLE),
    # Background colors
    (:bg_r, UInt8, 0xff), (:bg_g, UInt8, 0xff), (:bg_b, UInt8, 0xff), (:bg_a, UInt8, 0x00),
    (:has_background, Bool, false), (:dirty, Bool, true)
]

"LayoutData - Structure of Arrays for layout computation (SIMD-friendly)."
mutable struct LayoutData
    x::Vector{Float32}; y::Vector{Float32}; width::Vector{Float32}; height::Vector{Float32}
    content_width::Vector{Float32}; content_height::Vector{Float32}
    margin_top::Vector{Float32}; margin_right::Vector{Float32}; margin_bottom::Vector{Float32}; margin_left::Vector{Float32}
    padding_top::Vector{Float32}; padding_right::Vector{Float32}; padding_bottom::Vector{Float32}; padding_left::Vector{Float32}
    border_top_width::Vector{Float32}; border_right_width::Vector{Float32}; border_bottom_width::Vector{Float32}; border_left_width::Vector{Float32}
    border_top_style::Vector{UInt8}; border_right_style::Vector{UInt8}; border_bottom_style::Vector{UInt8}; border_left_style::Vector{UInt8}
    border_top_r::Vector{UInt8}; border_top_g::Vector{UInt8}; border_top_b::Vector{UInt8}; border_top_a::Vector{UInt8}
    border_right_r::Vector{UInt8}; border_right_g::Vector{UInt8}; border_right_b::Vector{UInt8}; border_right_a::Vector{UInt8}
    border_bottom_r::Vector{UInt8}; border_bottom_g::Vector{UInt8}; border_bottom_b::Vector{UInt8}; border_bottom_a::Vector{UInt8}
    border_left_r::Vector{UInt8}; border_left_g::Vector{UInt8}; border_left_b::Vector{UInt8}; border_left_a::Vector{UInt8}
    position_type::Vector{UInt8}; offset_top::Vector{Float32}; offset_right::Vector{Float32}; offset_bottom::Vector{Float32}; offset_left::Vector{Float32}
    offset_top_auto::Vector{Bool}; offset_right_auto::Vector{Bool}; offset_bottom_auto::Vector{Bool}; offset_left_auto::Vector{Bool}
    z_index::Vector{Int32}; float_type::Vector{UInt8}; clear_type::Vector{UInt8}
    display::Vector{UInt8}; visibility::Vector{Bool}; overflow::Vector{UInt8}
    bg_r::Vector{UInt8}; bg_g::Vector{UInt8}; bg_b::Vector{UInt8}; bg_a::Vector{UInt8}
    has_background::Vector{Bool}; dirty::Vector{Bool}
    
    function LayoutData(capacity::Int = 0)
        args = [Vector{t}(undef, capacity) for (_, t, _) in LAYOUT_FIELDS]
        new(args...)
    end
end

"Resize all layout arrays. New entries are initialized with defaults from LAYOUT_FIELDS."
function resize_layout!(layout::LayoutData, new_size::Int)
    old_size = length(layout.x)
    # Resize all arrays using field metadata
    for (name, _, _) in LAYOUT_FIELDS
        resize!(getfield(layout, name), new_size)
    end
    # Initialize new entries with defaults
    for i in (old_size + 1):new_size
        for (name, _, default) in LAYOUT_FIELDS
            getfield(layout, name)[i] = default
        end
    end
    layout
end

# Helper to check valid id range
@inline valid_id(layout, id) = id >= 1 && id <= length(layout.x)

"Set width and height for a node."
function set_bounds!(layout::LayoutData, id::Int, width::Float32, height::Float32)
    valid_id(layout, id) && (layout.width[id] = width; layout.height[id] = height; layout.dirty[id] = true)
end

"Get width and height for a node."
get_bounds(layout::LayoutData, id::Int)::Tuple{Float32, Float32} = 
    valid_id(layout, id) ? (layout.width[id], layout.height[id]) : (0.0f0, 0.0f0)

"Set position for a node."
function set_position!(layout::LayoutData, id::Int, x::Float32, y::Float32)
    valid_id(layout, id) && (layout.x[id] = x; layout.y[id] = y)
end

"Get position for a node."
get_position(layout::LayoutData, id::Int)::Tuple{Float32, Float32} = 
    valid_id(layout, id) ? (layout.x[id], layout.y[id]) : (0.0f0, 0.0f0)

"Set CSS position type."
function set_css_position!(layout::LayoutData, id::Int, pos_type::UInt8)
    valid_id(layout, id) && (layout.position_type[id] = pos_type; layout.dirty[id] = true)
end

"Set CSS offset properties for positioned elements."
function set_offsets!(layout::LayoutData, id::Int;
                      top::Float32=0.0f0, right::Float32=0.0f0, bottom::Float32=0.0f0, left::Float32=0.0f0,
                      top_auto::Bool=true, right_auto::Bool=true, bottom_auto::Bool=true, left_auto::Bool=true)
    valid_id(layout, id) || return
    layout.offset_top[id], layout.offset_right[id] = top, right
    layout.offset_bottom[id], layout.offset_left[id] = bottom, left
    layout.offset_top_auto[id], layout.offset_right_auto[id] = top_auto, right_auto
    layout.offset_bottom_auto[id], layout.offset_left_auto[id] = bottom_auto, left_auto
    layout.dirty[id] = true
end

"Set margins for a node."
function set_margins!(layout::LayoutData, id::Int; top::Float32=0.0f0, right::Float32=0.0f0, bottom::Float32=0.0f0, left::Float32=0.0f0)
    valid_id(layout, id) || return
    layout.margin_top[id], layout.margin_right[id] = top, right
    layout.margin_bottom[id], layout.margin_left[id] = bottom, left
    layout.dirty[id] = true
end

"Set paddings for a node."
function set_paddings!(layout::LayoutData, id::Int; top::Float32=0.0f0, right::Float32=0.0f0, bottom::Float32=0.0f0, left::Float32=0.0f0)
    valid_id(layout, id) || return
    layout.padding_top[id], layout.padding_right[id] = top, right
    layout.padding_bottom[id], layout.padding_left[id] = bottom, left
    layout.dirty[id] = true
end

"Set overflow behavior."
set_overflow!(layout::LayoutData, id::Int, overflow::UInt8) = valid_id(layout, id) && (layout.overflow[id] = overflow)

"Set visibility."
set_visibility!(layout::LayoutData, id::Int, visible::Bool) = valid_id(layout, id) && (layout.visibility[id] = visible)

"Set z-index."
set_z_index!(layout::LayoutData, id::Int, z::Int32) = valid_id(layout, id) && (layout.z_index[id] = z)

"Set float property (0=none, 1=left, 2=right)."
function set_float!(layout::LayoutData, id::Int, float_type::UInt8)
    valid_id(layout, id) && (layout.float_type[id] = float_type; layout.dirty[id] = true)
end

"Set clear property (0=none, 1=left, 2=right, 3=both)."
function set_clear!(layout::LayoutData, id::Int, clear_type::UInt8)
    valid_id(layout, id) && (layout.clear_type[id] = clear_type; layout.dirty[id] = true)
end

"Set background color."
function set_background_color!(layout::LayoutData, id::Int, r::UInt8, g::UInt8, b::UInt8, a::UInt8)
    valid_id(layout, id) || return
    layout.bg_r[id], layout.bg_g[id], layout.bg_b[id], layout.bg_a[id] = r, g, b, a
    layout.has_background[id] = a > 0
end

"Get background color."
get_background_color(layout::LayoutData, id::Int)::Tuple{UInt8,UInt8,UInt8,UInt8} = 
    valid_id(layout, id) ? (layout.bg_r[id], layout.bg_g[id], layout.bg_b[id], layout.bg_a[id]) : (0x00, 0x00, 0x00, 0x00)

"Set border properties (widths, styles, colors per side)."
function set_borders!(layout::LayoutData, id::Int;
        top_width::Float32=0.0f0, right_width::Float32=0.0f0, bottom_width::Float32=0.0f0, left_width::Float32=0.0f0,
        top_style::UInt8=0x00, right_style::UInt8=0x00, bottom_style::UInt8=0x00, left_style::UInt8=0x00,
        top_r::UInt8=0x00, top_g::UInt8=0x00, top_b::UInt8=0x00, top_a::UInt8=0x00,
        right_r::UInt8=0x00, right_g::UInt8=0x00, right_b::UInt8=0x00, right_a::UInt8=0x00,
        bottom_r::UInt8=0x00, bottom_g::UInt8=0x00, bottom_b::UInt8=0x00, bottom_a::UInt8=0x00,
        left_r::UInt8=0x00, left_g::UInt8=0x00, left_b::UInt8=0x00, left_a::UInt8=0x00)
    valid_id(layout, id) || return
    # Widths & styles
    layout.border_top_width[id], layout.border_right_width[id] = top_width, right_width
    layout.border_bottom_width[id], layout.border_left_width[id] = bottom_width, left_width
    layout.border_top_style[id], layout.border_right_style[id] = top_style, right_style
    layout.border_bottom_style[id], layout.border_left_style[id] = bottom_style, left_style
    # Colors
    layout.border_top_r[id], layout.border_top_g[id], layout.border_top_b[id], layout.border_top_a[id] = top_r, top_g, top_b, top_a
    layout.border_right_r[id], layout.border_right_g[id], layout.border_right_b[id], layout.border_right_a[id] = right_r, right_g, right_b, right_a
    layout.border_bottom_r[id], layout.border_bottom_g[id], layout.border_bottom_b[id], layout.border_bottom_a[id] = bottom_r, bottom_g, bottom_b, bottom_a
    layout.border_left_r[id], layout.border_left_g[id], layout.border_left_b[id], layout.border_left_a[id] = left_r, left_g, left_b, left_a
end

"Check if node has any visible border (width > 0, style != 0, alpha > 0)."
function has_border(layout::LayoutData, id::Int)::Bool
    valid_id(layout, id) || return false
    is_visible(w, s, a) = w > 0 && s != 0 && a > 0
    is_visible(layout.border_top_width[id], layout.border_top_style[id], layout.border_top_a[id]) ||
    is_visible(layout.border_right_width[id], layout.border_right_style[id], layout.border_right_a[id]) ||
    is_visible(layout.border_bottom_width[id], layout.border_bottom_style[id], layout.border_bottom_a[id]) ||
    is_visible(layout.border_left_width[id], layout.border_left_style[id], layout.border_left_a[id])
end

"Find containing block for positioned element (nearest ancestor with position != static)."
function find_containing_block(layout::LayoutData, parents::Vector{UInt32}, node_id::Int)::Int
    parent_id = Int(parents[node_id])
    while parent_id != 0
        layout.position_type[parent_id] != POSITION_STATIC && return parent_id
        parent_id = Int(parents[parent_id])
    end
    0  # Use viewport
end

"Compute layout for all dirty nodes using flat loop iteration (SIMD-friendly)."
function compute_layout!(layout::LayoutData, parents::Vector{UInt32}, 
                         first_children::Vector{UInt32}, next_siblings::Vector{UInt32})
    n = length(layout.x)
    if n == 0
        return
    end
    
    # First pass: compute content sizes (bottom-up)
    @inbounds for i in n:-1:1
        if !layout.dirty[i]
            continue
        end
        
        # Skip display:none elements
        if layout.display[i] == DISPLAY_NONE
            continue
        end
        
        # Calculate content size from children (only in-flow children)
        child_id = first_children[i]
        total_height = 0.0f0
        max_width = 0.0f0
        float_height = 0.0f0  # Track float height
        
        while child_id != 0
            # Skip out-of-flow children (absolute/fixed positioned)
            if layout.position_type[child_id] != POSITION_ABSOLUTE && 
               layout.position_type[child_id] != POSITION_FIXED &&
               layout.display[child_id] != DISPLAY_NONE
                child_h = layout.height[child_id] + layout.margin_top[child_id] + layout.margin_bottom[child_id]
                child_w = layout.width[child_id] + layout.margin_left[child_id] + layout.margin_right[child_id]
                
                # Floats don't contribute to block height in the same way
                if layout.float_type[child_id] != FLOAT_NONE
                    float_height = max(float_height, child_h)
                else
                    total_height += child_h
                end
                max_width = max(max_width, child_w)
            end
            child_id = next_siblings[child_id]
        end
        
        # Floats expand container if they're taller than block content
        total_height = max(total_height, float_height)
        
        layout.content_width[i] = max_width
        layout.content_height[i] = total_height
        
        # Update dimensions if not explicitly set
        if layout.width[i] == 0.0f0
            layout.width[i] = max_width + layout.padding_left[i] + layout.padding_right[i]
        end
        if layout.height[i] == 0.0f0
            layout.height[i] = total_height + layout.padding_top[i] + layout.padding_bottom[i]
        end
    end
    
    # Second pass: compute positions (top-down) with float support
    @inbounds for i in 1:n
        if !layout.dirty[i]
            continue
        end
        
        # Skip display:none elements
        if layout.display[i] == DISPLAY_NONE
            layout.x[i] = 0.0f0
            layout.y[i] = 0.0f0
            layout.dirty[i] = false
            continue
        end
        
        parent_id = Int(parents[i])
        pos_type = layout.position_type[i]
        float_type = layout.float_type[i]
        
        if pos_type == POSITION_ABSOLUTE || pos_type == POSITION_FIXED
            # Absolute/fixed positioning
            containing_block = find_containing_block(layout, parents, i)
            
            if containing_block == 0
                # Use viewport (assume root is at 0,0)
                cb_x = 0.0f0
                cb_y = 0.0f0
                cb_w = n >= 1 ? layout.width[1] : 0.0f0
                cb_h = n >= 1 ? layout.height[1] : 0.0f0
            else
                cb_x = layout.x[containing_block]
                cb_y = layout.y[containing_block]
                cb_w = layout.width[containing_block]
                cb_h = layout.height[containing_block]
            end
            
            # Position based on offsets
            if !layout.offset_left_auto[i]
                layout.x[i] = cb_x + layout.offset_left[i]
            elseif !layout.offset_right_auto[i]
                layout.x[i] = cb_x + cb_w - layout.width[i] - layout.offset_right[i]
            else
                # Default to parent's content box
                layout.x[i] = cb_x
            end
            
            if !layout.offset_top_auto[i]
                layout.y[i] = cb_y + layout.offset_top[i]
            elseif !layout.offset_bottom_auto[i]
                layout.y[i] = cb_y + cb_h - layout.height[i] - layout.offset_bottom[i]
            else
                layout.y[i] = cb_y
            end
            
        elseif float_type != FLOAT_NONE
            # Float positioning - simplified implementation
            if parent_id == 0
                base_x = layout.margin_left[i]
                base_y = layout.margin_top[i]
                parent_w = n >= 1 ? layout.width[1] : 0.0f0
            else
                base_x = layout.x[parent_id] + layout.padding_left[parent_id]
                base_y = layout.y[parent_id] + layout.padding_top[parent_id]
                parent_w = layout.width[parent_id] - layout.padding_left[parent_id] - layout.padding_right[parent_id]
                
                # Find float position among siblings
                sibling_id = first_children[parent_id]
                left_float_x = base_x
                right_float_x = base_x + parent_w
                y_offset = 0.0f0
                max_float_y = base_y
                
                while sibling_id != 0 && sibling_id != UInt32(i)
                    if layout.display[sibling_id] != DISPLAY_NONE
                        if layout.float_type[sibling_id] == FLOAT_LEFT
                            left_float_x = max(left_float_x, layout.x[sibling_id] + layout.width[sibling_id] + layout.margin_right[sibling_id])
                            max_float_y = max(max_float_y, layout.y[sibling_id])
                        elseif layout.float_type[sibling_id] == FLOAT_RIGHT
                            right_float_x = min(right_float_x, layout.x[sibling_id] - layout.margin_left[sibling_id])
                            max_float_y = max(max_float_y, layout.y[sibling_id])
                        elseif layout.position_type[sibling_id] != POSITION_ABSOLUTE && 
                               layout.position_type[sibling_id] != POSITION_FIXED
                            y_offset += layout.height[sibling_id] + layout.margin_top[sibling_id] + layout.margin_bottom[sibling_id]
                        end
                    end
                    sibling_id = next_siblings[sibling_id]
                end
                
                # Position float
                if float_type == FLOAT_LEFT
                    layout.x[i] = left_float_x + layout.margin_left[i]
                    layout.y[i] = max_float_y + layout.margin_top[i]
                else  # FLOAT_RIGHT
                    layout.x[i] = right_float_x - layout.width[i] - layout.margin_right[i]
                    layout.y[i] = max_float_y + layout.margin_top[i]
                end
            end
            
        elseif pos_type == POSITION_RELATIVE
            # First compute normal flow position
            if parent_id == 0
                base_x = layout.margin_left[i]
                base_y = layout.margin_top[i]
            else
                base_x = layout.x[parent_id] + layout.padding_left[parent_id]
                base_y = layout.y[parent_id] + layout.padding_top[parent_id]
                
                # Find position among siblings
                sibling_id = first_children[parent_id]
                y_offset = 0.0f0
                while sibling_id != 0 && sibling_id != UInt32(i)
                    if layout.position_type[sibling_id] != POSITION_ABSOLUTE && 
                       layout.position_type[sibling_id] != POSITION_FIXED &&
                       layout.float_type[sibling_id] == FLOAT_NONE &&
                       layout.display[sibling_id] != DISPLAY_NONE
                        y_offset += layout.height[sibling_id] + layout.margin_top[sibling_id] + layout.margin_bottom[sibling_id]
                    end
                    sibling_id = next_siblings[sibling_id]
                end
                
                base_x += layout.margin_left[i]
                base_y += y_offset + layout.margin_top[i]
            end
            
            # Apply relative offsets
            if !layout.offset_left_auto[i]
                base_x += layout.offset_left[i]
            elseif !layout.offset_right_auto[i]
                base_x -= layout.offset_right[i]
            end
            
            if !layout.offset_top_auto[i]
                base_y += layout.offset_top[i]
            elseif !layout.offset_bottom_auto[i]
                base_y -= layout.offset_bottom[i]
            end
            
            layout.x[i] = base_x
            layout.y[i] = base_y
            
        else
            # Static positioning (normal flow)
            if parent_id == 0
                layout.x[i] = layout.margin_left[i]
                layout.y[i] = layout.margin_top[i]
            else
                base_x = layout.x[parent_id] + layout.padding_left[parent_id]
                base_y = layout.y[parent_id] + layout.padding_top[parent_id]
                
                # Find position among in-flow siblings, accounting for clear
                sibling_id = first_children[parent_id]
                y_offset = 0.0f0
                max_left_float_bottom = base_y
                max_right_float_bottom = base_y
                
                while sibling_id != 0 && sibling_id != UInt32(i)
                    if layout.display[sibling_id] != DISPLAY_NONE
                        if layout.float_type[sibling_id] == FLOAT_LEFT
                            max_left_float_bottom = max(max_left_float_bottom, layout.y[sibling_id] + layout.height[sibling_id] + layout.margin_bottom[sibling_id])
                        elseif layout.float_type[sibling_id] == FLOAT_RIGHT
                            max_right_float_bottom = max(max_right_float_bottom, layout.y[sibling_id] + layout.height[sibling_id] + layout.margin_bottom[sibling_id])
                        elseif layout.position_type[sibling_id] != POSITION_ABSOLUTE && 
                               layout.position_type[sibling_id] != POSITION_FIXED
                            y_offset += layout.height[sibling_id] + layout.margin_top[sibling_id] + layout.margin_bottom[sibling_id]
                        end
                    end
                    sibling_id = next_siblings[sibling_id]
                end
                
                # Apply clear property
                clear_type = layout.clear_type[i]
                clear_offset = 0.0f0
                if clear_type == CLEAR_LEFT || clear_type == CLEAR_BOTH
                    clear_offset = max(clear_offset, max_left_float_bottom - base_y - y_offset)
                end
                if clear_type == CLEAR_RIGHT || clear_type == CLEAR_BOTH
                    clear_offset = max(clear_offset, max_right_float_bottom - base_y - y_offset)
                end
                
                layout.x[i] = base_x + layout.margin_left[i]
                layout.y[i] = base_y + y_offset + layout.margin_top[i] + max(0.0f0, clear_offset)
            end
        end
        
        layout.dirty[i] = false
    end
end

end # module LayoutArrays
