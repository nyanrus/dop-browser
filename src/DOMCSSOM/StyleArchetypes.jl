"""
    StyleArchetypes

Archetype-based style system for efficient style computation.

Archetypes represent unique combinations of CSS classes. Each unique
combination is solved once, and results are copied to all nodes sharing
that archetype. This enables efficient bulk styling via memcpy-style operations.
"""
module StyleArchetypes

export StyleProperty, Archetype, ArchetypeTable, get_or_create_archetype!
export apply_archetype!, get_archetype, archetype_count

"""
    StyleProperty

A computed style property value.

# Fields
- `property_id::UInt32` - Property identifier (e.g., interned "width", "height")
- `value::Float32` - Numeric value
- `unit::UInt8` - Unit type (0=px, 1=%, 2=em, 3=rem, 4=auto)
"""
struct StyleProperty
    property_id::UInt32
    value::Float32
    unit::UInt8
end

"""
    Archetype

A unique combination of CSS classes and their computed style properties.

# Fields
- `class_ids::Vector{UInt32}` - Sorted list of interned class name IDs
- `properties::Vector{StyleProperty}` - Computed style properties
- `hash::UInt64` - Pre-computed hash for fast comparison
"""
struct Archetype
    class_ids::Vector{UInt32}
    properties::Vector{StyleProperty}
    hash::UInt64
    
    function Archetype(class_ids::Vector{UInt32}, properties::Vector{StyleProperty})
        sorted_ids = sort(class_ids)
        h = hash(sorted_ids)
        new(sorted_ids, properties, h)
    end
end

"""
    ArchetypeTable

Table of unique style archetypes.

# Fields
- `archetypes::Vector{Archetype}` - All unique archetypes (1-indexed)
- `lookup::Dict{UInt64, Vector{UInt32}}` - Hash to archetype IDs (for collision handling)
- `default_properties::Vector{StyleProperty}` - Default style properties
"""
mutable struct ArchetypeTable
    archetypes::Vector{Archetype}
    lookup::Dict{UInt64, Vector{UInt32}}
    default_properties::Vector{StyleProperty}
    
    function ArchetypeTable()
        new(Archetype[], Dict{UInt64, Vector{UInt32}}(), StyleProperty[])
    end
end

"""
    archetype_count(table::ArchetypeTable) -> Int

Return the number of archetypes in the table.
"""
function archetype_count(table::ArchetypeTable)::Int
    return length(table.archetypes)
end

"""
    compute_hash(class_ids::Vector{UInt32}) -> UInt64

Compute a hash for a set of class IDs.
"""
function compute_hash(class_ids::Vector{UInt32})::UInt64
    return hash(sort(class_ids))
end

"""
    get_or_create_archetype!(table::ArchetypeTable, class_ids::Vector{UInt32}) -> UInt32

Get or create an archetype for the given class combination.

If an archetype with the exact same classes already exists, returns its ID.
Otherwise, creates a new archetype with computed styles.

# Arguments
- `table::ArchetypeTable` - The archetype table
- `class_ids::Vector{UInt32}` - Interned class name IDs

# Returns
- `UInt32` - Archetype ID (1-indexed)
"""
function get_or_create_archetype!(table::ArchetypeTable, class_ids::Vector{UInt32})::UInt32
    sorted_ids = sort(class_ids)
    h = hash(sorted_ids)
    
    # Check for existing archetype
    if haskey(table.lookup, h)
        for arch_id in table.lookup[h]
            arch = table.archetypes[arch_id]
            if arch.class_ids == sorted_ids
                return arch_id
            end
        end
    end
    
    # Create new archetype
    properties = compute_properties(sorted_ids, table.default_properties)
    archetype = Archetype(sorted_ids, properties)
    push!(table.archetypes, archetype)
    arch_id = UInt32(length(table.archetypes))
    
    # Add to lookup
    if !haskey(table.lookup, h)
        table.lookup[h] = UInt32[]
    end
    push!(table.lookup[h], arch_id)
    
    return arch_id
end

"""
    compute_properties(class_ids::Vector{UInt32}, defaults::Vector{StyleProperty}) -> Vector{StyleProperty}

Compute style properties for a class combination.
This is a placeholder that would integrate with CSS parsing.
"""
function compute_properties(class_ids::Vector{UInt32}, defaults::Vector{StyleProperty})::Vector{StyleProperty}
    # For now, return a copy of defaults
    # In a full implementation, this would cascade CSS rules
    return copy(defaults)
end

"""
    apply_archetype!(target_properties::Vector{Float32}, archetype::Archetype, property_offset::Int)

Apply archetype properties to a contiguous array of floats.
This enables bulk memcpy-style style application.

# Arguments
- `target_properties::Vector{Float32}` - Target property array
- `archetype::Archetype` - Source archetype
- `property_offset::Int` - Offset in target array
"""
function apply_archetype!(target_properties::Vector{Float32}, archetype::Archetype, property_offset::Int)
    for (i, prop) in enumerate(archetype.properties)
        idx = property_offset + i
        if idx <= length(target_properties)
            target_properties[idx] = prop.value
        end
    end
end

"""
    get_archetype(table::ArchetypeTable, id::UInt32) -> Union{Archetype, Nothing}

Get an archetype by ID.
"""
function get_archetype(table::ArchetypeTable, id::UInt32)::Union{Archetype, Nothing}
    if id == 0 || id > length(table.archetypes)
        return nothing
    end
    return table.archetypes[id]
end

end # module StyleArchetypes
