"""
    Layout

HTML5/CSS3 compliant layout calculation module for the browser rendering pipeline.

This module provides SIMD-friendly, thread-safe layout computation using contiguous arrays
in Structure of Arrays (SoA) format for optimal cache performance.

## Architecture

Content-- nodes → Layout calculation → Positioned rectangles

## Key Features

- Structure of Arrays for SIMD optimization
- Contiguous Float32 arrays for vectorized computation
- Full HTML5/CSS3 support:
  * CSS Flexbox Layout (flex-direction, flex-wrap, justify-content, align-items, etc.)
  * CSS Grid Layout (grid-template, grid-auto-flow, grid-gap, etc.)
  * CSS Box Model (margin, padding, border)
  * CSS Positioning (static, relative, absolute, fixed, sticky)
  * Float and clear properties
- Thread-safe layout computation with ReentrantLock
- Layout caching for performance (avoid redundant calculations)
- Precaching support for predictive rendering
- Incremental reflow (only recompute changed subtrees)
- Overflow and visibility handling

## Usage

```julia
using DOPBrowser.Layout

# Create layout data
layout = LayoutData()
resize_layout!(layout, 100)

# Set element properties
set_bounds!(layout, 1, 200.0f0, 150.0f0)
set_margins!(layout, 1, top=10.0f0, left=10.0f0)

# Compute layout (thread-safe)
compute_layout!(layout, parents, first_children, next_siblings)

# Use layout cache for performance
cache = LayoutCache(capacity=1000)
cache_layout!(cache, node_id, x, y, width, height)

# Invalidate and reflow
invalidate_subtree!(cache, changed_node_id)
```

## Thread Safety

All layout computation functions are thread-safe and can be called concurrently from multiple threads.
Layout caching uses ReentrantLock for synchronization.
"""
module Layout

include("LayoutArrays.jl")
include("FlexboxLayout.jl")
include("GridLayout.jl")
include("LayoutCache.jl")

using .LayoutArrays: LayoutData, resize_layout!, set_bounds!, get_bounds, 
                     set_position!, get_position, compute_layout!,
                     set_css_position!, set_offsets!, set_margins!, set_paddings!, 
                     set_overflow!, set_visibility!, set_z_index!,
                     set_background_color!, get_background_color, set_borders!, 
                     has_border, set_float!, set_clear!,
                     POSITION_STATIC, POSITION_RELATIVE, POSITION_ABSOLUTE, POSITION_FIXED,
                     OVERFLOW_VISIBLE, OVERFLOW_HIDDEN,
                     DISPLAY_NONE, DISPLAY_BLOCK, DISPLAY_INLINE, DISPLAY_TABLE,
                     DISPLAY_TABLE_CELL, DISPLAY_TABLE_ROW, DISPLAY_INLINE_BLOCK,
                     DISPLAY_FLEX, DISPLAY_INLINE_FLEX, DISPLAY_GRID, DISPLAY_INLINE_GRID,
                     FLOAT_NONE, FLOAT_LEFT, FLOAT_RIGHT,
                     CLEAR_NONE, CLEAR_LEFT, CLEAR_RIGHT, CLEAR_BOTH,
                     FLEX_DIRECTION_ROW, FLEX_DIRECTION_ROW_REVERSE, 
                     FLEX_DIRECTION_COLUMN, FLEX_DIRECTION_COLUMN_REVERSE,
                     FLEX_WRAP_NOWRAP, FLEX_WRAP_WRAP, FLEX_WRAP_WRAP_REVERSE,
                     JUSTIFY_CONTENT_START, JUSTIFY_CONTENT_END, JUSTIFY_CONTENT_CENTER,
                     JUSTIFY_CONTENT_BETWEEN, JUSTIFY_CONTENT_AROUND, JUSTIFY_CONTENT_EVENLY,
                     ALIGN_ITEMS_START, ALIGN_ITEMS_END, ALIGN_ITEMS_CENTER,
                     ALIGN_ITEMS_STRETCH, ALIGN_ITEMS_BASELINE,
                     ALIGN_CONTENT_START, ALIGN_CONTENT_END, ALIGN_CONTENT_CENTER,
                     ALIGN_CONTENT_BETWEEN, ALIGN_CONTENT_AROUND, ALIGN_CONTENT_STRETCH

using .FlexboxLayout: compute_flexbox_layout!
using .GridLayout: compute_grid_layout!
using .LayoutCache: LayoutCache, cache_layout!, get_cached_layout, has_cached_layout,
                    invalidate_node!, invalidate_subtree!, clear_cache!,
                    precache_layouts!, get_cache_stats

# Export all public API
export LayoutData, resize_layout!, set_bounds!, get_bounds, set_position!, get_position, compute_layout!
export set_css_position!, set_offsets!, set_margins!, set_paddings!, set_overflow!, set_visibility!, set_z_index!
export set_background_color!, get_background_color, set_borders!, has_border, set_float!, set_clear!

# Position constants
export POSITION_STATIC, POSITION_RELATIVE, POSITION_ABSOLUTE, POSITION_FIXED

# Overflow constants
export OVERFLOW_VISIBLE, OVERFLOW_HIDDEN

# Display constants (HTML5/CSS3 complete)
export DISPLAY_NONE, DISPLAY_BLOCK, DISPLAY_INLINE, DISPLAY_TABLE,
       DISPLAY_TABLE_CELL, DISPLAY_TABLE_ROW, DISPLAY_INLINE_BLOCK,
       DISPLAY_FLEX, DISPLAY_INLINE_FLEX, DISPLAY_GRID, DISPLAY_INLINE_GRID

# Float and clear constants
export FLOAT_NONE, FLOAT_LEFT, FLOAT_RIGHT
export CLEAR_NONE, CLEAR_LEFT, CLEAR_RIGHT, CLEAR_BOTH

# Flexbox constants
export FLEX_DIRECTION_ROW, FLEX_DIRECTION_ROW_REVERSE, 
       FLEX_DIRECTION_COLUMN, FLEX_DIRECTION_COLUMN_REVERSE
export FLEX_WRAP_NOWRAP, FLEX_WRAP_WRAP, FLEX_WRAP_WRAP_REVERSE
export JUSTIFY_CONTENT_START, JUSTIFY_CONTENT_END, JUSTIFY_CONTENT_CENTER,
       JUSTIFY_CONTENT_BETWEEN, JUSTIFY_CONTENT_AROUND, JUSTIFY_CONTENT_EVENLY
export ALIGN_ITEMS_START, ALIGN_ITEMS_END, ALIGN_ITEMS_CENTER,
       ALIGN_ITEMS_STRETCH, ALIGN_ITEMS_BASELINE
export ALIGN_CONTENT_START, ALIGN_CONTENT_END, ALIGN_CONTENT_CENTER,
       ALIGN_CONTENT_BETWEEN, ALIGN_CONTENT_AROUND, ALIGN_CONTENT_STRETCH

# Flexbox and Grid layout functions
export compute_flexbox_layout!, compute_grid_layout!

# Layout caching
export LayoutCache, cache_layout!, get_cached_layout, has_cached_layout
export invalidate_node!, invalidate_subtree!, clear_cache!
export precache_layouts!, get_cache_stats

# Re-export submodules
export LayoutArrays, FlexboxLayout, GridLayout, LayoutCache

end # module Layout
