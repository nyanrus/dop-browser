"""
    Primitives

Content-- primitive node types as specified in v6.0.

## Layout Primitives
- `Stack`: Universal Flex container with Direction, Pack, Align, Gap
- `Grid`: 2D Cartesian layout with Cols, Rows
- `Scroll`: Viewport wrapper allowing content overflow
- `Rect`: Simple color block for dividers/shapes

## Text Primitives (JIT Targets)
- `Paragraph`: Container for flowing text (triggers JIT shaping)
- `Span`: Inline text unit within a Paragraph
- `Link`: Interactive inline text unit
- `TextCluster`: Internal primitive - atomic GPU command (output of JIT)

All nodes use the syntax: `Type( Prop: Value ) { Children }`
"""
module Primitives

export NodeType, NODE_STACK, NODE_GRID, NODE_SCROLL, NODE_RECT,
       NODE_PARAGRAPH, NODE_SPAN, NODE_LINK, NODE_TEXT_CLUSTER,
       NODE_ROOT, NODE_EXTERNAL
export ContentNode, NodeTable, create_node!, get_node, node_count,
       add_child!, get_children, get_parent, set_property!

"""
    NodeType

Content-- node type enumeration.
"""
@enum NodeType::UInt8 begin
    NODE_ROOT = 0        # Root document node
    NODE_STACK = 1       # Flex container
    NODE_GRID = 2        # 2D grid container  
    NODE_SCROLL = 3      # Scrollable viewport
    NODE_RECT = 4        # Simple colored rectangle
    NODE_PARAGRAPH = 5   # Text block (JIT target)
    NODE_SPAN = 6        # Inline text
    NODE_LINK = 7        # Interactive link
    NODE_TEXT_CLUSTER = 8  # Internal: GPU glyph run
    NODE_EXTERNAL = 9    # External/imported component
end

"""
    ContentNode

A Content-- node in the AST. Uses index-based references for cache efficiency.

# Fields
- `node_type::NodeType` - Type of node
- `parent::UInt32` - Parent node index (0 = no parent)
- `first_child::UInt32` - First child index (0 = no children)
- `next_sibling::UInt32` - Next sibling index (0 = last sibling)
- `style_id::UInt32` - Reference to flattened style (0 = default)
- `archetype_id::UInt32` - Style archetype for batch processing
- `text_id::UInt32` - Interned text content (for text nodes)
- `event_mask::UInt16` - Bitmask of bound events
- `flags::UInt8` - Node flags (dirty, visible, etc.)
"""
struct ContentNode
    node_type::NodeType
    parent::UInt32
    first_child::UInt32
    next_sibling::UInt32
    style_id::UInt32
    archetype_id::UInt32
    text_id::UInt32
    event_mask::UInt16
    flags::UInt8
end

# Node flags
const FLAG_DIRTY = UInt8(1 << 0)
const FLAG_VISIBLE = UInt8(1 << 1)
const FLAG_FOCUSABLE = UInt8(1 << 2)
const FLAG_JIT_DIRTY = UInt8(1 << 3)  # Text needs JIT reshaping

"""
    NodeTable

Structure of Arrays (SoA) representation of the Content-- node tree.
Uses parallel arrays for cache-efficient traversal and SIMD operations.
"""
mutable struct NodeTable
    # Core node data
    node_types::Vector{NodeType}
    parents::Vector{UInt32}
    first_children::Vector{UInt32}
    next_siblings::Vector{UInt32}
    
    # Style references
    style_ids::Vector{UInt32}
    archetype_ids::Vector{UInt32}
    
    # Text content
    text_ids::Vector{UInt32}
    
    # Event handling
    event_masks::Vector{UInt16}
    
    # Flags
    flags::Vector{UInt8}
    
    # String interning pool reference ID
    string_pool_id::UInt32
    
    function NodeTable()
        new(
            NodeType[],
            UInt32[],
            UInt32[],
            UInt32[],
            UInt32[],
            UInt32[],
            UInt32[],
            UInt16[],
            UInt8[],
            UInt32(0)
        )
    end
end

"""
    node_count(table::NodeTable) -> Int

Return the number of nodes in the table.
"""
function node_count(table::NodeTable)::Int
    return length(table.node_types)
end

"""
    create_node!(table::NodeTable, node_type::NodeType; 
                 parent::UInt32=UInt32(0),
                 style_id::UInt32=UInt32(0),
                 text_id::UInt32=UInt32(0)) -> UInt32

Create a new node and return its index.
"""
function create_node!(table::NodeTable, node_type::NodeType;
                      parent::UInt32=UInt32(0),
                      style_id::UInt32=UInt32(0),
                      text_id::UInt32=UInt32(0))::UInt32
    push!(table.node_types, node_type)
    push!(table.parents, parent)
    push!(table.first_children, UInt32(0))
    push!(table.next_siblings, UInt32(0))
    push!(table.style_ids, style_id)
    push!(table.archetype_ids, UInt32(0))
    push!(table.text_ids, text_id)
    push!(table.event_masks, UInt16(0))
    push!(table.flags, FLAG_DIRTY | FLAG_VISIBLE)
    
    new_id = UInt32(length(table.node_types))
    
    # Link to parent
    if parent != 0 && parent <= length(table.first_children)
        if table.first_children[parent] == 0
            table.first_children[parent] = new_id
        else
            # Find last sibling
            sibling = table.first_children[parent]
            while table.next_siblings[sibling] != 0
                sibling = table.next_siblings[sibling]
            end
            table.next_siblings[sibling] = new_id
        end
    end
    
    return new_id
end

"""
    get_node(table::NodeTable, id::UInt32) -> Union{ContentNode, Nothing}

Get a node by its index.
"""
function get_node(table::NodeTable, id::UInt32)::Union{ContentNode, Nothing}
    if id == 0 || id > length(table.node_types)
        return nothing
    end
    return ContentNode(
        table.node_types[id],
        table.parents[id],
        table.first_children[id],
        table.next_siblings[id],
        table.style_ids[id],
        table.archetype_ids[id],
        table.text_ids[id],
        table.event_masks[id],
        table.flags[id]
    )
end

"""
    add_child!(table::NodeTable, parent_id::UInt32, child_id::UInt32)

Add a child node to a parent.
"""
function add_child!(table::NodeTable, parent_id::UInt32, child_id::UInt32)
    if parent_id == 0 || child_id == 0
        return
    end
    if parent_id > length(table.parents) || child_id > length(table.parents)
        return
    end
    
    table.parents[child_id] = parent_id
    
    if table.first_children[parent_id] == 0
        table.first_children[parent_id] = child_id
    else
        sibling = table.first_children[parent_id]
        while table.next_siblings[sibling] != 0
            sibling = table.next_siblings[sibling]
        end
        table.next_siblings[sibling] = child_id
    end
end

"""
    get_children(table::NodeTable, parent_id::UInt32) -> Vector{UInt32}

Get all child node IDs of a parent.
"""
function get_children(table::NodeTable, parent_id::UInt32)::Vector{UInt32}
    children = UInt32[]
    if parent_id == 0 || parent_id > length(table.first_children)
        return children
    end
    
    child = table.first_children[parent_id]
    while child != 0
        push!(children, child)
        child = table.next_siblings[child]
    end
    return children
end

"""
    get_parent(table::NodeTable, node_id::UInt32) -> UInt32

Get the parent of a node.
"""
function get_parent(table::NodeTable, node_id::UInt32)::UInt32
    if node_id == 0 || node_id > length(table.parents)
        return UInt32(0)
    end
    return table.parents[node_id]
end

"""
    set_property!(table::NodeTable, node_id::UInt32, prop::Symbol, value)

Set a property on a node.
"""
function set_property!(table::NodeTable, node_id::UInt32, prop::Symbol, value)
    if node_id == 0 || node_id > length(table.node_types)
        return
    end
    
    if prop == :style_id
        table.style_ids[node_id] = UInt32(value)
    elseif prop == :archetype_id
        table.archetype_ids[node_id] = UInt32(value)
    elseif prop == :text_id
        table.text_ids[node_id] = UInt32(value)
    elseif prop == :event_mask
        table.event_masks[node_id] = UInt16(value)
    elseif prop == :flags
        table.flags[node_id] = UInt8(value)
    end
    
    # Mark dirty
    table.flags[node_id] |= FLAG_DIRTY
end

end # module Primitives
