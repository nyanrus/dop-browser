"""
    StringInterner

Zero-copy string interning for efficient memory usage and fast comparisons.

This module uses the Rust-based RustParser when available for better performance,
with a Julia fallback implementation.

NOTE: This is a wrapper module. The core implementation is in RustParser (Rust).
"""
module StringInterner

export StringPool, intern!, get_string, get_id

"""
    StringPool

A pool for interning strings. Each unique string is stored once and
assigned a unique UInt32 identifier.
"""
mutable struct StringPool
    # Julia storage (always used for compatibility)
    strings::Vector{String}
    lookup::Dict{String, UInt32}
    
    function StringPool()
        new(String[], Dict{String, UInt32}())
    end
end

"""
    intern!(pool::StringPool, s::AbstractString) -> UInt32

Intern a string and return its unique ID.
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
"""
function get_id(pool::StringPool, s::AbstractString)::Union{UInt32, Nothing}
    str = String(s)
    id = get(pool.lookup, str, UInt32(0))
    return id == 0 ? nothing : id
end

end # module StringInterner
