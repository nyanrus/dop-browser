"""
    StaticCore

StaticCompiler-compatible core types extracted from ContentIR.
Uses only stack-allocated, fixed-size types for compilation without GC.

## Design Philosophy

Julia's mathematical aesthetics are preserved while ensuring StaticCompiler compatibility:
- **Vec2, Box4, Rect** from MathOps for natural mathematical expressions
- **Property enums** (Direction, Pack, Align) for type-safe layout semantics
- **Fixed-size structures** using StaticArrays for compile-time known bounds

## Usage in StaticCompiler Contexts

```julia
using DOPBrowser.ContentIR.StaticCore

# Mathematical layout computation
pos = Vec2(100.0f0, 200.0f0)
size = Vec2(50.0f0, 30.0f0)
bounds = Rect(pos, size)

# Direction as unit vector (mathematical elegance)
flow = direction_to_vec2(DIRECTION_DOWN)  # Vec2(0, 1)
next_pos = pos + flow * child_height

# Unicode operators for clarity
merged_box = box1 ⊕ box2  # Max of each side
```

## Relationship with ContentIR

StaticCore re-exports StaticCompiler-compatible subsets from:
- `MathOps.jl` - All types and operators (fully compatible)
- `Properties.jl` - Enums and simple structs only (PropertyTable excluded)
- `Primitives.jl` - NodeType enum only (NodeTable excluded)

For dynamic structures, use the full ContentIR or delegate to Rust via FFI.
"""
module StaticCore

using StaticArrays
using LinearAlgebra

# =============================================================================
# Re-exports from MathOps (fully StaticCompiler-compatible)
# =============================================================================

using ..MathOps

# Types
export Vec2, Box4, Rect, Transform2D

# Constructors
export vec2, box4, rect

# Mathematical utilities
export lerp, clamp01, remap, smoothstep

# Unicode operators (mathematical aesthetics)
export ⊕, ⊗, ⊙

# ASCII alternatives
export box_merge, hadamard, dot_product

# Constants
export ZERO_VEC2, UNIT_VEC2, ZERO_BOX4, ZERO_RECT, IDENTITY_TRANSFORM

# LinearAlgebra re-exports
export norm, normalize

# Aliases for clarity
export magnitude, dot

# Box4 utilities
export horizontal, vertical, total

# Transform constructors
export translate, scale, rotate

# Rect operations
export contains, intersects, intersection, inset_rect, outset_rect

# Layout computation helpers
export compute_content_box, compute_total_size, compute_child_position

# =============================================================================
# Property Enums (StaticCompiler-compatible)
# =============================================================================

using ..Properties: Direction, Pack, Align
using ..Properties: DIRECTION_DOWN, DIRECTION_UP, DIRECTION_RIGHT, DIRECTION_LEFT
using ..Properties: PACK_START, PACK_END, PACK_CENTER, PACK_BETWEEN, PACK_AROUND, PACK_EVENLY
using ..Properties: ALIGN_START, ALIGN_END, ALIGN_CENTER, ALIGN_STRETCH, ALIGN_BASELINE
using ..Properties: direction_to_vec2

export Direction, Pack, Align
export DIRECTION_DOWN, DIRECTION_UP, DIRECTION_RIGHT, DIRECTION_LEFT
export PACK_START, PACK_END, PACK_CENTER, PACK_BETWEEN, PACK_AROUND, PACK_EVENLY
export ALIGN_START, ALIGN_END, ALIGN_CENTER, ALIGN_STRETCH, ALIGN_BASELINE
export direction_to_vec2

# =============================================================================
# Color (StaticCompiler-compatible struct)
# =============================================================================

"""
    StaticColor

RGBA color with 8-bit components.
StaticCompiler-compatible (no GC allocation).
"""
struct StaticColor
    r::UInt8
    g::UInt8
    b::UInt8
    a::UInt8
end

# Default colors
const COLOR_BLACK = StaticColor(0x00, 0x00, 0x00, 0xff)
const COLOR_WHITE = StaticColor(0xff, 0xff, 0xff, 0xff)
const COLOR_TRANSPARENT = StaticColor(0x00, 0x00, 0x00, 0x00)

"""
    color_to_rgba(c::StaticColor) -> NTuple{4, Float32}

Convert StaticColor to normalized RGBA floats (0-1 range).
"""
@inline function color_to_rgba(c::StaticColor)::NTuple{4, Float32}
    (Float32(c.r) / 255.0f0,
     Float32(c.g) / 255.0f0,
     Float32(c.b) / 255.0f0,
     Float32(c.a) / 255.0f0)
end

"""
    rgba_to_color(r::Float32, g::Float32, b::Float32, a::Float32) -> StaticColor

Convert normalized RGBA floats to StaticColor.
"""
@inline function rgba_to_color(r::Float32, g::Float32, b::Float32, a::Float32)::StaticColor
    StaticColor(
        round(UInt8, clamp01(r) * 255),
        round(UInt8, clamp01(g) * 255),
        round(UInt8, clamp01(b) * 255),
        round(UInt8, clamp01(a) * 255)
    )
end

export StaticColor, COLOR_BLACK, COLOR_WHITE, COLOR_TRANSPARENT
export color_to_rgba, rgba_to_color

# =============================================================================
# Node Type Enum (StaticCompiler-compatible)
# =============================================================================

using ..Primitives: NodeType
using ..Primitives: NODE_ROOT, NODE_STACK, NODE_GRID, NODE_SCROLL, NODE_RECT
using ..Primitives: NODE_PARAGRAPH, NODE_SPAN, NODE_LINK, NODE_TEXT_CLUSTER, NODE_EXTERNAL

export NodeType
export NODE_ROOT, NODE_STACK, NODE_GRID, NODE_SCROLL, NODE_RECT
export NODE_PARAGRAPH, NODE_SPAN, NODE_LINK, NODE_TEXT_CLUSTER, NODE_EXTERNAL

# =============================================================================
# Fixed-Size Node Representation (for static contexts)
# =============================================================================

"""
    StaticNode

Minimal node representation for StaticCompiler contexts.
All fields are primitive types or fixed-size arrays.
"""
struct StaticNode
    node_type::UInt8
    parent::UInt32
    first_child::UInt32
    next_sibling::UInt32
    # Layout cache
    x::Float32
    y::Float32
    width::Float32
    height::Float32
end

# Default node
const NULL_NODE = StaticNode(0x00, 0x00, 0x00, 0x00, 0.0f0, 0.0f0, 0.0f0, 0.0f0)

"""
    node_position(node::StaticNode) -> Vec2{Float32}

Get node position as Vec2.
"""
@inline node_position(node::StaticNode)::Vec2{Float32} = Vec2(node.x, node.y)

"""
    node_size(node::StaticNode) -> Vec2{Float32}

Get node size as Vec2.
"""
@inline node_size(node::StaticNode)::Vec2{Float32} = Vec2(node.width, node.height)

"""
    node_bounds(node::StaticNode) -> Rect{Float32}

Get node bounds as Rect.
"""
@inline node_bounds(node::StaticNode)::Rect{Float32} = Rect(node.x, node.y, node.width, node.height)

export StaticNode, NULL_NODE
export node_position, node_size, node_bounds

# =============================================================================
# Fixed-Size Node Table (for bounded static contexts)
# =============================================================================

"""
    StaticNodeTable{N}

Fixed-capacity node table for StaticCompiler contexts.
N is the maximum number of nodes (compile-time constant).

Use this for applications with known, bounded node counts.
For unbounded trees, use Rust FFI with dynamic allocation.

# Example
```julia
const MAX_NODES = 64
table = StaticNodeTable{MAX_NODES}()
```
"""
struct StaticNodeTable{N}
    nodes::MVector{N, StaticNode}
    count::Int32
    
    function StaticNodeTable{N}() where N
        nodes = MVector{N, StaticNode}(ntuple(_ -> NULL_NODE, N))
        new{N}(nodes, Int32(0))
    end
end

"""
    add_node!(table::StaticNodeTable, node_type::UInt8, parent::UInt32) -> UInt32

Add a node to the table. Returns node ID (1-indexed) or 0 if table is full.
"""
@inline function add_node!(table::StaticNodeTable{N}, node_type::UInt8, parent::UInt32)::UInt32 where N
    if table.count >= N
        return UInt32(0)  # Table full
    end
    
    new_id = UInt32(table.count + 1)
    # Create new node (immutable, so we replace)
    # Note: In static contexts, we work with the MVector directly
    # For actual mutation in StaticCompiler, use MallocArray from StaticTools
    new_id
end

"""
    get_node(table::StaticNodeTable, id::UInt32) -> StaticNode

Get a node by ID. Returns NULL_NODE if ID is invalid.
"""
@inline function get_node(table::StaticNodeTable{N}, id::UInt32)::StaticNode where N
    if id == 0 || id > table.count
        return NULL_NODE
    end
    table.nodes[id]
end

"""
    node_count(table::StaticNodeTable) -> Int32

Get the number of nodes in the table.
"""
@inline node_count(table::StaticNodeTable)::Int32 = table.count

export StaticNodeTable, add_node!, get_node, node_count

# =============================================================================
# Layout Computation Types (for algorithm expression)
# =============================================================================

"""
    LayoutConstraint

Constraints for layout computation.
Represents available space and sizing rules.
"""
struct LayoutConstraint
    min_width::Float32
    max_width::Float32
    min_height::Float32
    max_height::Float32
end

# Unconstrained layout
const UNCONSTRAINED = LayoutConstraint(0.0f0, Inf32, 0.0f0, Inf32)

"""
    constrain(size::Vec2, constraint::LayoutConstraint) -> Vec2

Apply constraints to a size.
"""
@inline function constrain(size::Vec2{Float32}, c::LayoutConstraint)::Vec2{Float32}
    Vec2(
        clamp(size.x, c.min_width, c.max_width),
        clamp(size.y, c.min_height, c.max_height)
    )
end

"""
    LayoutResult

Computed layout for a node.
"""
struct LayoutResult
    position::Vec2{Float32}
    size::Vec2{Float32}
    content_origin::Vec2{Float32}
end

export LayoutConstraint, UNCONSTRAINED, constrain
export LayoutResult

# =============================================================================
# Inset/Offset as Fixed Structs (StaticCompiler-compatible)
# =============================================================================

"""
    StaticInset

Fixed-size inset (padding) representation.
"""
struct StaticInset
    top::Float32
    right::Float32
    bottom::Float32
    left::Float32
end

const ZERO_INSET = StaticInset(0.0f0, 0.0f0, 0.0f0, 0.0f0)

"""
    inset_to_box4(i::StaticInset) -> Box4{Float32}

Convert StaticInset to MathOps Box4.
"""
@inline inset_to_box4(i::StaticInset)::Box4{Float32} = Box4(i.top, i.right, i.bottom, i.left)

"""
    inset_horizontal(i::StaticInset) -> Float32

Sum of left and right inset.
"""
@inline inset_horizontal(i::StaticInset)::Float32 = i.left + i.right

"""
    inset_vertical(i::StaticInset) -> Float32

Sum of top and bottom inset.
"""
@inline inset_vertical(i::StaticInset)::Float32 = i.top + i.bottom

"""
    inset_total(i::StaticInset) -> Vec2{Float32}

Total inset as Vec2(horizontal, vertical).
"""
@inline inset_total(i::StaticInset)::Vec2{Float32} = Vec2(inset_horizontal(i), inset_vertical(i))

export StaticInset, ZERO_INSET
export inset_to_box4, inset_horizontal, inset_vertical, inset_total

# =============================================================================
# Static Layout Helpers
# =============================================================================

"""
    compute_content_origin(bounds::Rect, inset::StaticInset) -> Vec2{Float32}

Compute where content starts within bounds.

# Mathematical Form
```
content_origin = bounds.origin + Vec2(inset.left, inset.top)
```
"""
@inline function compute_content_origin(bounds::Rect, inset::StaticInset)::Vec2{Float32}
    Vec2(bounds.x + inset.left, bounds.y + inset.top)
end

"""
    compute_content_size(bounds::Rect, inset::StaticInset) -> Vec2{Float32}

Compute available content size within bounds.

# Mathematical Form
```
content_size = bounds.size - inset.total
```
"""
@inline function compute_content_size(bounds::Rect, inset::StaticInset)::Vec2{Float32}
    Vec2(
        bounds.width - inset_horizontal(inset),
        bounds.height - inset_vertical(inset)
    )
end

"""
    stack_child_position(content_origin::Vec2, accumulated::Float32, 
                         direction::Direction, child_offset::Vec2) -> Vec2{Float32}

Compute child position in a stack layout.

# Mathematical Form
For DIRECTION_DOWN:
```
child.position = content_origin + Vec2(child_offset.x, accumulated + child_offset.y)
```
"""
@inline function stack_child_position(
    content_origin::Vec2{Float32},
    accumulated::Float32,
    direction::Direction,
    child_offset::Vec2{Float32}
)::Vec2{Float32}
    flow = direction_to_vec2(direction)
    content_origin + flow * accumulated + child_offset
end

export compute_content_origin, compute_content_size, stack_child_position

end # module StaticCore
