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
"""
module Styles

using ..Properties: Color, parse_color, Direction, Pack, Align, Size, Inset, Offset, Gap,
                    PropertyValue, DIRECTION_DOWN, PACK_START, ALIGN_STRETCH

export StyleDeclaration, StyleTable, FlatStyle, StyleResolver
export create_style!, inherit_style!, flatten_styles!, get_style, style_count
export resolve_archetype!, get_archetype_styles

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
    return FlatStyle(
        DIRECTION_DOWN, PACK_START, ALIGN_STRETCH,
        0.0f0, 0.0f0,  # gap
        0.0f0, 0.0f0,  # size
        0.0f0, 0.0f0,  # min size
        typemax(Float32), typemax(Float32),  # max size
        0.0f0, 0.0f0, 0.0f0, 0.0f0,  # inset
        0.0f0, 0.0f0, 0.0f0, 0.0f0,  # offset
        0x00, 0x00, 0x00, 0x00,  # fill (transparent)
        0.0f0,  # round
        UInt64(0)  # hash
    )
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
    
    # Start with defaults
    props = Dict{Symbol, Any}(
        :direction => DIRECTION_DOWN,
        :pack => PACK_START,
        :align => ALIGN_STRETCH,
        :gap_row => 0.0f0,
        :gap_col => 0.0f0,
        :width => 0.0f0,
        :height => 0.0f0,
        :min_width => 0.0f0,
        :min_height => 0.0f0,
        :max_width => typemax(Float32),
        :max_height => typemax(Float32),
        :inset_top => 0.0f0,
        :inset_right => 0.0f0,
        :inset_bottom => 0.0f0,
        :inset_left => 0.0f0,
        :offset_top => 0.0f0,
        :offset_right => 0.0f0,
        :offset_bottom => 0.0f0,
        :offset_left => 0.0f0,
        :fill_r => 0x00,
        :fill_g => 0x00,
        :fill_b => 0x00,
        :fill_a => 0x00,
        :round => 0.0f0
    )
    
    # Apply parent styles first (in order)
    for parent_id in decl.parent_ids
        parent_flat = flatten_style(table, parent_id, copy(visited))
        # Copy parent properties
        props[:direction] = parent_flat.direction
        props[:pack] = parent_flat.pack
        props[:align] = parent_flat.align
        props[:gap_row] = parent_flat.gap_row
        props[:gap_col] = parent_flat.gap_col
        props[:width] = parent_flat.width
        props[:height] = parent_flat.height
        props[:min_width] = parent_flat.min_width
        props[:min_height] = parent_flat.min_height
        props[:max_width] = parent_flat.max_width
        props[:max_height] = parent_flat.max_height
        props[:inset_top] = parent_flat.inset_top
        props[:inset_right] = parent_flat.inset_right
        props[:inset_bottom] = parent_flat.inset_bottom
        props[:inset_left] = parent_flat.inset_left
        props[:offset_top] = parent_flat.offset_top
        props[:offset_right] = parent_flat.offset_right
        props[:offset_bottom] = parent_flat.offset_bottom
        props[:offset_left] = parent_flat.offset_left
        props[:fill_r] = parent_flat.fill_r
        props[:fill_g] = parent_flat.fill_g
        props[:fill_b] = parent_flat.fill_b
        props[:fill_a] = parent_flat.fill_a
        props[:round] = parent_flat.round
    end
    
    # Apply own properties (override parents)
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
    
    return FlatStyle(
        props[:direction], props[:pack], props[:align],
        Float32(props[:gap_row]), Float32(props[:gap_col]),
        Float32(props[:width]), Float32(props[:height]),
        Float32(props[:min_width]), Float32(props[:min_height]),
        Float32(props[:max_width]), Float32(props[:max_height]),
        Float32(props[:inset_top]), Float32(props[:inset_right]),
        Float32(props[:inset_bottom]), Float32(props[:inset_left]),
        Float32(props[:offset_top]), Float32(props[:offset_right]),
        Float32(props[:offset_bottom]), Float32(props[:offset_left]),
        UInt8(props[:fill_r]), UInt8(props[:fill_g]),
        UInt8(props[:fill_b]), UInt8(props[:fill_a]),
        Float32(props[:round]),
        h
    )
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
