# GridLayout - CSS3 Grid layout engine implementation
#
# Implements the CSS Grid Layout Module Level 1 specification
# for two-dimensional grid-based layouts.

module GridLayout

using ..LayoutArrays: LayoutData, DISPLAY_GRID, DISPLAY_INLINE_GRID
using ..LayoutArrays: POSITION_ABSOLUTE, POSITION_FIXED, DISPLAY_NONE
using ..LayoutArrays: JUSTIFY_CONTENT_START, JUSTIFY_CONTENT_END, JUSTIFY_CONTENT_CENTER, JUSTIFY_CONTENT_BETWEEN, JUSTIFY_CONTENT_AROUND, JUSTIFY_CONTENT_EVENLY
using ..LayoutArrays: ALIGN_ITEMS_START, ALIGN_ITEMS_END, ALIGN_ITEMS_CENTER, ALIGN_ITEMS_STRETCH

export compute_grid_layout!

"""
    GridTrack

Represents a grid track (column or row).
"""
mutable struct GridTrack
    size::Float32           # Resolved size
    is_flexible::Bool       # Is this a fr unit track?
    flex_factor::Float32    # The fr value (e.g., 2.0 for 2fr)
    min_size::Float32       # Minimum size
    max_size::Float32       # Maximum size
end

"""
    GridItem

Represents an item placed in the grid.
"""
struct GridItem
    id::UInt32
    column_start::Int32
    column_end::Int32
    row_start::Int32
    row_end::Int32
    width::Float32
    height::Float32
end

"""
    GridDefinition

Grid container definition.
"""
struct GridDefinition
    columns::Vector{GridTrack}
    rows::Vector{GridTrack}
    gap_column::Float32
    gap_row::Float32
    auto_flow_row::Bool  # true for row, false for column
    auto_flow_dense::Bool
end

"""
    parse_grid_template(template_str::String) -> Vector{GridTrack}

Parse a grid template string into track definitions.
Simplified implementation supporting: auto, px values, fr units.

Example: "100px 1fr 2fr" → [GridTrack(100, false), GridTrack(0, true, 1), GridTrack(0, true, 2)]
"""
function parse_grid_template(template_str::String)::Vector{GridTrack}
    tracks = GridTrack[]
    parts = split(strip(template_str))
    
    for part in parts
        part_str = String(part)
        if part_str == "auto"
            push!(tracks, GridTrack(0.0f0, false, 0.0f0, 0.0f0, Inf32))
        elseif endswith(part_str, "px")
            px_val = parse(Float32, part_str[1:end-2])
            push!(tracks, GridTrack(px_val, false, 0.0f0, px_val, px_val))
        elseif endswith(part_str, "fr")
            fr_val = parse(Float32, part_str[1:end-2])
            push!(tracks, GridTrack(0.0f0, true, fr_val, 0.0f0, Inf32))
        else
            # Try to parse as px value without unit
            try
                px_val = parse(Float32, part_str)
                push!(tracks, GridTrack(px_val, false, 0.0f0, px_val, px_val))
            catch
                # Unknown format, treat as auto
                push!(tracks, GridTrack(0.0f0, false, 0.0f0, 0.0f0, Inf32))
            end
        end
    end
    
    # Default to single auto track if empty
    if isempty(tracks)
        push!(tracks, GridTrack(0.0f0, false, 0.0f0, 0.0f0, Inf32))
    end
    
    tracks
end

"""
    create_default_grid(rows::Int, cols::Int) -> GridDefinition

Create a default grid with specified number of rows and columns.
"""
function create_default_grid(rows::Int, cols::Int)::GridDefinition
    # Create auto-sized tracks
    columns = [GridTrack(0.0f0, false, 0.0f0, 0.0f0, Inf32) for _ in 1:cols]
    row_tracks = [GridTrack(0.0f0, false, 0.0f0, 0.0f0, Inf32) for _ in 1:rows]
    
    GridDefinition(columns, row_tracks, 0.0f0, 0.0f0, true, false)
end

"""
    collect_grid_items(layout::LayoutData, parent_id::Int,
                       first_children::Vector{UInt32},
                       next_siblings::Vector{UInt32}) -> Vector{GridItem}

Collect all grid items from a grid container.
"""
function collect_grid_items(layout::LayoutData, parent_id::Int,
                            first_children::Vector{UInt32},
                            next_siblings::Vector{UInt32})::Vector{GridItem}
    items = GridItem[]
    child_id = first_children[parent_id]
    auto_placement_idx = 1
    
    while child_id != 0
        # Skip out-of-flow and display:none children
        if layout.position_type[child_id] != POSITION_ABSOLUTE && 
           layout.position_type[child_id] != POSITION_FIXED &&
           layout.display[child_id] != DISPLAY_NONE
            
            # For now, auto-place items sequentially
            # In a full implementation, would parse grid-column/grid-row properties
            width = layout.width[child_id]
            height = layout.height[child_id]
            
            item = GridItem(
                child_id,
                Int32(auto_placement_idx),  # column_start
                Int32(auto_placement_idx + 1),  # column_end
                Int32(1),  # row_start
                Int32(2),  # row_end
                width,
                height
            )
            
            push!(items, item)
            auto_placement_idx += 1
        end
        
        child_id = next_siblings[child_id]
    end
    
    items
end

"""
    auto_place_items!(items::Vector{GridItem}, grid::GridDefinition) -> Nothing

Auto-place grid items that don't have explicit placement.
Implements the grid auto-placement algorithm.
"""
function auto_place_items!(items::Vector{GridItem}, grid::GridDefinition)
    # This is a simplified implementation
    # Full implementation would handle:
    # - Sparse auto-placement
    # - Dense packing
    # - Row vs column auto-flow
    # - Implicit grid expansion
    
    current_row = 1
    current_col = 1
    max_col = length(grid.columns)
    
    for item in items
        # Skip already-placed items (in a full implementation)
        # For now, all items are auto-placed
        
        # Place item
        # (Grid item is immutable, so we'd need to create a new one or use mutable struct)
        
        # Advance to next position
        if grid.auto_flow_row
            current_col += 1
            if current_col > max_col
                current_col = 1
                current_row += 1
            end
        else
            current_row += 1
        end
    end
end

"""
    resolve_track_sizes!(tracks::Vector{GridTrack}, available_space::Float32,
                        gap::Float32, item_count::Int) -> Nothing

Resolve track sizes including flexible (fr) units.
"""
function resolve_track_sizes!(tracks::Vector{GridTrack}, available_space::Float32,
                             gap::Float32, item_count::Int)
    n_tracks = length(tracks)
    total_gap = gap * max(0, n_tracks - 1)
    remaining_space = available_space - total_gap
    
    # First pass: resolve fixed and auto tracks
    total_flex = 0.0f0
    used_space = 0.0f0
    
    for track in tracks
        if track.is_flexible
            total_flex += track.flex_factor
        else
            used_space += track.size
            remaining_space -= track.size
        end
    end
    
    # Second pass: distribute remaining space to flexible tracks
    if total_flex > 0.0f0 && remaining_space > 0.0f0
        fr_unit = remaining_space / total_flex
        
        for track in tracks
            if track.is_flexible
                track.size = track.flex_factor * fr_unit
                track.size = clamp(track.size, track.min_size, track.max_size)
            end
        end
    end
    
    # Third pass: ensure minimum sizes for auto tracks
    for track in tracks
        if !track.is_flexible && track.size == 0.0f0
            # Auto track - use minimum content size
            # In a full implementation, would measure content
            track.size = track.min_size
        end
    end
end

"""
    compute_grid_layout!(layout::LayoutData, container_id::Int,
                        first_children::Vector{UInt32},
                        next_siblings::Vector{UInt32})

Compute CSS Grid layout for a grid container.
"""
function compute_grid_layout!(layout::LayoutData, container_id::Int,
                             first_children::Vector{UInt32},
                             next_siblings::Vector{UInt32})
    # Get grid container properties
    # For now, create a simple default grid
    # In full implementation, would read from layout data:
    # - grid-template-columns
    # - grid-template-rows  
    # - grid-gap
    # - grid-auto-flow
    
    # Simple 3-column grid as default
    grid = create_default_grid(10, 3)  # 10 rows, 3 columns
    
    # Get container dimensions
    container_width = layout.width[container_id]
    container_height = layout.height[container_id]
    padding_top = layout.padding_top[container_id]
    padding_right = layout.padding_right[container_id]
    padding_bottom = layout.padding_bottom[container_id]
    padding_left = layout.padding_left[container_id]
    
    available_width = container_width - padding_left - padding_right
    available_height = container_height - padding_top - padding_bottom
    
    # Collect grid items
    items = collect_grid_items(layout, container_id, first_children, next_siblings)
    
    if isempty(items)
        return
    end
    
    # Auto-place items
    auto_place_items!(items, grid)
    
    # Resolve track sizes
    resolve_track_sizes!(grid.columns, available_width, grid.gap_column, length(items))
    resolve_track_sizes!(grid.rows, available_height, grid.gap_row, length(items))
    
    # Position items in grid cells
    container_x = layout.x[container_id]
    container_y = layout.y[container_id]
    
    for (idx, item) in enumerate(items)
        item_id = Int(item.id)
        
        # Calculate grid cell position
        # For simplified auto-placement: items placed left-to-right, top-to-bottom
        row_idx = div(idx - 1, length(grid.columns)) + 1
        col_idx = mod(idx - 1, length(grid.columns)) + 1
        
        # Calculate x position (sum of column widths before this column)
        x_pos = padding_left
        for i in 1:(col_idx - 1)
            x_pos += grid.columns[i].size + grid.gap_column
        end
        
        # Calculate y position (sum of row heights before this row)
        y_pos = padding_top
        for i in 1:(row_idx - 1)
            if i <= length(grid.rows)
                y_pos += grid.rows[i].size + grid.gap_row
            end
        end
        
        # Set item position and size
        layout.x[item_id] = container_x + x_pos
        layout.y[item_id] = container_y + y_pos
        
        # Set item size to fill grid cell (or use item's intrinsic size if smaller)
        if col_idx <= length(grid.columns)
            cell_width = grid.columns[col_idx].size
            if layout.width[item_id] == 0.0f0
                layout.width[item_id] = cell_width
            end
        end
        
        if row_idx <= length(grid.rows)
            cell_height = grid.rows[row_idx].size
            if layout.height[item_id] == 0.0f0
                layout.height[item_id] = cell_height
            end
        end
    end
end

end # module GridLayout
