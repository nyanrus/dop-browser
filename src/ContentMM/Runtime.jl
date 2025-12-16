"""
    Runtime

Content-- WASM-compatible runtime for dynamic interactions.

## Key Features
- Event → State update → Direct binary patching
- Sticky positioning resolver (Phase B)
- Dynamic effects (:hover) without layout reflow
- Virtual JS interface layer

## Sticky Positioning
Sticky is resolved outside the main constraint solver:
1. Phase A (Solver): Calculate anchor_rect once
2. Phase B (Resolver): On scroll, update final_rect.y using clamp formula
3. Benefit: Scrolling causes zero layout reflow
"""
module Runtime

using ..Primitives: NodeTable, NodeType, NODE_STACK, NODE_PARAGRAPH, node_count
using ..Properties: PropertyTable, Direction, resize_properties!, 
                    DIRECTION_DOWN, DIRECTION_UP, DIRECTION_RIGHT, DIRECTION_LEFT
using ..Styles: FlatStyle
using ..TextJIT: TextShaper, shape_paragraph!, ShapedParagraph
using ..Reactive: EventBindingTable, EventType, VarMap, get_bindings, EventBinding

export RuntimeContext, StickyElement, LayoutOutput
export initialize!, update!, render!
export resolve_sticky!, update_hover_state!, dispatch_event!
export JSInterface, js_get_property, js_set_property, js_call_method

"""
    StickyElement

Data for sticky positioned elements (Phase B resolver).
"""
mutable struct StickyElement
    node_id::UInt32
    anchor_y::Float32       # Static position from Phase A
    sticky_offset::Float32  # Offset from top when stuck
    parent_bottom::Float32  # Bottom of containing block
    current_y::Float32      # Current computed Y position
    is_stuck::Bool
end

"""
    LayoutOutput

Output of layout computation for a node.
"""
struct LayoutOutput
    x::Float32
    y::Float32
    width::Float32
    height::Float32
    visible::Bool
    needs_clip::Bool
end

"""
    RuntimeContext

Runtime context for Content-- execution.
"""
mutable struct RuntimeContext
    # Core data
    nodes::NodeTable
    properties::PropertyTable
    
    # Layout computed values
    layout_x::Vector{Float32}
    layout_y::Vector{Float32}
    layout_width::Vector{Float32}
    layout_height::Vector{Float32}
    
    # Text shaping
    text_shaper::TextShaper
    shaped_paragraphs::Dict{UInt32, ShapedParagraph}
    
    # Sticky positioning
    sticky_elements::Vector{StickyElement}
    
    # Event handling
    event_bindings::EventBindingTable
    var_map::VarMap
    
    # Hover state
    hovered_nodes::Set{UInt32}
    focused_node::UInt32
    
    # Scroll state
    scroll_x::Float32
    scroll_y::Float32
    
    # Viewport
    viewport_width::Float32
    viewport_height::Float32
    
    # Dirty flags
    layout_dirty::Bool
    render_dirty::Bool
    
    function RuntimeContext(viewport_width::Float32 = 1920.0f0,
                            viewport_height::Float32 = 1080.0f0)
        new(
            NodeTable(),
            PropertyTable(),
            Float32[],
            Float32[],
            Float32[],
            Float32[],
            TextShaper(),
            Dict{UInt32, ShapedParagraph}(),
            StickyElement[],
            EventBindingTable(),
            VarMap(),
            Set{UInt32}(),
            UInt32(0),
            0.0f0,
            0.0f0,
            viewport_width,
            viewport_height,
            true,
            true
        )
    end
end

"""
    initialize!(ctx::RuntimeContext, nodes::NodeTable, props::PropertyTable)

Initialize runtime with compiled Content--.
"""
function initialize!(ctx::RuntimeContext, nodes::NodeTable, props::PropertyTable)
    ctx.nodes = nodes
    ctx.properties = props
    
    n = node_count(nodes)
    resize!(ctx.layout_x, n)
    resize!(ctx.layout_y, n)
    resize!(ctx.layout_width, n)
    resize!(ctx.layout_height, n)
    
    fill!(ctx.layout_x, 0.0f0)
    fill!(ctx.layout_y, 0.0f0)
    fill!(ctx.layout_width, 0.0f0)
    fill!(ctx.layout_height, 0.0f0)
    
    ctx.layout_dirty = true
    ctx.render_dirty = true
end

"""
    update!(ctx::RuntimeContext, dt::Float32)

Update runtime state (called each frame).
"""
function update!(ctx::RuntimeContext, dt::Float32)
    if ctx.layout_dirty
        compute_layout!(ctx)
        ctx.layout_dirty = false
        ctx.render_dirty = true
    end
    
    # Always resolve sticky (lightweight, runs every scroll)
    resolve_sticky!(ctx)
end

"""
    compute_layout!(ctx::RuntimeContext)

Compute layout for all nodes (Content-- layout algorithm).
"""
function compute_layout!(ctx::RuntimeContext)
    n = node_count(ctx.nodes)
    if n == 0
        return
    end
    
    # Set root to viewport
    if n >= 1
        ctx.layout_width[1] = ctx.viewport_width
        ctx.layout_height[1] = ctx.viewport_height
        ctx.layout_x[1] = 0.0f0
        ctx.layout_y[1] = 0.0f0
    end
    
    # First pass: measure content (bottom-up)
    for i in n:-1:1
        node_type = ctx.nodes.node_types[i]
        
        # Get children and compute content size
        child_id = ctx.nodes.first_children[i]
        total_height = 0.0f0
        max_width = 0.0f0
        
        while child_id != 0
            child_h = ctx.layout_height[child_id]
            child_w = ctx.layout_width[child_id]
            
            # Check direction for stacking
            if i <= length(ctx.properties.direction)
                dir = ctx.properties.direction[i]
                if dir == Properties.DIRECTION_DOWN || dir == Properties.DIRECTION_UP
                    total_height += child_h
                    if i <= length(ctx.properties.gap_row)
                        total_height += ctx.properties.gap_row[i]
                    end
                    max_width = max(max_width, child_w)
                else
                    max_width += child_w
                    if i <= length(ctx.properties.gap_col)
                        max_width += ctx.properties.gap_col[i]
                    end
                    total_height = max(total_height, child_h)
                end
            end
            
            child_id = ctx.nodes.next_siblings[child_id]
        end
        
        # Use computed size if not explicitly set
        if i <= length(ctx.properties.width) && ctx.properties.width[i] > 0.0f0
            ctx.layout_width[i] = ctx.properties.width[i]
        else
            # Add padding
            inset_h = 0.0f0
            if i <= length(ctx.properties.inset_left)
                inset_h = ctx.properties.inset_left[i] + ctx.properties.inset_right[i]
            end
            ctx.layout_width[i] = max_width + inset_h
        end
        
        if i <= length(ctx.properties.height) && ctx.properties.height[i] > 0.0f0
            ctx.layout_height[i] = ctx.properties.height[i]
        else
            inset_v = 0.0f0
            if i <= length(ctx.properties.inset_top)
                inset_v = ctx.properties.inset_top[i] + ctx.properties.inset_bottom[i]
            end
            ctx.layout_height[i] = total_height + inset_v
        end
        
        # Handle Paragraph JIT shaping
        if node_type == NODE_PARAGRAPH && ctx.nodes.text_ids[i] != 0
            shape_paragraph_node!(ctx, UInt32(i))
        end
    end
    
    # Second pass: position children (top-down)
    for i in 1:n
        parent_id = Int(ctx.nodes.parents[i])
        if parent_id == 0
            continue
        end
        
        # Start at parent's content box
        parent_x = ctx.layout_x[parent_id]
        parent_y = ctx.layout_y[parent_id]
        
        if parent_id <= length(ctx.properties.inset_left)
            parent_x += ctx.properties.inset_left[parent_id]
            parent_y += ctx.properties.inset_top[parent_id]
        end
        
        # Add offset (margin)
        if i <= length(ctx.properties.offset_left)
            parent_x += ctx.properties.offset_left[i]
            parent_y += ctx.properties.offset_top[i]
        end
        
        # Find position among siblings
        sibling_id = ctx.nodes.first_children[parent_id]
        offset = 0.0f0
        
        while sibling_id != 0 && sibling_id != UInt32(i)
            if parent_id <= length(ctx.properties.direction)
                dir = ctx.properties.direction[parent_id]
                if dir == Properties.DIRECTION_DOWN || dir == Properties.DIRECTION_UP
                    offset += ctx.layout_height[sibling_id]
                    if parent_id <= length(ctx.properties.gap_row)
                        offset += ctx.properties.gap_row[parent_id]
                    end
                else
                    offset += ctx.layout_width[sibling_id]
                    if parent_id <= length(ctx.properties.gap_col)
                        offset += ctx.properties.gap_col[parent_id]
                    end
                end
            end
            sibling_id = ctx.nodes.next_siblings[sibling_id]
        end
        
        # Apply position based on direction
        if parent_id <= length(ctx.properties.direction)
            dir = ctx.properties.direction[parent_id]
            if dir == Properties.DIRECTION_DOWN
                ctx.layout_x[i] = parent_x
                ctx.layout_y[i] = parent_y + offset
            elseif dir == Properties.DIRECTION_UP
                ctx.layout_x[i] = parent_x
                ctx.layout_y[i] = parent_y + ctx.layout_height[parent_id] - offset - ctx.layout_height[i]
            elseif dir == Properties.DIRECTION_RIGHT
                ctx.layout_x[i] = parent_x + offset
                ctx.layout_y[i] = parent_y
            else  # LEFT
                ctx.layout_x[i] = parent_x + ctx.layout_width[parent_id] - offset - ctx.layout_width[i]
                ctx.layout_y[i] = parent_y
            end
        else
            ctx.layout_x[i] = parent_x
            ctx.layout_y[i] = parent_y + offset
        end
    end
end

"""
    shape_paragraph_node!(ctx::RuntimeContext, node_id::UInt32)

Shape a paragraph node using JIT.
"""
function shape_paragraph_node!(ctx::RuntimeContext, node_id::UInt32)
    # Get text content (would need string pool access)
    text = ""  # Simplified - would resolve from text_id
    max_width = ctx.layout_width[node_id]
    
    if max_width <= 0.0f0
        max_width = ctx.viewport_width
    end
    
    shaped = shape_paragraph!(ctx.text_shaper, text, max_width)
    ctx.shaped_paragraphs[node_id] = shaped
    
    # Update layout dimensions from shaped result
    ctx.layout_width[node_id] = shaped.width
    ctx.layout_height[node_id] = shaped.height
end

"""
    resolve_sticky!(ctx::RuntimeContext)

Phase B sticky positioning resolver.
Y_final = clamp(Y_anchor, ScrollTop + Offset, ParentBottom)
"""
function resolve_sticky!(ctx::RuntimeContext)
    for sticky in ctx.sticky_elements
        anchor_y = sticky.anchor_y
        scroll_top = ctx.scroll_y
        offset = sticky.sticky_offset
        parent_bottom = sticky.parent_bottom
        
        # Clamp formula
        new_y = clamp(anchor_y, scroll_top + offset, parent_bottom - ctx.layout_height[sticky.node_id])
        
        sticky.current_y = new_y
        sticky.is_stuck = new_y != anchor_y
        
        # Update layout (direct binary patching)
        if sticky.node_id <= length(ctx.layout_y)
            ctx.layout_y[sticky.node_id] = new_y
        end
    end
    
    ctx.render_dirty = true
end

"""
    update_hover_state!(ctx::RuntimeContext, node_id::UInt32, is_hovered::Bool)

Update hover state for a node (triggers style patching without reflow).
"""
function update_hover_state!(ctx::RuntimeContext, node_id::UInt32, is_hovered::Bool)
    if is_hovered
        push!(ctx.hovered_nodes, node_id)
    else
        delete!(ctx.hovered_nodes, node_id)
    end
    
    # Mark render dirty but NOT layout dirty
    # This enables :hover effects without layout reflow
    ctx.render_dirty = true
end

"""
    dispatch_event!(ctx::RuntimeContext, node_id::UInt32, 
                    event_type::EventType, event_data::Dict{Symbol, Any}) -> Bool

Dispatch an event to handlers.
"""
function dispatch_event!(ctx::RuntimeContext, node_id::UInt32,
                         event_type::EventType, 
                         event_data::Dict{Symbol, Any})::Bool
    bindings = get_bindings(ctx.event_bindings, node_id)
    handled = false
    
    for binding in bindings
        if binding.event_type == event_type
            # Would invoke WASM handler here
            # For now, just mark as handled
            handled = true
        end
    end
    
    return handled
end

"""
    render!(ctx::RuntimeContext, buffer::Vector{UInt8}) -> Int

Generate render commands into buffer.
Returns number of bytes written.
"""
function render!(ctx::RuntimeContext, buffer::Vector{UInt8})::Int
    if !ctx.render_dirty
        return 0
    end
    
    bytes_written = 0
    n = node_count(ctx.nodes)
    
    # Generate commands for each visible node
    for i in 1:n
        node_type = ctx.nodes.node_types[i]
        
        # Skip invisible or zero-size nodes
        if ctx.layout_width[i] <= 0 || ctx.layout_height[i] <= 0
            continue
        end
        
        # Emit render command based on node type
        # (Simplified - real implementation would write to buffer)
        bytes_written += 32  # Placeholder for command size
    end
    
    ctx.render_dirty = false
    return bytes_written
end

# ============================================================================
# Virtual JS Interface
# ============================================================================

"""
    JSInterface

Virtual interface for JavaScript interop.
Enables DOM-like API without actual DOM.
"""
mutable struct JSInterface
    runtime::RuntimeContext
    
    # Exposed properties per node
    property_cache::Dict{Tuple{UInt32, Symbol}, Any}
    
    # Method handlers
    method_handlers::Dict{Symbol, Function}
    
    function JSInterface(runtime::RuntimeContext)
        new(
            runtime,
            Dict{Tuple{UInt32, Symbol}, Any}(),
            Dict{Symbol, Function}()
        )
    end
end

"""
    js_get_property(iface::JSInterface, node_id::UInt32, prop::Symbol) -> Any

Get a property value (virtual DOM API).
"""
function js_get_property(iface::JSInterface, node_id::UInt32, prop::Symbol)::Any
    # Check cache
    key = (node_id, prop)
    if haskey(iface.property_cache, key)
        return iface.property_cache[key]
    end
    
    # Read from layout
    ctx = iface.runtime
    if prop == :offsetLeft && node_id <= length(ctx.layout_x)
        return ctx.layout_x[node_id]
    elseif prop == :offsetTop && node_id <= length(ctx.layout_y)
        return ctx.layout_y[node_id]
    elseif prop == :offsetWidth && node_id <= length(ctx.layout_width)
        return ctx.layout_width[node_id]
    elseif prop == :offsetHeight && node_id <= length(ctx.layout_height)
        return ctx.layout_height[node_id]
    elseif prop == :scrollLeft
        return ctx.scroll_x
    elseif prop == :scrollTop
        return ctx.scroll_y
    end
    
    return nothing
end

"""
    js_set_property!(iface::JSInterface, node_id::UInt32, prop::Symbol, value)

Set a property value (virtual DOM API).
"""
function js_set_property!(iface::JSInterface, node_id::UInt32, prop::Symbol, value)
    ctx = iface.runtime
    
    if prop == :scrollLeft
        ctx.scroll_x = Float32(value)
        resolve_sticky!(ctx)
    elseif prop == :scrollTop
        ctx.scroll_y = Float32(value)
        resolve_sticky!(ctx)
    else
        # Cache for later retrieval
        iface.property_cache[(node_id, prop)] = value
    end
end

"""
    js_call_method(iface::JSInterface, node_id::UInt32, 
                   method::Symbol, args::Vector{Any}) -> Any

Call a method on a node (virtual DOM API).
"""
function js_call_method(iface::JSInterface, node_id::UInt32,
                        method::Symbol, args::Vector{Any})::Any
    ctx = iface.runtime
    
    if method == :getBoundingClientRect
        return Dict{Symbol, Float32}(
            :x => js_get_property(iface, node_id, :offsetLeft),
            :y => js_get_property(iface, node_id, :offsetTop),
            :width => js_get_property(iface, node_id, :offsetWidth),
            :height => js_get_property(iface, node_id, :offsetHeight),
            :top => js_get_property(iface, node_id, :offsetTop),
            :left => js_get_property(iface, node_id, :offsetLeft),
            :right => js_get_property(iface, node_id, :offsetLeft) + 
                      js_get_property(iface, node_id, :offsetWidth),
            :bottom => js_get_property(iface, node_id, :offsetTop) + 
                       js_get_property(iface, node_id, :offsetHeight)
        )
    elseif method == :scrollTo && length(args) >= 2
        ctx.scroll_x = Float32(args[1])
        ctx.scroll_y = Float32(args[2])
        resolve_sticky!(ctx)
        return nothing
    elseif method == :focus
        ctx.focused_node = node_id
        return nothing
    elseif method == :blur
        if ctx.focused_node == node_id
            ctx.focused_node = UInt32(0)
        end
        return nothing
    end
    
    # Check custom handlers
    if haskey(iface.method_handlers, method)
        return iface.method_handlers[method](node_id, args)
    end
    
    return nothing
end

end # module Runtime
