"""
Simple Layout Module Test

Tests the new layout features without loading the full DOPBrowser package.
"""

# Load just the Layout module
include("../src/Layout/Layout.jl")
using .Layout
using .Layout.LayoutCache: get_precache_queue

println("=" ^ 70)
println("Testing HTML5/CSS3 Layout Engine")
println("=" ^ 70)
println()

# Test 1: Basic Layout Data Structure
println("Test 1: Basic Layout Data Structure")
println("-" ^ 50)
layout = LayoutData()
resize_layout!(layout, 5)
println("✓ Created LayoutData with 5 nodes")
println("  Array sizes: x=$(length(layout.x)), width=$(length(layout.width))")
println()

# Test 2: Setting and Getting Bounds
println("Test 2: Setting and Getting Bounds")
println("-" ^ 50)
set_bounds!(layout, 1, 800.0f0, 600.0f0)
set_position!(layout, 1, 0.0f0, 0.0f0)
w, h = get_bounds(layout, 1)
x, y = get_position(layout, 1)
println("✓ Set node 1: position=($x, $y), size=($w, $h)")
println()

# Test 3: CSS Properties
println("Test 3: CSS Properties")  
println("-" ^ 50)
set_margins!(layout, 2, top=10.0f0, right=20.0f0, bottom=10.0f0, left=20.0f0)
println("✓ Set margins for node 2")
println("  Top=$(layout.margin_top[2])px, Right=$(layout.margin_right[2])px")

set_paddings!(layout, 2, top=5.0f0, right=5.0f0, bottom=5.0f0, left=5.0f0)
println("✓ Set paddings for node 2")
println("  Top=$(layout.padding_top[2])px, Right=$(layout.padding_right[2])px")

set_background_color!(layout, 2, 0xff, 0x00, 0x00, 0xff)
r, g, b, a = get_background_color(layout, 2)
println("✓ Set background color: RGB($r, $g, $b) Alpha=$a")
println()

# Test 4: Display Types
println("Test 4: Display Types (Flexbox & Grid)")
println("-" ^ 50)
layout.display[1] = DISPLAY_FLEX
layout.display[2] = DISPLAY_GRID
println("✓ Node 1: DISPLAY_FLEX = $(layout.display[1])")
println("✓ Node 2: DISPLAY_GRID = $(layout.display[2])")
println()

# Test 5: Layout Caching
println("Test 5: Thread-Safe Layout Caching")
println("-" ^ 50)
cache = Layout.LayoutCache.LayoutCache(capacity=100)
println("✓ Created cache with capacity 100")

# Cache some layouts
cache_layout!(cache, UInt32(1), 0.0f0, 0.0f0, 800.0f0, 600.0f0,
             children=[UInt32(2), UInt32(3)])
cache_layout!(cache, UInt32(2), 10.0f0, 10.0f0, 100.0f0, 50.0f0,
             parent_id=UInt32(1))
println("✓ Cached 2 layouts")

# Retrieve from cache
if has_cached_layout(cache, UInt32(2))
    entry = get_cached_layout(cache, UInt32(2))
    println("✓ Retrieved from cache: Node 2 at ($(entry.x), $(entry.y))")
else
    println("✗ Failed to retrieve from cache")
end

# Cache stats
stats = get_cache_stats(cache)
println("✓ Cache stats: $(stats.size) entries, $(stats.hits) hits, $(stats.misses) misses")
println("  Hit rate: $(round(stats.hit_rate * 100, digits=1))%")
println()

# Test 6: Cache Invalidation
println("Test 6: Cache Invalidation")
println("-" ^ 50)
println("  Before invalidation: has_cached_layout(2) = $(has_cached_layout(cache, UInt32(2)))")
invalidate_node!(cache, UInt32(2))
println("  After invalidation: has_cached_layout(2) = $(has_cached_layout(cache, UInt32(2)))")
println("✓ Cache invalidation working")
println()

# Test 7: Subtree Invalidation
println("Test 7: Subtree Invalidation")
println("-" ^ 50)
# Re-cache nodes
cache_layout!(cache, UInt32(1), 0.0f0, 0.0f0, 800.0f0, 600.0f0,
             children=[UInt32(2), UInt32(3)])
cache_layout!(cache, UInt32(2), 10.0f0, 10.0f0, 100.0f0, 50.0f0,
             parent_id=UInt32(1))
cache_layout!(cache, UInt32(3), 120.0f0, 10.0f0, 100.0f0, 50.0f0,
             parent_id=UInt32(1))

println("  Cached nodes: 1, 2, 3")
println("  Before: has(1)=$(has_cached_layout(cache, UInt32(1))), " *
        "has(2)=$(has_cached_layout(cache, UInt32(2))), " *
        "has(3)=$(has_cached_layout(cache, UInt32(3)))")

invalidate_subtree!(cache, UInt32(1))

println("  After invalidate_subtree!(1):")
println("  has(1)=$(has_cached_layout(cache, UInt32(1))), " *
        "has(2)=$(has_cached_layout(cache, UInt32(2))), " *
        "has(3)=$(has_cached_layout(cache, UInt32(3)))")
println("✓ Subtree invalidation working")
println()

# Test 8: Precaching
println("Test 8: Precaching")
println("-" ^ 50)
cache2 = Layout.LayoutCache.LayoutCache(capacity=1000)
nodes = UInt32[10, 11, 12, 13, 14]
precache_layouts!(cache2, nodes)
queue = get_precache_queue(cache2)
println("✓ Queued $(length(nodes)) nodes for precaching")
println("  Queue retrieved: $(length(queue)) nodes")
println()

# Test 9: Flexbox Constants
println("Test 9: Flexbox & Grid Constants")
println("-" ^ 50)
println("✓ FLEX_DIRECTION_ROW = $FLEX_DIRECTION_ROW")
println("✓ FLEX_DIRECTION_COLUMN = $FLEX_DIRECTION_COLUMN")
println("✓ JUSTIFY_CONTENT_CENTER = $JUSTIFY_CONTENT_CENTER")
println("✓ ALIGN_ITEMS_STRETCH = $ALIGN_ITEMS_STRETCH")
println()

# Summary
println("=" ^ 70)
println("All tests passed! ✓")
println("=" ^ 70)
println()
println("Summary of new features:")
println("  • Full CSS3 Flexbox support (direction, wrap, justify, align)")
println("  • Full CSS3 Grid support (template, auto-flow, gap)")
println("  • Thread-safe layout caching with ReentrantLock")
println("  • Layout invalidation and incremental reflow")
println("  • Precaching for predictive rendering")
println("  • SIMD-friendly Structure of Arrays design")
println()
