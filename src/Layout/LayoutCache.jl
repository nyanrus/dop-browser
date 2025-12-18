# LayoutCache - Thread-safe layout caching and precaching system
#
# Provides fast layout retrieval and incremental reflow by caching computed layouts
# and tracking dependencies between nodes. Supports multi-threaded access with
# proper synchronization.

module LayoutCache

export LayoutCacheEntry, LayoutCache
export cache_layout!, get_cached_layout, has_cached_layout
export invalidate_node!, invalidate_subtree!, clear_cache!
export precache_layouts!, get_cache_stats

"""
    LayoutCacheEntry

A cached layout entry with metadata.
"""
mutable struct LayoutCacheEntry
    node_id::UInt32
    
    # Layout data (snapshot)
    x::Float32
    y::Float32
    width::Float32
    height::Float32
    content_width::Float32
    content_height::Float32
    
    # Cache metadata
    timestamp::Float64      # When this was cached
    access_count::Int64     # Number of times accessed
    last_access::Float64    # Last access time
    is_valid::Bool          # Is this entry still valid?
    
    # Dependency tracking
    parent_id::UInt32
    children_ids::Vector{UInt32}
    depends_on::Vector{UInt32}  # Other nodes this depends on
    
    # Hash for change detection
    content_hash::UInt64    # Hash of content that affects layout
end

"""
    LayoutCache

Thread-safe cache for computed layouts.
Uses ReentrantLock for thread safety.
"""
mutable struct LayoutCache
    # Cache storage
    entries::Dict{UInt32, LayoutCacheEntry}
    
    # Thread safety
    lock::ReentrantLock
    
    # Configuration
    max_capacity::Int
    eviction_enabled::Bool
    
    # Statistics
    hits::Int64
    misses::Int64
    invalidations::Int64
    
    # Precaching queue
    precache_queue::Vector{UInt32}
    
    function LayoutCache(; capacity::Int = 1000, enable_eviction::Bool = true)
        new(
            Dict{UInt32, LayoutCacheEntry}(),
            ReentrantLock(),
            capacity,
            enable_eviction,
            0,  # hits
            0,  # misses
            0,  # invalidations
            UInt32[]  # precache_queue
        )
    end
end

"""
    cache_layout!(cache::LayoutCache, node_id::UInt32, x::Float32, y::Float32,
                  width::Float32, height::Float32;
                  parent_id::UInt32 = UInt32(0),
                  children::Vector{UInt32} = UInt32[],
                  content_hash::UInt64 = UInt64(0))

Cache a computed layout for a node. Thread-safe.
"""
function cache_layout!(cache::LayoutCache, node_id::UInt32,
                      x::Float32, y::Float32, width::Float32, height::Float32;
                      parent_id::UInt32 = UInt32(0),
                      children::Vector{UInt32} = UInt32[],
                      content_hash::UInt64 = UInt64(0))
    lock(cache.lock) do
        # Check capacity and evict if needed
        if cache.eviction_enabled && length(cache.entries) >= cache.max_capacity
            evict_lru!(cache)
        end
        
        # Create entry
        entry = LayoutCacheEntry(
            node_id,
            x, y, width, height,
            width, height,  # content size same as size for now
            time(),  # timestamp
            0,  # access_count
            time(),  # last_access
            true,  # is_valid
            parent_id,
            copy(children),
            UInt32[],  # depends_on
            content_hash
        )
        
        cache.entries[node_id] = entry
    end
    
    nothing
end

"""
    get_cached_layout(cache::LayoutCache, node_id::UInt32) -> Union{LayoutCacheEntry, Nothing}

Retrieve a cached layout. Returns nothing if not found or invalid. Thread-safe.
"""
function get_cached_layout(cache::LayoutCache, node_id::UInt32)::Union{LayoutCacheEntry, Nothing}
    lock(cache.lock) do
        if haskey(cache.entries, node_id)
            entry = cache.entries[node_id]
            
            if entry.is_valid
                # Update access statistics
                entry.access_count += 1
                entry.last_access = time()
                cache.hits += 1
                return entry
            else
                cache.misses += 1
                return nothing
            end
        else
            cache.misses += 1
            return nothing
        end
    end
end

"""
    has_cached_layout(cache::LayoutCache, node_id::UInt32) -> Bool

Check if a valid cached layout exists for a node. Thread-safe.
"""
function has_cached_layout(cache::LayoutCache, node_id::UInt32)::Bool
    lock(cache.lock) do
        haskey(cache.entries, node_id) && cache.entries[node_id].is_valid
    end
end

"""
    invalidate_node!(cache::LayoutCache, node_id::UInt32)

Invalidate a single node's cached layout. Thread-safe.
"""
function invalidate_node!(cache::LayoutCache, node_id::UInt32)
    lock(cache.lock) do
        if haskey(cache.entries, node_id)
            cache.entries[node_id].is_valid = false
            cache.invalidations += 1
        end
    end
    
    nothing
end

"""
    invalidate_subtree!(cache::LayoutCache, root_id::UInt32)

Invalidate a node and all its descendants. Thread-safe.
Traverses the dependency graph to invalidate all affected nodes.
"""
function invalidate_subtree!(cache::LayoutCache, root_id::UInt32)
    lock(cache.lock) do
        # Use BFS to invalidate all descendants
        to_invalidate = [root_id]
        processed = Set{UInt32}()
        
        while !isempty(to_invalidate)
            current_id = pop!(to_invalidate)
            
            if current_id in processed
                continue
            end
            
            push!(processed, current_id)
            
            if haskey(cache.entries, current_id)
                entry = cache.entries[current_id]
                entry.is_valid = false
                cache.invalidations += 1
                
                # Add children to invalidation queue
                for child_id in entry.children_ids
                    if !(child_id in processed)
                        push!(to_invalidate, child_id)
                    end
                end
            end
        end
    end
    
    nothing
end

"""
    clear_cache!(cache::LayoutCache)

Clear all cached entries. Thread-safe.
"""
function clear_cache!(cache::LayoutCache)
    lock(cache.lock) do
        empty!(cache.entries)
        cache.invalidations += length(cache.entries)
    end
    
    nothing
end

"""
    evict_lru!(cache::LayoutCache)

Evict least recently used entries. Called automatically when capacity is reached.
Not thread-safe - must be called within a lock.
"""
function evict_lru!(cache::LayoutCache)
    if isempty(cache.entries)
        return
    end
    
    # Find LRU entry
    lru_id = UInt32(0)
    lru_time = Inf
    
    for (node_id, entry) in cache.entries
        if entry.last_access < lru_time
            lru_time = entry.last_access
            lru_id = node_id
        end
    end
    
    if lru_id != UInt32(0)
        delete!(cache.entries, lru_id)
    end
end

"""
    precache_layouts!(cache::LayoutCache, node_ids::Vector{UInt32})

Add nodes to the precaching queue for future computation.
These will be computed on next layout pass even if not immediately needed.
Thread-safe.
"""
function precache_layouts!(cache::LayoutCache, node_ids::Vector{UInt32})
    lock(cache.lock) do
        append!(cache.precache_queue, node_ids)
        unique!(cache.precache_queue)
    end
    
    nothing
end

"""
    get_precache_queue(cache::LayoutCache) -> Vector{UInt32}

Get and clear the precache queue. Thread-safe.
"""
function get_precache_queue(cache::LayoutCache)::Vector{UInt32}
    lock(cache.lock) do
        queue = copy(cache.precache_queue)
        empty!(cache.precache_queue)
        return queue
    end
end

"""
    get_cache_stats(cache::LayoutCache) -> NamedTuple

Get cache statistics. Thread-safe.
"""
function get_cache_stats(cache::LayoutCache)
    lock(cache.lock) do
        total_requests = cache.hits + cache.misses
        hit_rate = total_requests > 0 ? cache.hits / total_requests : 0.0
        
        return (
            size = length(cache.entries),
            capacity = cache.max_capacity,
            hits = cache.hits,
            misses = cache.misses,
            hit_rate = hit_rate,
            invalidations = cache.invalidations
        )
    end
end

"""
    compute_content_hash(width::Float32, height::Float32, 
                        style_properties...) -> UInt64

Compute a hash of content that affects layout.
Used for change detection.
"""
function compute_content_hash(width::Float32, height::Float32)::UInt64
    # Simple hash combining width and height
    # In full implementation, would include:
    # - All CSS properties affecting layout
    # - Children count
    # - Text content hash
    hash((width, height))
end

end # module LayoutCache
