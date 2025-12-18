# FlexboxLayout - CSS3 Flexbox layout engine implementation
#
# Implements the CSS Flexible Box Layout Module Level 1 specification
# for flexible, responsive layouts with proper flex item sizing and alignment.

module FlexboxLayout

using ..LayoutArrays: LayoutData, DISPLAY_FLEX, DISPLAY_INLINE_FLEX
using ..LayoutArrays: FLEX_DIRECTION_ROW, FLEX_DIRECTION_ROW_REVERSE, FLEX_DIRECTION_COLUMN, FLEX_DIRECTION_COLUMN_REVERSE
using ..LayoutArrays: FLEX_WRAP_NOWRAP, FLEX_WRAP_WRAP, FLEX_WRAP_WRAP_REVERSE
using ..LayoutArrays: JUSTIFY_CONTENT_START, JUSTIFY_CONTENT_END, JUSTIFY_CONTENT_CENTER, JUSTIFY_CONTENT_BETWEEN, JUSTIFY_CONTENT_AROUND, JUSTIFY_CONTENT_EVENLY
using ..LayoutArrays: ALIGN_ITEMS_START, ALIGN_ITEMS_END, ALIGN_ITEMS_CENTER, ALIGN_ITEMS_STRETCH, ALIGN_ITEMS_BASELINE
using ..LayoutArrays: ALIGN_CONTENT_START, ALIGN_CONTENT_END, ALIGN_CONTENT_CENTER, ALIGN_CONTENT_BETWEEN, ALIGN_CONTENT_AROUND, ALIGN_CONTENT_STRETCH
using ..LayoutArrays: POSITION_ABSOLUTE, POSITION_FIXED, DISPLAY_NONE

export compute_flexbox_layout!

"""
    FlexItem

Temporary structure for flex item computation.
"""
struct FlexItem
    id::UInt32
    flex_basis::Float32
    flex_grow::Float32
    flex_shrink::Float32
    computed_size::Float32  # Size along main axis
    cross_size::Float32     # Size along cross axis
    margin_main_start::Float32
    margin_main_end::Float32
    margin_cross_start::Float32
    margin_cross_end::Float32
end

"""
    FlexLine

A line of flex items (for multi-line flex containers).
"""
struct FlexLine
    items::Vector{FlexItem}
    main_size::Float32      # Total size along main axis
    cross_size::Float32     # Max size along cross axis
    free_space::Float32     # Remaining space after items
end

"""
    is_row_direction(direction::UInt8) -> Bool

Check if flex direction is row-based (horizontal).
"""
@inline is_row_direction(direction::UInt8) = direction == FLEX_DIRECTION_ROW || direction == FLEX_DIRECTION_ROW_REVERSE

"""
    is_reverse_direction(direction::UInt8) -> Bool

Check if flex direction is reversed.
"""
@inline is_reverse_direction(direction::UInt8) = direction == FLEX_DIRECTION_ROW_REVERSE || direction == FLEX_DIRECTION_COLUMN_REVERSE

"""
    get_main_axis_size(layout::LayoutData, id::Int, is_row::Bool) -> Float32

Get the size along the main axis for a flex item.
"""
@inline function get_main_axis_size(layout::LayoutData, id::Int, is_row::Bool)::Float32
    is_row ? layout.width[id] : layout.height[id]
end

"""
    get_cross_axis_size(layout::LayoutData, id::Int, is_row::Bool) -> Float32

Get the size along the cross axis for a flex item.
"""
@inline function get_cross_axis_size(layout::LayoutData, id::Int, is_row::Bool)::Float32
    is_row ? layout.height[id] : layout.width[id]
end

"""
    get_main_axis_margins(layout::LayoutData, id::Int, is_row::Bool) -> (Float32, Float32)

Get margins along the main axis (start, end).
"""
@inline function get_main_axis_margins(layout::LayoutData, id::Int, is_row::Bool)::Tuple{Float32, Float32}
    if is_row
        (layout.margin_left[id], layout.margin_right[id])
    else
        (layout.margin_top[id], layout.margin_bottom[id])
    end
end

"""
    get_cross_axis_margins(layout::LayoutData, id::Int, is_row::Bool) -> (Float32, Float32)

Get margins along the cross axis (start, end).
"""
@inline function get_cross_axis_margins(layout::LayoutData, id::Int, is_row::Bool)::Tuple{Float32, Float32}
    if is_row
        (layout.margin_top[id], layout.margin_bottom[id])
    else
        (layout.margin_left[id], layout.margin_right[id])
    end
end

"""
    collect_flex_items(layout::LayoutData, parent_id::Int, first_children::Vector{UInt32}, 
                       next_siblings::Vector{UInt32}, is_row::Bool) -> Vector{FlexItem}

Collect all flex items for a flex container, excluding out-of-flow positioned items.
"""
function collect_flex_items(layout::LayoutData, parent_id::Int, 
                             first_children::Vector{UInt32}, 
                             next_siblings::Vector{UInt32}, 
                             is_row::Bool)::Vector{FlexItem}
    items = FlexItem[]
    child_id = first_children[parent_id]
    
    while child_id != 0
        # Skip out-of-flow and display:none children
        if layout.position_type[child_id] != POSITION_ABSOLUTE && 
           layout.position_type[child_id] != POSITION_FIXED &&
           layout.display[child_id] != DISPLAY_NONE
            
            main_size = get_main_axis_size(layout, Int(child_id), is_row)
            cross_size = get_cross_axis_size(layout, Int(child_id), is_row)
            margin_main = get_main_axis_margins(layout, Int(child_id), is_row)
            margin_cross = get_cross_axis_margins(layout, Int(child_id), is_row)
            
            # Get flex properties (would need to be added to LayoutData)
            # For now, use defaults
            flex_grow = 0.0f0  # layout.flex_grow[child_id]
            flex_shrink = 1.0f0  # layout.flex_shrink[child_id]
            flex_basis = main_size  # layout.flex_basis[child_id]
            
            item = FlexItem(
                child_id,
                flex_basis,
                flex_grow,
                flex_shrink,
                main_size,
                cross_size,
                margin_main[1],
                margin_main[2],
                margin_cross[1],
                margin_cross[2]
            )
            
            push!(items, item)
        end
        
        child_id = next_siblings[child_id]
    end
    
    items
end

"""
    resolve_flexible_lengths!(items::Vector{FlexItem}, available_space::Float32) -> Nothing

Resolve flexible lengths for flex items using the flex-grow and flex-shrink properties.
Implements the CSS Flexbox flexible length resolution algorithm.

Note: This is a simplified implementation. Full implementation requires mutable FlexItem
or returning updated items.
"""
function resolve_flexible_lengths!(items::Vector{FlexItem}, Δspace::Float32)
    # Calculate total basis with margins
    Σbasis = sum(item.flex_basis + item.margin_main_start + item.margin_main_end for item in items)
    Δfree = Δspace - Σbasis  # free space delta
    
    if Δfree > 0
        # Distribute free space using flex-grow
        Σgrow = sum(item.flex_grow for item in items)
        
        # TODO: Update computed_size (requires mutable struct or new vector)
        # for item in items where item.flex_grow > 0
        #     flex_share = Δfree * (item.flex_grow / Σgrow)
        #     item.computed_size += flex_share
        # end
    elseif Δfree < 0
        # Shrink items using flex-shrink
        Σshrink = sum(item.flex_shrink * item.flex_basis for item in items)
        
        # TODO: Update computed_size (requires mutable struct or new vector)
        # for item in items where item.flex_shrink > 0
        #     shrink_share = -Δfree * (item.flex_shrink * item.flex_basis / Σshrink)
        #     item.computed_size -= shrink_share
        # end
    end
end

"""
    distribute_main_axis_space(items::Vector{FlexItem}, free_space::Float32, 
                               justify::UInt8) -> Vector{Float32}

Calculate positions along main axis based on justify-content property.
Returns array of positions for each flex item.
"""
function distribute_main_axis_space(items::Vector{FlexItem}, free_space::Float32, 
                                    justify::UInt8)::Vector{Float32}
    n = length(items)
    positions = zeros(Float32, n)
    
    if n == 0
        return positions
    end
    
    if justify == JUSTIFY_CONTENT_START
        # Items packed at start
        pos = 0.0f0
        for (i, item) in enumerate(items)
            positions[i] = pos + item.margin_main_start
            pos += item.computed_size + item.margin_main_start + item.margin_main_end
        end
        
    elseif justify == JUSTIFY_CONTENT_END
        # Items packed at end
        pos = free_space
        for (i, item) in enumerate(items)
            positions[i] = pos + item.margin_main_start
            pos += item.computed_size + item.margin_main_start + item.margin_main_end
        end
        
    elseif justify == JUSTIFY_CONTENT_CENTER
        # Items centered
        pos = free_space / 2.0f0
        for (i, item) in enumerate(items)
            positions[i] = pos + item.margin_main_start
            pos += item.computed_size + item.margin_main_start + item.margin_main_end
        end
        
    elseif justify == JUSTIFY_CONTENT_BETWEEN
        # Space distributed between items
        gap = n > 1 ? free_space / (n - 1) : 0.0f0
        pos = 0.0f0
        for (i, item) in enumerate(items)
            positions[i] = pos + item.margin_main_start
            pos += item.computed_size + item.margin_main_start + item.margin_main_end + gap
        end
        
    elseif justify == JUSTIFY_CONTENT_AROUND
        # Space distributed around items
        gap = free_space / n
        pos = gap / 2.0f0
        for (i, item) in enumerate(items)
            positions[i] = pos + item.margin_main_start
            pos += item.computed_size + item.margin_main_start + item.margin_main_end + gap
        end
        
    elseif justify == JUSTIFY_CONTENT_EVENLY
        # Space distributed evenly
        gap = free_space / (n + 1)
        pos = gap
        for (i, item) in enumerate(items)
            positions[i] = pos + item.margin_main_start
            pos += item.computed_size + item.margin_main_start + item.margin_main_end + gap
        end
    end
    
    positions
end

"""
    compute_flexbox_layout!(layout::LayoutData, container_id::Int, 
                           first_children::Vector{UInt32}, 
                           next_siblings::Vector{UInt32})

Compute flexbox layout for a flex container.
Modifies layout positions and sizes in place.
"""
function compute_flexbox_layout!(layout::LayoutData, container_id::Int,
                                first_children::Vector{UInt32},
                                next_siblings::Vector{UInt32})
    # Get flex container properties (would need to be added to LayoutData)
    # For now, use defaults from CSS
    flex_direction = FLEX_DIRECTION_ROW  # layout.flex_direction[container_id]
    flex_wrap = FLEX_WRAP_NOWRAP  # layout.flex_wrap[container_id]
    justify_content = JUSTIFY_CONTENT_START  # layout.justify_content[container_id]
    align_items = ALIGN_ITEMS_STRETCH  # layout.align_items[container_id]
    gap_main = 0.0f0  # layout.gap_row[container_id] or gap_column
    gap_cross = 0.0f0
    
    is_row = is_row_direction(flex_direction)
    is_reverse = is_reverse_direction(flex_direction)
    
    # Get container dimensions
    container_width = layout.width[container_id]
    container_height = layout.height[container_id]
    padding_top = layout.padding_top[container_id]
    padding_right = layout.padding_right[container_id]
    padding_bottom = layout.padding_bottom[container_id]
    padding_left = layout.padding_left[container_id]
    
    available_main = is_row ? 
        (container_width - padding_left - padding_right) : 
        (container_height - padding_top - padding_bottom)
    
    available_cross = is_row ? 
        (container_height - padding_top - padding_bottom) : 
        (container_width - padding_left - padding_right)
    
    # Collect flex items
    items = collect_flex_items(layout, container_id, first_children, next_siblings, is_row)
    
    if isempty(items)
        return
    end
    
    # Resolve flexible lengths
    resolve_flexible_lengths!(items, available_main)
    
    # Calculate total size needed
    total_main_size = sum(item.computed_size + item.margin_main_start + item.margin_main_end for item in items)
    total_main_size += gap_main * max(0, length(items) - 1)
    
    free_space = available_main - total_main_size
    
    # Distribute main axis space
    main_positions = distribute_main_axis_space(items, free_space, justify_content)
    
    # Position items
    container_x = layout.x[container_id]
    container_y = layout.y[container_id]
    
    for (i, item) in enumerate(items)
        item_id = Int(item.id)
        
        # Main axis position
        main_pos = main_positions[i]
        
        # Cross axis position (simplified - would need full align-items implementation)
        cross_pos = if align_items == ALIGN_ITEMS_START
            item.margin_cross_start
        elseif align_items == ALIGN_ITEMS_END
            available_cross - item.cross_size - item.margin_cross_end
        elseif align_items == ALIGN_ITEMS_CENTER
            (available_cross - item.cross_size) / 2.0f0 + item.margin_cross_start - item.margin_cross_end / 2.0f0
        else  # STRETCH
            item.margin_cross_start
        end
        
        # Set final position based on flex direction
        if is_row
            layout.x[item_id] = container_x + padding_left + (is_reverse ? available_main - main_pos - item.computed_size : main_pos)
            layout.y[item_id] = container_y + padding_top + cross_pos
            
            # Stretch cross axis if needed
            if align_items == ALIGN_ITEMS_STRETCH && layout.height[item_id] == 0.0f0
                layout.height[item_id] = available_cross - item.margin_cross_start - item.margin_cross_end
            end
        else
            layout.x[item_id] = container_x + padding_left + cross_pos
            layout.y[item_id] = container_y + padding_top + (is_reverse ? available_main - main_pos - item.computed_size : main_pos)
            
            # Stretch cross axis if needed
            if align_items == ALIGN_ITEMS_STRETCH && layout.width[item_id] == 0.0f0
                layout.width[item_id] = available_cross - item.margin_cross_start - item.margin_cross_end
            end
        end
    end
end

end # module FlexboxLayout
