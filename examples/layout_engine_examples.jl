"""
Flexbox Layout Examples

Demonstrates the CSS Flexbox layout capabilities of the DOPBrowser layout engine.
"""

using DOPBrowser.Layout

# ============================================================================
# Example 1: Basic Flex Row Layout
# ============================================================================

println("Example 1: Basic Flex Row Layout")
println("=" ^ 50)

# Create layout data
layout = LayoutData()
resize_layout!(layout, 10)

# Setup container (node 1) as flex container
layout.display[1] = DISPLAY_FLEX
layout.width[1] = 800.0f0
layout.height[1] = 600.0f0
layout.x[1] = 0.0f0
layout.y[1] = 0.0f0

# Simulate a simple parent-child structure
parents = UInt32[0, 1, 1, 1]  # Root, then 3 children of node 1
first_children = UInt32[1, 2, 0, 0]  # Node 1 has child 2
next_siblings = UInt32[0, 0, 3, 4]  # 2->3->4 are siblings

# Add three flex items (children of container)
for i in 2:4
    layout.width[i] = 100.0f0
    layout.height[i] = 50.0f0
    layout.margin_left[i] = 10.0f0
    layout.margin_right[i] = 10.0f0
end

# Compute flexbox layout
compute_flexbox_layout!(layout, 1, first_children, next_siblings)

# Display results
println("Container: ($(layout.x[1]), $(layout.y[1])) size: $(layout.width[1])x$(layout.height[1])")
for i in 2:4
    println("Item $i: ($(layout.x[i]), $(layout.y[i])) size: $(layout.width[i])x$(layout.height[i])")
end

println()

# ============================================================================
# Example 2: Flexbox with Justify Content
# ============================================================================

println("Example 2: Flexbox with Space-Between")
println("=" ^ 50)

# Reset layout
layout = LayoutData()
resize_layout!(layout, 10)

# Setup container with space-between justification
layout.display[1] = DISPLAY_FLEX
layout.width[1] = 800.0f0
layout.height[1] = 200.0f0
layout.x[1] = 0.0f0
layout.y[1] = 0.0f0

# NOTE: In full implementation, these would be settable:
# layout.flex_direction[1] = FLEX_DIRECTION_ROW
# layout.justify_content[1] = JUSTIFY_CONTENT_BETWEEN

# Add flex items
for i in 2:5
    layout.width[i] = 150.0f0
    layout.height[i] = 100.0f0
end

parents = UInt32[0, 1, 1, 1, 1]
first_children = UInt32[1, 2, 0, 0, 0]
next_siblings = UInt32[0, 0, 3, 4, 5]

compute_flexbox_layout!(layout, 1, first_children, next_siblings)

println("Container: $(layout.width[1])px wide")
for i in 2:5
    println("Item $i: x=$(layout.x[i])px")
end

println()

# ============================================================================
# Example 3: Layout Caching
# ============================================================================

println("Example 3: Thread-Safe Layout Caching")
println("=" ^ 50)

# Create a cache
cache = LayoutCache(capacity=100)

# Cache some layouts
cache_layout!(cache, UInt32(1), 0.0f0, 0.0f0, 800.0f0, 600.0f0,
             children=[UInt32(2), UInt32(3), UInt32(4)])

cache_layout!(cache, UInt32(2), 10.0f0, 10.0f0, 100.0f0, 50.0f0,
             parent_id=UInt32(1))

cache_layout!(cache, UInt32(3), 120.0f0, 10.0f0, 100.0f0, 50.0f0,
             parent_id=UInt32(1))

# Retrieve from cache
if has_cached_layout(cache, UInt32(2))
    entry = get_cached_layout(cache, UInt32(2))
    println("Retrieved from cache: Node 2 at ($(entry.x), $(entry.y))")
end

# Get cache statistics
stats = get_cache_stats(cache)
println("\nCache Statistics:")
println("  Size: $(stats.size)/$(stats.capacity)")
println("  Hits: $(stats.hits)")
println("  Misses: $(stats.misses)")
println("  Hit Rate: $(round(stats.hit_rate * 100, digits=2))%")

# Invalidate a subtree
println("\nInvalidating subtree rooted at node 1...")
invalidate_subtree!(cache, UInt32(1))

# Try to retrieve again
if has_cached_layout(cache, UInt32(2))
    println("Node 2 still cached (shouldn't happen)")
else
    println("Node 2 correctly invalidated")
end

println()

# ============================================================================
# Example 4: Precaching
# ============================================================================

println("Example 4: Precaching for Performance")
println("=" ^ 50)

cache = LayoutCache(capacity=1000)

# Queue nodes for precaching
nodes_to_precache = UInt32[10, 11, 12, 13, 14, 15]
println("Queuing $(length(nodes_to_precache)) nodes for precaching")
precache_layouts!(cache, nodes_to_precache)

# Get the precache queue
queue = get_precache_queue(cache)
println("Precache queue contains $(length(queue)) nodes: $queue")

# In a real layout pass, these would be computed
println("These nodes will be computed on next layout pass")
println("even if not immediately visible (for smooth scrolling)")

println()

# ============================================================================
# Example 5: Multi-threaded Caching (Demonstration)
# ============================================================================

println("Example 5: Thread-Safe Operations")
println("=" ^ 50)

cache = LayoutCache(capacity=1000)

println("Demonstrating thread-safety...")
println("(In production, this would run on multiple threads)")

# Simulate concurrent access
using Base.Threads

# This would be run on different threads in production
for i in 1:10
    node_id = UInt32(i)
    
    # Thread 1: Write to cache
    cache_layout!(cache, node_id, 
                 Float32(i * 10), Float32(i * 10),
                 100.0f0, 100.0f0)
    
    # Thread 2: Read from cache
    if has_cached_layout(cache, node_id)
        entry = get_cached_layout(cache, node_id)
        println("  Node $i cached at ($(entry.x), $(entry.y))")
    end
    
    # Thread 3: Get stats (safe to call concurrently)
    stats = get_cache_stats(cache)
end

println("\nAll operations completed safely")
println("Final cache size: $(get_cache_stats(cache).size)")

println()

# ============================================================================
# Example 6: Incremental Reflow
# ============================================================================

println("Example 6: Incremental Reflow")
println("=" ^ 50)

layout = LayoutData()
resize_layout!(layout, 20)
cache = LayoutCache(capacity=100)

# Initial layout
layout.display[1] = DISPLAY_FLEX
layout.width[1] = 1000.0f0
layout.height[1] = 600.0f0

for i in 2:10
    layout.width[i] = 100.0f0
    layout.height[i] = 80.0f0
    cache_layout!(cache, UInt32(i), 
                 Float32((i-2) * 110), 0.0f0,
                 layout.width[i], layout.height[i],
                 parent_id=UInt32(1))
end

println("Initial layout computed and cached")
println("Cache size: $(get_cache_stats(cache).size)")

# Simulate a change to one element
println("\nChanging width of element 5...")
layout.width[5] = 200.0f0  # Make it wider

# Invalidate affected nodes
invalidate_subtree!(cache, UInt32(5))

# In a real implementation, only subtree rooted at 5 would recompute
println("Invalidated node 5 and descendants")
println("Only affected subtree needs recomputation")
println("Unchanged nodes (2, 3, 4, 6-10) can use cached layouts")

# Check which nodes are still valid
valid_count = 0
for i in 2:10
    if has_cached_layout(cache, UInt32(i))
        valid_count += 1
    end
end
println("Nodes with valid cached layouts: $valid_count/9")

println()
println("=" ^ 50)
println("Examples completed successfully!")
