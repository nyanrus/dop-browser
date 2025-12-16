"""
    StringInterner

Zero-copy string interning for efficient memory usage and fast comparisons.

Strings are stored once and referenced by UInt32 IDs, enabling:
- O(1) equality checks via ID comparison
- Reduced memory footprint through deduplication
- Cache-friendly sequential access patterns

This is the canonical StringInterner implementation used throughout DOPBrowser.
Other modules that need string interning (e.g., DOMCSSOM) import this module
rather than maintaining their own copies.
"""
module StringInterner

export StringPool, intern!, get_string, get_id

"""
    StringPool

A pool for interning strings. Each unique string is stored once and
assigned a unique UInt32 identifier.

# Fields
- `strings::Vector{String}` - Interned string storage (1-indexed)
- `lookup::Dict{String, UInt32}` - Fast string-to-ID mapping
"""
mutable struct StringPool
    strings::Vector{String}
    lookup::Dict{String, UInt32}
    
    function StringPool()
        new(String[], Dict{String, UInt32}())
    end
end

"""
    intern!(pool::StringPool, s::AbstractString) -> UInt32

Intern a string and return its unique ID. If the string already exists
in the pool, returns the existing ID without allocating new storage.

# Arguments
- `pool::StringPool` - The string pool
- `s::AbstractString` - String to intern

# Returns
- `UInt32` - Unique identifier for the interned string
"""
function intern!(pool::StringPool, s::AbstractString)::UInt32
    str = String(s)
    id = get(pool.lookup, str, UInt32(0))
    if id != 0
        return id
    end
    
    push!(pool.strings, str)
    new_id = UInt32(length(pool.strings))
    pool.lookup[str] = new_id
    return new_id
end

"""
    get_string(pool::StringPool, id::UInt32) -> String

Retrieve the string associated with the given ID.

# Arguments
- `pool::StringPool` - The string pool
- `id::UInt32` - String identifier (1-based index)

# Returns
- `String` - The interned string

# Throws
- `BoundsError` if ID is out of range
"""
function get_string(pool::StringPool, id::UInt32)::String
    if id == 0 || id > length(pool.strings)
        throw(BoundsError(pool.strings, id))
    end
    return pool.strings[id]
end

"""
    get_id(pool::StringPool, s::AbstractString) -> Union{UInt32, Nothing}

Look up the ID for a string without interning it.

# Arguments
- `pool::StringPool` - The string pool
- `s::AbstractString` - String to look up

# Returns
- `UInt32` if string is interned, `nothing` otherwise
"""
function get_id(pool::StringPool, s::AbstractString)::Union{UInt32, Nothing}
    str = String(s)
    id = get(pool.lookup, str, UInt32(0))
    return id == 0 ? nothing : id
end

end # module StringInterner
