"""
    SourceMap

Source mapping from HTML/CSS (source language) to Content-- (target language).

Content-- is designed as a mathematically intuitive target language that:
1. Has pre-calculated values (no CSS cascade at runtime)
2. Maps 1:1 with HTML/CSS concepts (lowered with minimal calculation)
3. Is render-friendly (rendering engine understands only Content--)

## Mathematical Semantics

Content-- uses a coordinate system where:
- Origin (0, 0) is at top-left of viewport
- X increases rightward
- Y increases downward
- All units are in device pixels (Float32)

### Layout Mathematics

For a node N with parent P:

Position in normal flow:
    N.x = P.content_x + N.offset_left + Σ(sibling.total_width)
    N.y = P.content_y + N.offset_top + Σ(sibling.total_height)

Where:
    P.content_x = P.x + P.inset_left
    P.content_y = P.y + P.inset_top
    N.total_width = N.width + N.offset_left + N.offset_right
    N.total_height = N.height + N.offset_top + N.offset_bottom

Absolute positioning (position_type = ABSOLUTE):
    N.x = containing_block.x + N.css_left  (if left specified)
    N.x = containing_block.x + containing_block.width - N.width - N.css_right  (if right specified)

## SourceMap Structure

Each Content-- node stores optional source location:
- source_line: UInt32 (line in HTML source)
- source_column: UInt32 (column in HTML source)
- source_type: SourceType (HTML_ELEMENT, HTML_TEXT, CSS_RULE, etc.)
"""
module SourceMap

export SourceType, SourceLocation, SourceMapTable
export SOURCE_HTML_ELEMENT, SOURCE_HTML_TEXT, SOURCE_CSS_RULE, SOURCE_CSS_PROPERTY
export add_mapping!, get_location, get_nodes_at_location

"""
    SourceType

Type of source construct that maps to a Content-- node.
"""
@enum SourceType::UInt8 begin
    SOURCE_UNKNOWN = 0
    SOURCE_HTML_ELEMENT = 1      # <div>, <span>, etc.
    SOURCE_HTML_TEXT = 2         # Text content
    SOURCE_HTML_COMMENT = 3      # <!-- comment -->
    SOURCE_CSS_RULE = 4          # selector { ... }
    SOURCE_CSS_PROPERTY = 5      # property: value
    SOURCE_CSS_INLINE = 6        # style="..."
    SOURCE_GENERATED = 7         # Content-- generated (pseudo-elements, etc.)
end

"""
    SourceLocation

A location in the source HTML/CSS.

# Fields
- `source_type::SourceType` - Type of source construct
- `line::UInt32` - 1-based line number
- `column::UInt32` - 1-based column number
- `end_line::UInt32` - End line number
- `end_column::UInt32` - End column number
- `file_id::UInt32` - Interned filename (0 = inline/unknown)
- `selector_id::UInt32` - For CSS rules, the interned selector string
"""
struct SourceLocation
    source_type::SourceType
    line::UInt32
    column::UInt32
    end_line::UInt32
    end_column::UInt32
    file_id::UInt32
    selector_id::UInt32
    
    function SourceLocation(;
            source_type::SourceType = SOURCE_UNKNOWN,
            line::UInt32 = UInt32(0),
            column::UInt32 = UInt32(0),
            end_line::UInt32 = UInt32(0),
            end_column::UInt32 = UInt32(0),
            file_id::UInt32 = UInt32(0),
            selector_id::UInt32 = UInt32(0))
        new(source_type, line, column, end_line, end_column, file_id, selector_id)
    end
end

"""
    SourceMapTable

Bidirectional mapping between Content-- nodes and HTML/CSS source locations.

Structure of Arrays for cache efficiency.
"""
mutable struct SourceMapTable
    # Node ID -> Source location (parallel arrays)
    source_types::Vector{SourceType}
    lines::Vector{UInt32}
    columns::Vector{UInt32}
    end_lines::Vector{UInt32}
    end_columns::Vector{UInt32}
    file_ids::Vector{UInt32}
    selector_ids::Vector{UInt32}
    
    # CSS property contributions (multiple CSS rules can affect one node)
    # Maps node_id -> list of (property_name_id, source_location)
    css_contributions::Dict{UInt32, Vector{Tuple{UInt32, SourceLocation}}}
    
    # Reverse mapping: (file_id, line) -> Vector of node IDs
    line_to_nodes::Dict{Tuple{UInt32, UInt32}, Vector{UInt32}}
    
    function SourceMapTable()
        new(
            SourceType[],
            UInt32[],
            UInt32[],
            UInt32[],
            UInt32[],
            UInt32[],
            UInt32[],
            Dict{UInt32, Vector{Tuple{UInt32, SourceLocation}}}(),
            Dict{Tuple{UInt32, UInt32}, Vector{UInt32}}()
        )
    end
end

"""
    resize_sourcemap!(table::SourceMapTable, new_size::Int)

Resize source map arrays for new nodes.
"""
function resize_sourcemap!(table::SourceMapTable, new_size::Int)
    old_size = length(table.source_types)
    
    # Resize all arrays
    fields_defaults = [
        (table.source_types, SOURCE_UNKNOWN),
        (table.lines, UInt32(0)),
        (table.columns, UInt32(0)),
        (table.end_lines, UInt32(0)),
        (table.end_columns, UInt32(0)),
        (table.file_ids, UInt32(0)),
        (table.selector_ids, UInt32(0))
    ]
    
    for (field, default) in fields_defaults
        resize!(field, new_size)
        # Initialize new entries
        for i in (old_size + 1):new_size
            field[i] = default
        end
    end
end

"""
    add_mapping!(table::SourceMapTable, node_id::UInt32, location::SourceLocation)

Add a source mapping for a Content-- node.
"""
function add_mapping!(table::SourceMapTable, node_id::UInt32, location::SourceLocation)
    # Ensure arrays are large enough
    if node_id > length(table.source_types)
        resize_sourcemap!(table, Int(node_id))
    end
    
    # Explicit mapping between SourceLocation fields and SourceMapTable fields
    field_map = Dict(
        :source_type => :source_types,
        :line => :lines,
        :column => :columns,
        :end_line => :end_lines,
        :end_column => :end_columns,
        :file_id => :file_ids,
        :selector_id => :selector_ids
    )
    
    # Set primary location
    for (loc_field, table_field) in field_map
        getfield(table, table_field)[node_id] = getfield(location, loc_field)
    end
    
    # Add to reverse mapping
    key = (location.file_id, location.line)
    if !haskey(table.line_to_nodes, key)
        table.line_to_nodes[key] = UInt32[]
    end
    if !(node_id in table.line_to_nodes[key])
        push!(table.line_to_nodes[key], node_id)
    end
end

"""
    add_css_contribution!(table::SourceMapTable, node_id::UInt32, 
                          property_id::UInt32, location::SourceLocation)

Record that a CSS property came from a specific source location.
Useful for debugging which CSS rule affected which property.
"""
function add_css_contribution!(table::SourceMapTable, node_id::UInt32,
                               property_id::UInt32, location::SourceLocation)
    if !haskey(table.css_contributions, node_id)
        table.css_contributions[node_id] = Tuple{UInt32, SourceLocation}[]
    end
    push!(table.css_contributions[node_id], (property_id, location))
end

"""
    get_location(table::SourceMapTable, node_id::UInt32) -> SourceLocation

Get the source location for a Content-- node.
"""
function get_location(table::SourceMapTable, node_id::UInt32)::SourceLocation
    if node_id == 0 || node_id > length(table.source_types)
        return SourceLocation()
    end
    
    return SourceLocation(
        source_type = table.source_types[node_id],
        line = table.lines[node_id],
        column = table.columns[node_id],
        end_line = table.end_lines[node_id],
        end_column = table.end_columns[node_id],
        file_id = table.file_ids[node_id],
        selector_id = table.selector_ids[node_id]
    )
end

"""
    get_nodes_at_location(table::SourceMapTable, file_id::UInt32, 
                          line::UInt32) -> Vector{UInt32}

Get all Content-- nodes that originated from a source line.
"""
function get_nodes_at_location(table::SourceMapTable, file_id::UInt32,
                               line::UInt32)::Vector{UInt32}
    key = (file_id, line)
    return get(table.line_to_nodes, key, UInt32[])
end

"""
    get_css_contributions(table::SourceMapTable, 
                          node_id::UInt32) -> Vector{Tuple{UInt32, SourceLocation}}

Get all CSS contributions for a node.
"""
function get_css_contributions(table::SourceMapTable, 
                               node_id::UInt32)::Vector{Tuple{UInt32, SourceLocation}}
    return get(table.css_contributions, node_id, Tuple{UInt32, SourceLocation}[])
end

"""
    node_count(table::SourceMapTable) -> Int

Get the number of mapped nodes.
"""
function node_count(table::SourceMapTable)::Int
    return length(table.source_types)
end

end # module SourceMap
