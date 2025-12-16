"""
    Layout

Layout calculation module for the browser rendering pipeline.

This module provides SIMD-friendly layout computation using contiguous arrays
in Structure of Arrays (SoA) format for optimal cache performance.

## Architecture

Content-- nodes → Layout calculation → Positioned rectangles

## Key Features

- Structure of Arrays for SIMD optimization
- Contiguous Float32 arrays for vectorized computation
- Support for CSS box model (margin, padding, border)
- CSS positioning (static, relative, absolute, fixed)
- Overflow and visibility handling

## Usage

```julia
using DOPBrowser.Layout

layout = LayoutData()
resize_layout!(layout, 100)
set_bounds!(layout, 1, 200.0f0, 150.0f0)
compute_layout!(layout, parents, first_children, next_siblings)
```
"""
module Layout

include("LayoutArrays.jl")

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
                     FLOAT_NONE, FLOAT_LEFT, FLOAT_RIGHT,
                     CLEAR_NONE, CLEAR_LEFT, CLEAR_RIGHT, CLEAR_BOTH

# Export all public API
export LayoutData, resize_layout!, set_bounds!, get_bounds, set_position!, get_position, compute_layout!
export set_css_position!, set_offsets!, set_margins!, set_paddings!, set_overflow!, set_visibility!, set_z_index!
export set_background_color!, get_background_color, set_borders!, has_border, set_float!, set_clear!
export POSITION_STATIC, POSITION_RELATIVE, POSITION_ABSOLUTE, POSITION_FIXED
export OVERFLOW_VISIBLE, OVERFLOW_HIDDEN
export DISPLAY_NONE, DISPLAY_BLOCK, DISPLAY_INLINE, DISPLAY_TABLE,
       DISPLAY_TABLE_CELL, DISPLAY_TABLE_ROW, DISPLAY_INLINE_BLOCK
export FLOAT_NONE, FLOAT_LEFT, FLOAT_RIGHT
export CLEAR_NONE, CLEAR_LEFT, CLEAR_RIGHT, CLEAR_BOTH

# Re-export submodule
export LayoutArrays

end # module Layout
