"""
    Styles

Content-- style system with AOT inheritance flattening.

## Style Declarations
Styles are defined at compile time and all inheritance is flattened:
```
style Base(Fill: #FFF);
style Derived(use: Base, Border: 1px);  // Inherits Base, flattened at compile
```

## Key Features
- All inheritance resolved at AOT (zero runtime lookup cost)
- Archetype-based deduplication for efficient memory usage
- Direct binary patching for WASM runtime updates
- Metadata-driven property operations for maintainability
"""
module Styles

using ..Properties: Color, parse_color, Direction, Pack, Align, Size, Inset, Offset, Gap,
                    PropertyValue, DIRECTION_DOWN, PACK_START, ALIGN_STRETCH

export StyleDeclaration, StyleTable, FlatStyle, StyleResolver
export create_style!, inherit_style!, flatten_styles!, get_style, style_count
export resolve_archetype!, get_archetype_styles
export FLAT_STYLE_FIELDS

# ============================================================================
# Metadata-driven FlatStyle fields definition
# Format: (name::Symbol, type::DataType, default_value)
# This metadata enables loop-based operations instead of repetitive code
#
# NOTE: This is intentionally a SUBSET of the full PROPERTY_FIELDS in Properties.jl.
# FlatStyle represents the flattened style output used for layout, while PropertyTable
# contains all dynamic layout properties including per-node overrides like scroll state.
# The field order MUST match the FlatStyle struct definition exactly.
# ============================================================================
const FLAT_STYLE_FIELDS = [
    # Layout
    (:direction, Direction, DIRECTION_DOWN),
    (:pack, Pack, PACK_START),
    (:align, Align, ALIGN_STRETCH),
    (:gap_row, Float32, 0.0f0),
    (:gap_col, Float32, 0.0f0),
    # Dimensions
    (:width, Float32, 0.0f0),
    (:height, Float32, 0.0f0),
    (:min_width, Float32, 0.0f0),
    (:min_height, Float32, 0.0f0),
    (:max_width, Float32, typemax(Float32)),
    (:max_height, Float32, typemax(Float32)),
    # Box model (inset = padding, offset = margin in Content-- semantics)
    (:inset_top, Float32, 0.0f0),
    (:inset_right, Float32, 0.0f0),
    (:inset_bottom, Float32, 0.0f0),
    (:inset_left, Float32, 0.0f0),
    (:offset_top, Float32, 0.0f0),
    (:offset_right, Float32, 0.0f0),
    (:offset_bottom, Float32, 0.0f0),
    (:offset_left, Float32, 0.0f0),
    # Colors
    (:fill_r, UInt8, 0x00),
    (:fill_g, UInt8, 0x00),
    (:fill_b, UInt8, 0x00),
    (:fill_a, UInt8, 0x00),
    # Border radius
    (:round, Float32, 0.0f0),
]

"Generate default props dictionary from FLAT_STYLE_FIELDS metadata."
function _default_style_props()::Dict{Symbol, Any}
    return Dict{Symbol, Any}(name => default for (name, _, default) in FLAT_STYLE_FIELDS)
end

"""
    StyleDeclaration

A named style declaration with optional inheritance.

# Fields
- `name_id::UInt32` - Interned style name
- `parent_ids::Vector{UInt32}` - Styles inherited via `use:`
- `properties::Dict{Symbol, PropertyValue}` - Declared properties
- `is_flattened::Bool` - Whether inheritance has been resolved
"""
mutable struct StyleDeclaration
    name_id::UInt32
    parent_ids::Vector{UInt32}
    properties::Dict{Symbol, PropertyValue}
    is_flattened::Bool
    
    function StyleDeclaration(name_id::UInt32)
        new(name_id, UInt32[], Dict{Symbol, PropertyValue}(), false)
    end
end

"""
    FlatStyle

A completely flattened style with all inheritance resolved.
Optimized for direct memcpy to layout arrays.

Fields are defined by FLAT_STYLE_FIELDS metadata for maintainability.
"""
struct FlatStyle
    # Layout
    direction::Direction
    pack::Pack
    align::Align
    gap_row::Float32
    gap_col::Float32
    
    # Dimensions
    width::Float32
    height::Float32
    min_width::Float32
    min_height::Float32
    max_width::Float32
    max_height::Float32
    
    # Box model
    inset_top::Float32
    inset_right::Float32
    inset_bottom::Float32
    inset_left::Float32
    offset_top::Float32
    offset_right::Float32
    offset_bottom::Float32
    offset_left::Float32
    
    # Colors
    fill_r::UInt8
    fill_g::UInt8
    fill_b::UInt8
    fill_a::UInt8
    
    # Border radius
    round::Float32
    
    # Hash for archetype lookup
    hash::UInt64
end

"""
    default_flat_style() -> FlatStyle

Create a default flat style with all properties at their defaults.
"""
function default_flat_style()::FlatStyle
    # Use metadata to build defaults tuple
    defaults = tuple((default for (_, _, default) in FLAT_STYLE_FIELDS)..., UInt64(0))
    return FlatStyle(defaults...)
end

"Copy all properties from FlatStyle to props dictionary using metadata."
function _copy_flat_to_props!(props::Dict{Symbol, Any}, flat::FlatStyle)
    for (name, _, _) in FLAT_STYLE_FIELDS
        props[name] = getfield(flat, name)
    end
end

"""
    StyleTable

Table of style declarations with support for AOT flattening.
"""
mutable struct StyleTable
    declarations::Vector{StyleDeclaration}
    flattened::Vector{FlatStyle}
    name_lookup::Dict{UInt32, UInt32}  # name_id -> style_id
    
    function StyleTable()
        new(StyleDeclaration[], FlatStyle[], Dict{UInt32, UInt32}())
    end
end

"""
    style_count(table::StyleTable) -> Int

Return the number of styles.
"""
function style_count(table::StyleTable)::Int
    return length(table.declarations)
end

"""
    create_style!(table::StyleTable, name_id::UInt32) -> UInt32

Create a new style declaration.
"""
function create_style!(table::StyleTable, name_id::UInt32)::UInt32
    decl = StyleDeclaration(name_id)
    push!(table.declarations, decl)
    id = UInt32(length(table.declarations))
    table.name_lookup[name_id] = id
    return id
end

"""
    set_style_property!(table::StyleTable, style_id::UInt32, prop::Symbol, value)

Set a property on a style declaration.
"""
function set_style_property!(table::StyleTable, style_id::UInt32, prop::Symbol, value)
    if style_id == 0 || style_id > length(table.declarations)
        return
    end
    table.declarations[style_id].properties[prop] = value
    table.declarations[style_id].is_flattened = false
end

"""
    inherit_style!(table::StyleTable, style_id::UInt32, parent_id::UInt32)

Add a parent style (via `use:` declaration).
"""
function inherit_style!(table::StyleTable, style_id::UInt32, parent_id::UInt32)
    if style_id == 0 || style_id > length(table.declarations)
        return
    end
    if parent_id == 0 || parent_id > length(table.declarations)
        return
    end
    push!(table.declarations[style_id].parent_ids, parent_id)
    table.declarations[style_id].is_flattened = false
end

"""
    flatten_style(table::StyleTable, style_id::UInt32, 
                  visited::Set{UInt32}=Set{UInt32}()) -> FlatStyle

Recursively flatten a style by resolving all inheritance.
Uses FLAT_STYLE_FIELDS metadata to avoid repetitive code.
"""
function flatten_style(table::StyleTable, style_id::UInt32,
                       visited::Set{UInt32}=Set{UInt32}())::FlatStyle
    if style_id == 0 || style_id > length(table.declarations)
        return default_flat_style()
    end
    
    # Cycle detection
    if style_id in visited
        return default_flat_style()
    end
    push!(visited, style_id)
    
    decl = table.declarations[style_id]
    
    # Start with defaults from metadata
    props = _default_style_props()
    
    # Apply parent styles first (in order) - use metadata-driven copy
    for parent_id in decl.parent_ids
        parent_flat = flatten_style(table, parent_id, copy(visited))
        _copy_flat_to_props!(props, parent_flat)
    end
    
    # Apply own properties (override parents) - handle compound properties
    for (key, value) in decl.properties
        if key == :fill && value isa Color
            props[:fill_r] = value.r
            props[:fill_g] = value.g
            props[:fill_b] = value.b
            props[:fill_a] = value.a
        elseif key == :inset && value isa Inset
            props[:inset_top] = value.top
            props[:inset_right] = value.right
            props[:inset_bottom] = value.bottom
            props[:inset_left] = value.left
        elseif key == :offset && value isa Offset
            props[:offset_top] = value.top
            props[:offset_right] = value.right
            props[:offset_bottom] = value.bottom
            props[:offset_left] = value.left
        elseif key == :gap && value isa Gap
            props[:gap_row] = value.row
            props[:gap_col] = value.column
        elseif haskey(props, key)
            props[key] = value
        end
    end
    
    # Compute hash for archetype lookup
    h = hash((props[:direction], props[:pack], props[:align], 
              props[:fill_r], props[:fill_g], props[:fill_b], props[:fill_a],
              props[:width], props[:height]))
    
    # Build FlatStyle from props using metadata for type conversion
    values = Any[]
    for (name, T, _) in FLAT_STYLE_FIELDS
        push!(values, convert(T, props[name]))
    end
    push!(values, h)  # Add hash
    
    return FlatStyle(values...)
end

"""
    flatten_styles!(table::StyleTable)

Flatten all styles (AOT operation).
"""
function flatten_styles!(table::StyleTable)
    empty!(table.flattened)
    for i in 1:length(table.declarations)
        flat = flatten_style(table, UInt32(i))
        push!(table.flattened, flat)
        table.declarations[i].is_flattened = true
    end
end

"""
    get_style(table::StyleTable, style_id::UInt32) -> Union{FlatStyle, Nothing}

Get a flattened style by ID.
"""
function get_style(table::StyleTable, style_id::UInt32)::Union{FlatStyle, Nothing}
    if style_id == 0 || style_id > length(table.flattened)
        return nothing
    end
    return table.flattened[style_id]
end

"""
    StyleResolver

Resolves styles to archetypes for batch processing.
Archetypes allow memcpy-style style application to all nodes sharing the same style.
"""
mutable struct StyleResolver
    # Archetype lookup: hash -> archetype_id
    archetype_lookup::Dict{UInt64, UInt32}
    # Flat styles by archetype
    archetype_styles::Vector{FlatStyle}
    
    function StyleResolver()
        new(Dict{UInt64, UInt32}(), FlatStyle[])
    end
end

"""
    resolve_archetype!(resolver::StyleResolver, style::FlatStyle) -> UInt32

Get or create an archetype ID for a style.
"""
function resolve_archetype!(resolver::StyleResolver, style::FlatStyle)::UInt32
    if haskey(resolver.archetype_lookup, style.hash)
        return resolver.archetype_lookup[style.hash]
    end
    
    push!(resolver.archetype_styles, style)
    id = UInt32(length(resolver.archetype_styles))
    resolver.archetype_lookup[style.hash] = id
    return id
end

"""
    get_archetype_styles(resolver::StyleResolver, archetype_id::UInt32) -> Union{FlatStyle, Nothing}

Get the flattened style for an archetype.
"""
function get_archetype_styles(resolver::StyleResolver, archetype_id::UInt32)::Union{FlatStyle, Nothing}
    if archetype_id == 0 || archetype_id > length(resolver.archetype_styles)
        return nothing
    end
    return resolver.archetype_styles[archetype_id]
end

end # module Styles
