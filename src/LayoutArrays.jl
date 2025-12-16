"""
    LayoutArrays

SIMD-friendly layout computation using contiguous float arrays.

Layout data is stored in Structure of Arrays format, enabling
vectorized computation across multiple nodes simultaneously.
"""
module LayoutArrays

export LayoutData, resize_layout!, set_bounds!, get_bounds, set_position!, get_position, compute_layout!

"""
    LayoutData

Contiguous arrays for layout computation, designed for SIMD/AVX operations.

Each node's layout is stored at the corresponding index in each array.
All arrays are pre-allocated and resized together.

# Fields
- `x::Vector{Float32}` - X position
- `y::Vector{Float32}` - Y position  
- `width::Vector{Float32}` - Computed width
- `height::Vector{Float32}` - Computed height
- `content_width::Vector{Float32}` - Content area width
- `content_height::Vector{Float32}` - Content area height
- `margin_top::Vector{Float32}` - Top margin
- `margin_right::Vector{Float32}` - Right margin
- `margin_bottom::Vector{Float32}` - Bottom margin
- `margin_left::Vector{Float32}` - Left margin
- `padding_top::Vector{Float32}` - Top padding
- `padding_right::Vector{Float32}` - Right padding
- `padding_bottom::Vector{Float32}` - Bottom padding
- `padding_left::Vector{Float32}` - Left padding
- `display::Vector{UInt8}` - Display type (0=none, 1=block, 2=inline, 3=flex, 4=grid)
- `dirty::Vector{Bool}` - Layout needs recomputation
"""
mutable struct LayoutData
    x::Vector{Float32}
    y::Vector{Float32}
    width::Vector{Float32}
    height::Vector{Float32}
    content_width::Vector{Float32}
    content_height::Vector{Float32}
    margin_top::Vector{Float32}
    margin_right::Vector{Float32}
    margin_bottom::Vector{Float32}
    margin_left::Vector{Float32}
    padding_top::Vector{Float32}
    padding_right::Vector{Float32}
    padding_bottom::Vector{Float32}
    padding_left::Vector{Float32}
    display::Vector{UInt8}
    dirty::Vector{Bool}
    
    function LayoutData(capacity::Int = 0)
        new(
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{UInt8}(undef, capacity),
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
    resize!(layout.display, new_size)
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
        layout.display[i] = 0x01  # Default to block
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
    compute_layout!(layout::LayoutData, parents::Vector{UInt32}, 
                    first_children::Vector{UInt32}, next_siblings::Vector{UInt32})

Compute layout for all dirty nodes using flat loop iteration.

This implementation uses contiguous array access patterns suitable for
SIMD/AVX vectorization by the Julia compiler.

# Arguments
- `layout::LayoutData` - Layout data arrays
- `parents::Vector{UInt32}` - Parent node IDs from DOM table
- `first_children::Vector{UInt32}` - First child IDs from DOM table
- `next_siblings::Vector{UInt32}` - Next sibling IDs from DOM table
"""
function compute_layout!(layout::LayoutData, parents::Vector{UInt32}, 
                         first_children::Vector{UInt32}, next_siblings::Vector{UInt32})
    n = length(layout.x)
    if n == 0
        return
    end
    
    # First pass: compute content sizes (bottom-up)
    # This is a simplified block layout algorithm
    @inbounds for i in n:-1:1
        if !layout.dirty[i]
            continue
        end
        
        # Calculate content size from children
        child_id = first_children[i]
        total_height = 0.0f0
        max_width = 0.0f0
        
        while child_id != 0
            child_h = layout.height[child_id] + layout.margin_top[child_id] + layout.margin_bottom[child_id]
            child_w = layout.width[child_id] + layout.margin_left[child_id] + layout.margin_right[child_id]
            total_height += child_h
            max_width = max(max_width, child_w)
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
        
        parent_id = parents[i]
        if parent_id == 0
            # Root node positioning
            layout.x[i] = layout.margin_left[i]
            layout.y[i] = layout.margin_top[i]
        else
            # Position relative to parent
            base_x = layout.x[parent_id] + layout.padding_left[parent_id]
            base_y = layout.y[parent_id] + layout.padding_top[parent_id]
            
            # Find position among siblings (simplified block layout)
            sibling_id = first_children[parent_id]
            y_offset = 0.0f0
            while sibling_id != 0 && sibling_id != i
                y_offset += layout.height[sibling_id] + layout.margin_top[sibling_id] + layout.margin_bottom[sibling_id]
                sibling_id = next_siblings[sibling_id]
            end
            
            layout.x[i] = base_x + layout.margin_left[i]
            layout.y[i] = base_y + y_offset + layout.margin_top[i]
        end
        
        layout.dirty[i] = false
    end
end

end # module LayoutArrays
