"""
    NodeTable

Structure of Arrays (SoA) DOM representation where nodes are IDs in a table.

Uses UInt32 indices instead of pointers for cache-friendly traversal and
efficient memory usage. The DOM is stored as parallel arrays enabling
vectorized operations.
"""
module NodeTable

using ..StringInterner: StringPool

export NodeKind, DOMTable, add_node!, get_parent, get_first_child, get_next_sibling
export get_tag, set_parent!, set_first_child!, set_next_sibling!, node_count
export NODE_ELEMENT, NODE_TEXT, NODE_COMMENT, NODE_DOCUMENT, NODE_DOCTYPE
export get_id_attr, get_class_attr, get_style_attr, set_attributes!

"""
    NodeKind

Type of DOM node.
"""
@enum NodeKind::UInt8 begin
    NODE_ELEMENT = 1
    NODE_TEXT = 2
    NODE_COMMENT = 3
    NODE_DOCUMENT = 4
    NODE_DOCTYPE = 5
end

"""
    DOMTable

Structure of Arrays representation of the DOM tree.

Nodes are referenced by UInt32 indices. Index 0 represents null/no-node.
All arrays are 1-indexed, so node ID 1 corresponds to index 1 in each array.

# Fields
- `kinds::Vector{NodeKind}` - Node type for each node
- `tags::Vector{UInt32}` - Interned tag name ID (0 for non-elements)
- `parents::Vector{UInt32}` - Parent node ID (0 for root)
- `first_children::Vector{UInt32}` - First child node ID (0 if no children)
- `next_siblings::Vector{UInt32}` - Next sibling node ID (0 if last)
- `text_content::Vector{UInt32}` - Interned text content ID (for text/comment nodes)
- `archetype_ids::Vector{UInt32}` - Style archetype ID (0 if none)
- `id_attrs::Vector{UInt32}` - Interned id attribute (0 if none)
- `class_attrs::Vector{UInt32}` - Interned class attribute (0 if none)
- `style_attrs::Vector{UInt32}` - Interned style attribute (0 if none)
- `strings::StringPool` - Reference to string pool
"""
mutable struct DOMTable
    kinds::Vector{NodeKind}
    tags::Vector{UInt32}
    parents::Vector{UInt32}
    first_children::Vector{UInt32}
    next_siblings::Vector{UInt32}
    text_content::Vector{UInt32}
    archetype_ids::Vector{UInt32}
    id_attrs::Vector{UInt32}
    class_attrs::Vector{UInt32}
    style_attrs::Vector{UInt32}
    strings::StringPool
    
    function DOMTable(pool::StringPool)
        new(
            NodeKind[],
            UInt32[],
            UInt32[],
            UInt32[],
            UInt32[],
            UInt32[],
            UInt32[],
            UInt32[],
            UInt32[],
            UInt32[],
            pool
        )
    end
end

"""
    node_count(table::DOMTable) -> Int

Return the number of nodes in the table.
"""
function node_count(table::DOMTable)::Int
    return length(table.kinds)
end

"""
    add_node!(table::DOMTable, kind::NodeKind; tag::UInt32=UInt32(0), 
              text::UInt32=UInt32(0), parent::UInt32=UInt32(0)) -> UInt32

Add a new node to the table and return its ID.

# Arguments
- `table::DOMTable` - The DOM table
- `kind::NodeKind` - Type of node to create
- `tag::UInt32` - Interned tag name ID (for elements)
- `text::UInt32` - Interned text content ID (for text/comment nodes)
- `parent::UInt32` - Parent node ID (0 for root)

# Returns
- `UInt32` - The new node's ID
"""
function add_node!(table::DOMTable, kind::NodeKind; 
                   tag::UInt32=UInt32(0), 
                   text::UInt32=UInt32(0),
                   parent::UInt32=UInt32(0))::UInt32
    push!(table.kinds, kind)
    push!(table.tags, tag)
    push!(table.parents, parent)
    push!(table.first_children, UInt32(0))
    push!(table.next_siblings, UInt32(0))
    push!(table.text_content, text)
    push!(table.archetype_ids, UInt32(0))
    push!(table.id_attrs, UInt32(0))
    push!(table.class_attrs, UInt32(0))
    push!(table.style_attrs, UInt32(0))
    
    new_id = UInt32(length(table.kinds))
    
    # Link to parent's children
    if parent != 0
        if table.first_children[parent] == 0
            table.first_children[parent] = new_id
        else
            # Find last sibling and append
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
    get_parent(table::DOMTable, id::UInt32) -> UInt32

Get the parent node ID.
"""
function get_parent(table::DOMTable, id::UInt32)::UInt32
    if id == 0 || id > length(table.parents)
        return UInt32(0)
    end
    return table.parents[id]
end

"""
    get_first_child(table::DOMTable, id::UInt32) -> UInt32

Get the first child node ID.
"""
function get_first_child(table::DOMTable, id::UInt32)::UInt32
    if id == 0 || id > length(table.first_children)
        return UInt32(0)
    end
    return table.first_children[id]
end

"""
    get_next_sibling(table::DOMTable, id::UInt32) -> UInt32

Get the next sibling node ID.
"""
function get_next_sibling(table::DOMTable, id::UInt32)::UInt32
    if id == 0 || id > length(table.next_siblings)
        return UInt32(0)
    end
    return table.next_siblings[id]
end

"""
    get_tag(table::DOMTable, id::UInt32) -> UInt32

Get the interned tag name ID for an element.
"""
function get_tag(table::DOMTable, id::UInt32)::UInt32
    if id == 0 || id > length(table.tags)
        return UInt32(0)
    end
    return table.tags[id]
end

"""
    set_parent!(table::DOMTable, id::UInt32, parent::UInt32)

Set the parent of a node.
"""
function set_parent!(table::DOMTable, id::UInt32, parent::UInt32)
    if id != 0 && id <= length(table.parents)
        table.parents[id] = parent
    end
end

"""
    set_first_child!(table::DOMTable, id::UInt32, child::UInt32)

Set the first child of a node.
"""
function set_first_child!(table::DOMTable, id::UInt32, child::UInt32)
    if id != 0 && id <= length(table.first_children)
        table.first_children[id] = child
    end
end

"""
    set_next_sibling!(table::DOMTable, id::UInt32, sibling::UInt32)

Set the next sibling of a node.
"""
function set_next_sibling!(table::DOMTable, id::UInt32, sibling::UInt32)
    if id != 0 && id <= length(table.next_siblings)
        table.next_siblings[id] = sibling
    end
end

"""
    get_id_attr(table::DOMTable, id::UInt32) -> UInt32

Get the interned id attribute for a node.
"""
function get_id_attr(table::DOMTable, id::UInt32)::UInt32
    if id == 0 || id > length(table.id_attrs)
        return UInt32(0)
    end
    return table.id_attrs[id]
end

"""
    get_class_attr(table::DOMTable, id::UInt32) -> UInt32

Get the interned class attribute for a node.
"""
function get_class_attr(table::DOMTable, id::UInt32)::UInt32
    if id == 0 || id > length(table.class_attrs)
        return UInt32(0)
    end
    return table.class_attrs[id]
end

"""
    get_style_attr(table::DOMTable, id::UInt32) -> UInt32

Get the interned style attribute for a node.
"""
function get_style_attr(table::DOMTable, id::UInt32)::UInt32
    if id == 0 || id > length(table.style_attrs)
        return UInt32(0)
    end
    return table.style_attrs[id]
end

"""
    set_attributes!(table::DOMTable, id::UInt32; 
                    id_attr::UInt32=UInt32(0), 
                    class_attr::UInt32=UInt32(0), 
                    style_attr::UInt32=UInt32(0))

Set attributes for a node.
"""
function set_attributes!(table::DOMTable, id::UInt32; 
                         id_attr::UInt32=UInt32(0), 
                         class_attr::UInt32=UInt32(0), 
                         style_attr::UInt32=UInt32(0))
    if id != 0 && id <= length(table.id_attrs)
        if id_attr != 0
            table.id_attrs[id] = id_attr
        end
        if class_attr != 0
            table.class_attrs[id] = class_attr
        end
        if style_attr != 0
            table.style_attrs[id] = style_attr
        end
    end
end

end # module NodeTable
