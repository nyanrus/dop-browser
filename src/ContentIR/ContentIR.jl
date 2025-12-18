"""
    ContentIR

Content Intermediate Representation for the DOP Browser.

This module provides the core data structures for representing UI content:
- **MathOps**: Mathematical types and operators for layout computation
- **Primitives**: Content node types (Stack, Grid, Rect, Paragraph, etc.)
- **Properties**: Layout properties (Direction, Pack, Align, Inset, Offset, etc.)
- **StaticCore**: StaticCompiler-compatible subset for standalone executables

## StaticCompiler Compatibility

Mathematical types are designed for StaticCompiler:
- **Vec2, Box4, Rect** use StaticArrays.SVector (stack-allocated, fixed-size)
- **All math functions** have @inline hints for performance
- **Type-stable** with explicit return type annotations

For StaticCompiler contexts, use `ContentIR.StaticCore` which provides only
the types and functions that work without GC allocations.

Dynamic structures (NodeTable, PropertyTable) require Vector for flexibility.
See docs/STATICCOMPILER_READINESS.md and docs/STATICCOMPILER_DISTRIBUTION_GUIDE.md for details.

## Architecture

The rendering pipeline follows this structure:

### Content Text Rendering
```
Content Text Format In → Parse in Rust → Compute Layout in Julia → Flatten Content IR in Rust and Render
```

### Web Rendering
```
HTML&CSS In w/ Network → Parse in Rust → Lower in Rust → Compute Layout in Julia → Flatten Content IR in Rust and Render
```

### Interaction
```
Extract action-related codes (:hover, :click, etc.) in Julia → Pass to Rendering
```

### Feedback
```
Window and Eventloop in Rust → Apply in Content IR → Compute layout in Julia if needed → Flatten and Render in Rust
```

## Usage

```julia
using DOPBrowser.ContentIR

# MathOps types for layout computation
pos = Vec2(100.0f0, 200.0f0)
size = Vec2(50.0f0, 30.0f0)
bounds = Rect(pos, size)

# Properties
direction = DIRECTION_DOWN
pack = PACK_CENTER

# Primitives
table = NodeTable()
root_id = create_node!(table, NODE_ROOT)
```
"""
module ContentIR

# MathOps - Mathematical types and operators
include("MathOps.jl")
using .MathOps
export Vec2, Box4, Rect, Transform2D
export vec2, box4, rect
export lerp, clamp01, remap, smoothstep
export ⊕, ⊗, ⊙, box_merge, hadamard, dot_product
export ZERO_VEC2, UNIT_VEC2, ZERO_BOX4, ZERO_RECT
export norm, normalize, magnitude, dot
export horizontal, vertical, total
export IDENTITY_TRANSFORM, translate, scale, rotate
export contains, intersects, intersection, inset_rect, outset_rect
export compute_content_box, compute_total_size, compute_child_position

# Primitives - Content node types
include("Primitives.jl")
using .Primitives
export NodeType, NODE_ROOT, NODE_STACK, NODE_GRID, NODE_SCROLL, NODE_RECT
export NODE_PARAGRAPH, NODE_SPAN, NODE_LINK, NODE_TEXT_CLUSTER, NODE_EXTERNAL
export ContentNode, NodeTable, create_node!, get_node, node_count
export add_child!, get_children, get_parent

# Properties - Layout properties
include("Properties.jl")
using .Properties
export Direction, DIRECTION_DOWN, DIRECTION_UP, DIRECTION_RIGHT, DIRECTION_LEFT
export Pack, PACK_START, PACK_END, PACK_CENTER, PACK_BETWEEN, PACK_AROUND, PACK_EVENLY
export Align, ALIGN_START, ALIGN_END, ALIGN_CENTER, ALIGN_STRETCH, ALIGN_BASELINE
export Size, SizeSpec, SIZE_AUTO, SIZE_FIXED, SIZE_PERCENT, SIZE_MIN, SIZE_MAX, SIZE_FILL
export Inset, Offset, Gap
export PropertyValue, PropertyTable, set_property!, get_property, resize_properties!
export Color, parse_color, color_to_rgba
export direction_to_vec2, to_vec2, to_box4

# StaticCore - StaticCompiler-compatible subset
# Use this module for standalone executable compilation
include("StaticCore.jl")
# Note: StaticCore exports are accessed via ContentIR.StaticCore.*
# This keeps the namespace clean while providing StaticCompiler-compatible types

end # module ContentIR
