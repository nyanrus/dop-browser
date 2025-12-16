"""
    LayoutArrays

SIMD-friendly layout computation using contiguous float arrays.

Layout data is stored in Structure of Arrays format, enabling
vectorized computation across multiple nodes simultaneously.
"""
module LayoutArrays

export LayoutData, resize_layout!, set_bounds!, get_bounds, set_position!, get_position, compute_layout!
export set_css_position!, set_offsets!, set_margins!, set_paddings!, set_overflow!, set_visibility!, set_z_index!
export set_background_color!, get_background_color, set_borders!, has_border

# Position types (matching CSSParser)
const POSITION_STATIC = UInt8(0)
const POSITION_RELATIVE = UInt8(1)
const POSITION_ABSOLUTE = UInt8(2)
const POSITION_FIXED = UInt8(3)

# Overflow types
const OVERFLOW_VISIBLE = UInt8(0)
const OVERFLOW_HIDDEN = UInt8(1)

# Display types
const DISPLAY_NONE = UInt8(0)
const DISPLAY_BLOCK = UInt8(1)
const DISPLAY_INLINE = UInt8(2)

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
mutable struct LayoutData
    # Position & dimensions
    x::Vector{Float32}
    y::Vector{Float32}
    width::Vector{Float32}
    height::Vector{Float32}
    content_width::Vector{Float32}
    content_height::Vector{Float32}
    
    # Box model - margin (offset in Content-- terms)
    margin_top::Vector{Float32}
    margin_right::Vector{Float32}
    margin_bottom::Vector{Float32}
    margin_left::Vector{Float32}
    
    # Box model - padding (inset in Content-- terms)
    padding_top::Vector{Float32}
    padding_right::Vector{Float32}
    padding_bottom::Vector{Float32}
    padding_left::Vector{Float32}
    
    # Box model - border (stroke in Content-- terms)
    border_top_width::Vector{Float32}
    border_right_width::Vector{Float32}
    border_bottom_width::Vector{Float32}
    border_left_width::Vector{Float32}
    border_top_style::Vector{UInt8}
    border_right_style::Vector{UInt8}
    border_bottom_style::Vector{UInt8}
    border_left_style::Vector{UInt8}
    border_top_r::Vector{UInt8}
    border_top_g::Vector{UInt8}
    border_top_b::Vector{UInt8}
    border_top_a::Vector{UInt8}
    border_right_r::Vector{UInt8}
    border_right_g::Vector{UInt8}
    border_right_b::Vector{UInt8}
    border_right_a::Vector{UInt8}
    border_bottom_r::Vector{UInt8}
    border_bottom_g::Vector{UInt8}
    border_bottom_b::Vector{UInt8}
    border_bottom_a::Vector{UInt8}
    border_left_r::Vector{UInt8}
    border_left_g::Vector{UInt8}
    border_left_b::Vector{UInt8}
    border_left_a::Vector{UInt8}
    
    # CSS positioning
    position_type::Vector{UInt8}  # POSITION_*
    offset_top::Vector{Float32}
    offset_right::Vector{Float32}
    offset_bottom::Vector{Float32}
    offset_left::Vector{Float32}
    offset_top_auto::Vector{Bool}
    offset_right_auto::Vector{Bool}
    offset_bottom_auto::Vector{Bool}
    offset_left_auto::Vector{Bool}
    z_index::Vector{Int32}
    
    # Display & visibility
    display::Vector{UInt8}
    visibility::Vector{Bool}
    overflow::Vector{UInt8}
    
    # Colors (RGBA 0-255)
    bg_r::Vector{UInt8}
    bg_g::Vector{UInt8}
    bg_b::Vector{UInt8}
    bg_a::Vector{UInt8}
    has_background::Vector{Bool}
    
    dirty::Vector{Bool}
    
    function LayoutData(capacity::Int = 0)
        new(
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            # margin
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            # padding
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            # border widths
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            # border styles
            Vector{UInt8}(undef, capacity),
            Vector{UInt8}(undef, capacity),
            Vector{UInt8}(undef, capacity),
            Vector{UInt8}(undef, capacity),
            # border top color
            Vector{UInt8}(undef, capacity),
            Vector{UInt8}(undef, capacity),
            Vector{UInt8}(undef, capacity),
            Vector{UInt8}(undef, capacity),
            # border right color
            Vector{UInt8}(undef, capacity),
            Vector{UInt8}(undef, capacity),
            Vector{UInt8}(undef, capacity),
            Vector{UInt8}(undef, capacity),
            # border bottom color
            Vector{UInt8}(undef, capacity),
            Vector{UInt8}(undef, capacity),
            Vector{UInt8}(undef, capacity),
            Vector{UInt8}(undef, capacity),
            # border left color
            Vector{UInt8}(undef, capacity),
            Vector{UInt8}(undef, capacity),
            Vector{UInt8}(undef, capacity),
            Vector{UInt8}(undef, capacity),
            # positioning
            Vector{UInt8}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Bool}(undef, capacity),
            Vector{Bool}(undef, capacity),
            Vector{Bool}(undef, capacity),
            Vector{Bool}(undef, capacity),
            Vector{Int32}(undef, capacity),
            # display
            Vector{UInt8}(undef, capacity),
            Vector{Bool}(undef, capacity),
            Vector{UInt8}(undef, capacity),
            # colors
            Vector{UInt8}(undef, capacity),
            Vector{UInt8}(undef, capacity),
            Vector{UInt8}(undef, capacity),
            Vector{UInt8}(undef, capacity),
            Vector{Bool}(undef, capacity),
            Vector{Bool}(undef, capacity)
        )
    end
end

"""
    resize_layout!(layout::LayoutData, new_size::Int)

Resize all layout arrays to accommodate `new_size` nodes.
New entries are zero-initialized.
"""
function resize_layout!(layout::LayoutData, new_size::Int)
    old_size = length(layout.x)
    
    resize!(layout.x, new_size)
    resize!(layout.y, new_size)
    resize!(layout.width, new_size)
    resize!(layout.height, new_size)
    resize!(layout.content_width, new_size)
    resize!(layout.content_height, new_size)
    resize!(layout.margin_top, new_size)
    resize!(layout.margin_right, new_size)
    resize!(layout.margin_bottom, new_size)
    resize!(layout.margin_left, new_size)
    resize!(layout.padding_top, new_size)
    resize!(layout.padding_right, new_size)
    resize!(layout.padding_bottom, new_size)
    resize!(layout.padding_left, new_size)
    # Border widths
    resize!(layout.border_top_width, new_size)
    resize!(layout.border_right_width, new_size)
    resize!(layout.border_bottom_width, new_size)
    resize!(layout.border_left_width, new_size)
    # Border styles
    resize!(layout.border_top_style, new_size)
    resize!(layout.border_right_style, new_size)
    resize!(layout.border_bottom_style, new_size)
    resize!(layout.border_left_style, new_size)
    # Border colors
    resize!(layout.border_top_r, new_size)
    resize!(layout.border_top_g, new_size)
    resize!(layout.border_top_b, new_size)
    resize!(layout.border_top_a, new_size)
    resize!(layout.border_right_r, new_size)
    resize!(layout.border_right_g, new_size)
    resize!(layout.border_right_b, new_size)
    resize!(layout.border_right_a, new_size)
    resize!(layout.border_bottom_r, new_size)
    resize!(layout.border_bottom_g, new_size)
    resize!(layout.border_bottom_b, new_size)
    resize!(layout.border_bottom_a, new_size)
    resize!(layout.border_left_r, new_size)
    resize!(layout.border_left_g, new_size)
    resize!(layout.border_left_b, new_size)
    resize!(layout.border_left_a, new_size)
    # Positioning
    resize!(layout.position_type, new_size)
    resize!(layout.offset_top, new_size)
    resize!(layout.offset_right, new_size)
    resize!(layout.offset_bottom, new_size)
    resize!(layout.offset_left, new_size)
    resize!(layout.offset_top_auto, new_size)
    resize!(layout.offset_right_auto, new_size)
    resize!(layout.offset_bottom_auto, new_size)
    resize!(layout.offset_left_auto, new_size)
    resize!(layout.z_index, new_size)
    resize!(layout.display, new_size)
    resize!(layout.visibility, new_size)
    resize!(layout.overflow, new_size)
    resize!(layout.bg_r, new_size)
    resize!(layout.bg_g, new_size)
    resize!(layout.bg_b, new_size)
    resize!(layout.bg_a, new_size)
    resize!(layout.has_background, new_size)
    resize!(layout.dirty, new_size)
    
    # Zero-initialize new entries
    for i in (old_size + 1):new_size
        layout.x[i] = 0.0f0
        layout.y[i] = 0.0f0
        layout.width[i] = 0.0f0
        layout.height[i] = 0.0f0
        layout.content_width[i] = 0.0f0
        layout.content_height[i] = 0.0f0
        layout.margin_top[i] = 0.0f0
        layout.margin_right[i] = 0.0f0
        layout.margin_bottom[i] = 0.0f0
        layout.margin_left[i] = 0.0f0
        layout.padding_top[i] = 0.0f0
        layout.padding_right[i] = 0.0f0
        layout.padding_bottom[i] = 0.0f0
        layout.padding_left[i] = 0.0f0
        # Border widths
        layout.border_top_width[i] = 0.0f0
        layout.border_right_width[i] = 0.0f0
        layout.border_bottom_width[i] = 0.0f0
        layout.border_left_width[i] = 0.0f0
        # Border styles (0 = none)
        layout.border_top_style[i] = 0x00
        layout.border_right_style[i] = 0x00
        layout.border_bottom_style[i] = 0x00
        layout.border_left_style[i] = 0x00
        # Border colors (black by default)
        layout.border_top_r[i] = 0x00
        layout.border_top_g[i] = 0x00
        layout.border_top_b[i] = 0x00
        layout.border_top_a[i] = 0x00
        layout.border_right_r[i] = 0x00
        layout.border_right_g[i] = 0x00
        layout.border_right_b[i] = 0x00
        layout.border_right_a[i] = 0x00
        layout.border_bottom_r[i] = 0x00
        layout.border_bottom_g[i] = 0x00
        layout.border_bottom_b[i] = 0x00
        layout.border_bottom_a[i] = 0x00
        layout.border_left_r[i] = 0x00
        layout.border_left_g[i] = 0x00
        layout.border_left_b[i] = 0x00
        layout.border_left_a[i] = 0x00
        # Positioning
        layout.position_type[i] = POSITION_STATIC
        layout.offset_top[i] = 0.0f0
        layout.offset_right[i] = 0.0f0
        layout.offset_bottom[i] = 0.0f0
        layout.offset_left[i] = 0.0f0
        layout.offset_top_auto[i] = true
        layout.offset_right_auto[i] = true
        layout.offset_bottom_auto[i] = true
        layout.offset_left_auto[i] = true
        layout.z_index[i] = Int32(0)
        layout.display[i] = DISPLAY_BLOCK
        layout.visibility[i] = true
        layout.overflow[i] = OVERFLOW_VISIBLE
        layout.bg_r[i] = 0xff
        layout.bg_g[i] = 0xff
        layout.bg_b[i] = 0xff
        layout.bg_a[i] = 0x00  # transparent
        layout.has_background[i] = false
        layout.dirty[i] = true
    end
    
    return layout
end

"""
    set_bounds!(layout::LayoutData, id::Int, width::Float32, height::Float32)

Set the width and height for a node.
"""
function set_bounds!(layout::LayoutData, id::Int, width::Float32, height::Float32)
    if id >= 1 && id <= length(layout.width)
        layout.width[id] = width
        layout.height[id] = height
        layout.dirty[id] = true
    end
end

"""
    get_bounds(layout::LayoutData, id::Int) -> Tuple{Float32, Float32}

Get the width and height for a node.
"""
function get_bounds(layout::LayoutData, id::Int)::Tuple{Float32, Float32}
    if id >= 1 && id <= length(layout.width)
        return (layout.width[id], layout.height[id])
    end
    return (0.0f0, 0.0f0)
end

"""
    set_position!(layout::LayoutData, id::Int, x::Float32, y::Float32)

Set the position for a node.
"""
function set_position!(layout::LayoutData, id::Int, x::Float32, y::Float32)
    if id >= 1 && id <= length(layout.x)
        layout.x[id] = x
        layout.y[id] = y
    end
end

"""
    get_position(layout::LayoutData, id::Int) -> Tuple{Float32, Float32}

Get the position for a node.
"""
function get_position(layout::LayoutData, id::Int)::Tuple{Float32, Float32}
    if id >= 1 && id <= length(layout.x)
        return (layout.x[id], layout.y[id])
    end
    return (0.0f0, 0.0f0)
end

"""
    set_css_position!(layout::LayoutData, id::Int, pos_type::UInt8)

Set the CSS position type for a node.
"""
function set_css_position!(layout::LayoutData, id::Int, pos_type::UInt8)
    if id >= 1 && id <= length(layout.position_type)
        layout.position_type[id] = pos_type
        layout.dirty[id] = true
    end
end

"""
    set_offsets!(layout::LayoutData, id::Int; top::Float32=0.0f0, right::Float32=0.0f0, 
                 bottom::Float32=0.0f0, left::Float32=0.0f0,
                 top_auto::Bool=true, right_auto::Bool=true, 
                 bottom_auto::Bool=true, left_auto::Bool=true)

Set CSS offset properties (top, right, bottom, left) for positioned elements.
"""
function set_offsets!(layout::LayoutData, id::Int; 
                      top::Float32=0.0f0, right::Float32=0.0f0, 
                      bottom::Float32=0.0f0, left::Float32=0.0f0,
                      top_auto::Bool=true, right_auto::Bool=true, 
                      bottom_auto::Bool=true, left_auto::Bool=true)
    if id >= 1 && id <= length(layout.offset_top)
        layout.offset_top[id] = top
        layout.offset_right[id] = right
        layout.offset_bottom[id] = bottom
        layout.offset_left[id] = left
        layout.offset_top_auto[id] = top_auto
        layout.offset_right_auto[id] = right_auto
        layout.offset_bottom_auto[id] = bottom_auto
        layout.offset_left_auto[id] = left_auto
        layout.dirty[id] = true
    end
end

"""
    set_margins!(layout::LayoutData, id::Int; top::Float32=0.0f0, right::Float32=0.0f0, 
                 bottom::Float32=0.0f0, left::Float32=0.0f0)

Set margin values for a node.
"""
function set_margins!(layout::LayoutData, id::Int; 
                      top::Float32=0.0f0, right::Float32=0.0f0, 
                      bottom::Float32=0.0f0, left::Float32=0.0f0)
    if id >= 1 && id <= length(layout.margin_top)
        layout.margin_top[id] = top
        layout.margin_right[id] = right
        layout.margin_bottom[id] = bottom
        layout.margin_left[id] = left
        layout.dirty[id] = true
    end
end

"""
    set_paddings!(layout::LayoutData, id::Int; top::Float32=0.0f0, right::Float32=0.0f0, 
                  bottom::Float32=0.0f0, left::Float32=0.0f0)

Set padding values for a node.
"""
function set_paddings!(layout::LayoutData, id::Int; 
                       top::Float32=0.0f0, right::Float32=0.0f0, 
                       bottom::Float32=0.0f0, left::Float32=0.0f0)
    if id >= 1 && id <= length(layout.padding_top)
        layout.padding_top[id] = top
        layout.padding_right[id] = right
        layout.padding_bottom[id] = bottom
        layout.padding_left[id] = left
        layout.dirty[id] = true
    end
end

"""
    set_overflow!(layout::LayoutData, id::Int, overflow::UInt8)

Set overflow behavior for a node.
"""
function set_overflow!(layout::LayoutData, id::Int, overflow::UInt8)
    if id >= 1 && id <= length(layout.overflow)
        layout.overflow[id] = overflow
    end
end

"""
    set_visibility!(layout::LayoutData, id::Int, visible::Bool)

Set visibility for a node.
"""
function set_visibility!(layout::LayoutData, id::Int, visible::Bool)
    if id >= 1 && id <= length(layout.visibility)
        layout.visibility[id] = visible
    end
end

"""
    set_z_index!(layout::LayoutData, id::Int, z::Int32)

Set z-index for a node.
"""
function set_z_index!(layout::LayoutData, id::Int, z::Int32)
    if id >= 1 && id <= length(layout.z_index)
        layout.z_index[id] = z
    end
end

"""
    set_background_color!(layout::LayoutData, id::Int, r::UInt8, g::UInt8, b::UInt8, a::UInt8)

Set background color for a node.
"""
function set_background_color!(layout::LayoutData, id::Int, r::UInt8, g::UInt8, b::UInt8, a::UInt8)
    if id >= 1 && id <= length(layout.bg_r)
        layout.bg_r[id] = r
        layout.bg_g[id] = g
        layout.bg_b[id] = b
        layout.bg_a[id] = a
        layout.has_background[id] = a > 0
    end
end

"""
    get_background_color(layout::LayoutData, id::Int) -> Tuple{UInt8, UInt8, UInt8, UInt8}

Get background color for a node.
"""
function get_background_color(layout::LayoutData, id::Int)::Tuple{UInt8, UInt8, UInt8, UInt8}
    if id >= 1 && id <= length(layout.bg_r)
        return (layout.bg_r[id], layout.bg_g[id], layout.bg_b[id], layout.bg_a[id])
    end
    return (0x00, 0x00, 0x00, 0x00)
end

"""
    set_borders!(layout::LayoutData, id::Int;
                 top_width::Float32=0.0f0, right_width::Float32=0.0f0,
                 bottom_width::Float32=0.0f0, left_width::Float32=0.0f0,
                 top_style::UInt8=0x00, right_style::UInt8=0x00,
                 bottom_style::UInt8=0x00, left_style::UInt8=0x00,
                 top_r::UInt8=0x00, top_g::UInt8=0x00, top_b::UInt8=0x00, top_a::UInt8=0x00,
                 right_r::UInt8=0x00, right_g::UInt8=0x00, right_b::UInt8=0x00, right_a::UInt8=0x00,
                 bottom_r::UInt8=0x00, bottom_g::UInt8=0x00, bottom_b::UInt8=0x00, bottom_a::UInt8=0x00,
                 left_r::UInt8=0x00, left_g::UInt8=0x00, left_b::UInt8=0x00, left_a::UInt8=0x00)

Set border (stroke) properties for a node.

Content-- semantic mapping:
- CSS border → Content-- stroke
- Border defines the visual boundary of a node

# Arguments
- `layout::LayoutData` - Layout data structure
- `id::Int` - Node ID
- `*_width` - Border width per side in device pixels
- `*_style` - Border style per side (0=none, 1=solid, 2=dotted, 3=dashed)
- `*_r/g/b/a` - Border color per side (RGBA 0-255)
"""
function set_borders!(layout::LayoutData, id::Int;
                      top_width::Float32=0.0f0, right_width::Float32=0.0f0,
                      bottom_width::Float32=0.0f0, left_width::Float32=0.0f0,
                      top_style::UInt8=0x00, right_style::UInt8=0x00,
                      bottom_style::UInt8=0x00, left_style::UInt8=0x00,
                      top_r::UInt8=0x00, top_g::UInt8=0x00, top_b::UInt8=0x00, top_a::UInt8=0x00,
                      right_r::UInt8=0x00, right_g::UInt8=0x00, right_b::UInt8=0x00, right_a::UInt8=0x00,
                      bottom_r::UInt8=0x00, bottom_g::UInt8=0x00, bottom_b::UInt8=0x00, bottom_a::UInt8=0x00,
                      left_r::UInt8=0x00, left_g::UInt8=0x00, left_b::UInt8=0x00, left_a::UInt8=0x00)
    if id < 1 || id > length(layout.border_top_width)
        return
    end
    
    # Widths
    layout.border_top_width[id] = top_width
    layout.border_right_width[id] = right_width
    layout.border_bottom_width[id] = bottom_width
    layout.border_left_width[id] = left_width
    
    # Styles
    layout.border_top_style[id] = top_style
    layout.border_right_style[id] = right_style
    layout.border_bottom_style[id] = bottom_style
    layout.border_left_style[id] = left_style
    
    # Top color
    layout.border_top_r[id] = top_r
    layout.border_top_g[id] = top_g
    layout.border_top_b[id] = top_b
    layout.border_top_a[id] = top_a
    
    # Right color
    layout.border_right_r[id] = right_r
    layout.border_right_g[id] = right_g
    layout.border_right_b[id] = right_b
    layout.border_right_a[id] = right_a
    
    # Bottom color
    layout.border_bottom_r[id] = bottom_r
    layout.border_bottom_g[id] = bottom_g
    layout.border_bottom_b[id] = bottom_b
    layout.border_bottom_a[id] = bottom_a
    
    # Left color
    layout.border_left_r[id] = left_r
    layout.border_left_g[id] = left_g
    layout.border_left_b[id] = left_b
    layout.border_left_a[id] = left_a
end

"""
    has_border(layout::LayoutData, id::Int) -> Bool

Check if a node has any visible border.
A border side is visible if width > 0, style != none (0), and alpha > 0.
"""
function has_border(layout::LayoutData, id::Int)::Bool
    if id < 1 || id > length(layout.border_top_width)
        return false
    end
    
    # Helper to check if a single border side is visible
    is_side_visible(width, style, alpha) = width > 0 && style != 0 && alpha > 0
    
    # Check if any side has a visible border
    return is_side_visible(layout.border_top_width[id], layout.border_top_style[id], layout.border_top_a[id]) ||
           is_side_visible(layout.border_right_width[id], layout.border_right_style[id], layout.border_right_a[id]) ||
           is_side_visible(layout.border_bottom_width[id], layout.border_bottom_style[id], layout.border_bottom_a[id]) ||
           is_side_visible(layout.border_left_width[id], layout.border_left_style[id], layout.border_left_a[id])
end

"""
    find_containing_block(layout::LayoutData, parents::Vector{UInt32}, node_id::Int) -> Int

Find the containing block for a positioned element.
For absolute positioning, this is the nearest ancestor with position != static.
Returns 0 if no such ancestor exists (use viewport).
"""
function find_containing_block(layout::LayoutData, parents::Vector{UInt32}, node_id::Int)::Int
    parent_id = Int(parents[node_id])
    while parent_id != 0
        if layout.position_type[parent_id] != POSITION_STATIC
            return parent_id
        end
        parent_id = Int(parents[parent_id])
    end
    return 0  # Use viewport
end

"""
    compute_layout!(layout::LayoutData, parents::Vector{UInt32}, 
                    first_children::Vector{UInt32}, next_siblings::Vector{UInt32})

Compute layout for all dirty nodes using flat loop iteration.

This implementation uses contiguous array access patterns suitable for
SIMD/AVX vectorization by the Julia compiler. Supports CSS positioning.
"""
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
        
        while child_id != 0
            # Skip out-of-flow children (absolute/fixed positioned)
            if layout.position_type[child_id] != POSITION_ABSOLUTE && 
               layout.position_type[child_id] != POSITION_FIXED &&
               layout.display[child_id] != DISPLAY_NONE
                child_h = layout.height[child_id] + layout.margin_top[child_id] + layout.margin_bottom[child_id]
                child_w = layout.width[child_id] + layout.margin_left[child_id] + layout.margin_right[child_id]
                total_height += child_h
                max_width = max(max_width, child_w)
            end
            child_id = next_siblings[child_id]
        end
        
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
    
    # Second pass: compute positions (top-down)
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
                
                # Find position among in-flow siblings
                sibling_id = first_children[parent_id]
                y_offset = 0.0f0
                while sibling_id != 0 && sibling_id != UInt32(i)
                    if layout.position_type[sibling_id] != POSITION_ABSOLUTE && 
                       layout.position_type[sibling_id] != POSITION_FIXED &&
                       layout.display[sibling_id] != DISPLAY_NONE
                        y_offset += layout.height[sibling_id] + layout.margin_top[sibling_id] + layout.margin_bottom[sibling_id]
                    end
                    sibling_id = next_siblings[sibling_id]
                end
                
                layout.x[i] = base_x + layout.margin_left[i]
                layout.y[i] = base_y + y_offset + layout.margin_top[i]
            end
        end
        
        layout.dirty[i] = false
    end
end

end # module LayoutArrays
