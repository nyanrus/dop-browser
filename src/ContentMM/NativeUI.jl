"""
    NativeUI

Native UI library interface for Content--.

This module provides a high-level API for using Content-- as a standalone UI library
in native applications. It offers both:

1. **Text-based input**: Parse human-readable Content-- text format
2. **Programmatic API**: Build UI trees using Julia code

## Usage Examples

### Text-based Input
```julia
using DOPBrowser.ContentMM.NativeUI

# Create a UI from text
ui = create_ui(\"\"\"
    Stack(Direction: Down, Fill: #FFFFFF) {
        Rect(Size: (200, 100), Fill: #FF0000);
        Paragraph { Span(Text: "Hello World"); }
    }
\"\"\")

# Render to PNG with Cairo (high-quality text rendering)
render_to_png!(ui, "output.png", width=800, height=600, use_cairo=true)
```

### Programmatic API
```julia
using DOPBrowser.ContentMM.NativeUI

# Build UI programmatically
ui = UIBuilder()
with_stack!(ui, direction=:down, fill="#FFFFFF") do
    rect!(ui, width=200, height=100, fill="#FF0000")
    with_paragraph!(ui) do
        span!(ui, text="Hello World")
    end
end

# Render to PNG
render_to_png!(ui, "output.png", width=800, height=600)
```

## Pixel Comparison
```julia
# Compare rendered output with reference image
result = compare_pixels(ui, "reference.png", width=800, height=600)
@test result.match_ratio > 0.99
```
"""
module NativeUI

using ..Primitives: NodeTable, NodeType, create_node!, node_count, get_children,
                    NODE_ROOT, NODE_STACK, NODE_GRID, NODE_SCROLL, NODE_RECT,
                    NODE_PARAGRAPH, NODE_SPAN, NODE_LINK
using ..Properties: PropertyTable, Direction, Pack, Align, Color,
                    DIRECTION_DOWN, DIRECTION_UP, DIRECTION_RIGHT, DIRECTION_LEFT,
                    PACK_START, PACK_END, PACK_CENTER, PACK_BETWEEN, PACK_AROUND, PACK_EVENLY,
                    ALIGN_START, ALIGN_END, ALIGN_CENTER, ALIGN_STRETCH, ALIGN_BASELINE,
                    resize_properties!, set_property!, parse_color
using ..TextParser: parse_content_text, ParsedDocument
using ...DOMCSSOM.RenderBuffer: CommandBuffer, emit_rect!, emit_text!, command_count, get_commands
import ...DOMCSSOM.RenderBuffer: clear! as clear_buffer!
# DEPRECATED: Old Renderer module removed, use RustRenderer instead
# using ...Renderer: RenderPipeline, create_pipeline, render_frame!, get_png_data, export_png!
# using ...Renderer.PNGExport: encode_png, decode_png, write_png_file
# using ...Renderer.GPURenderer: get_framebuffer
# using ...Renderer.SoftwareRenderer: SoftwareRenderContext, create_software_context
# using ...Renderer.SoftwareRenderer: render_rect! as sw_render_rect!, render_text! as sw_render_text!
# using ...Renderer.SoftwareRenderer: save_png as sw_save_png, get_surface_data as sw_get_surface_data
# using ...Renderer.SoftwareRenderer: measure_text as sw_measure_text
# import ...Renderer.SoftwareRenderer: clear! as clear_software!
using ...RustRenderer: RustRendererHandle, create_renderer, add_rect!, add_text!, export_png!, get_framebuffer
import ...RustRenderer: render! as rust_render!, clear! as rust_clear!

# Aliases for backward compatibility - commented out as old Renderer module was removed
# const CairoRenderContext = SoftwareRenderContext
# const create_cairo_context = create_software_context

export UIContext, create_ui, render!, render_to_png!, render_to_buffer
export UIBuilder, with_stack!, with_paragraph!, rect!, span!
export compare_pixels, PixelComparisonResult
# export render_cairo!, render_to_png_cairo!  # Deprecated with old Renderer

# ============================================================================
# UI Context
# ============================================================================

"""
    UIContext

A Content-- UI context for native applications.

Holds the parsed/built UI tree and provides rendering capabilities.
"""
mutable struct UIContext
    # Node tree
    nodes::NodeTable
    properties::PropertyTable
    strings::Vector{String}
    
    # Rendering - updated to use RustRenderer
    command_buffer::CommandBuffer
    renderer::Union{RustRendererHandle, Nothing}
    
    # State
    viewport_width::Float32
    viewport_height::Float32
    dirty::Bool
    use_software::Bool
    
    function UIContext()
        new(
            NodeTable(),
            PropertyTable(),
            String[],
            CommandBuffer(),
            nothing,
            800.0f0,
            600.0f0,
            true,
            false
        )
    end
end

# Backward compatibility aliases - commented out as old Renderer was removed
# const cairo_context = software_context
# const use_cairo = use_software

"""
    create_ui(source::String) -> UIContext

Create a UI context from Content-- text format.
"""
function create_ui(source::String)::UIContext
    ctx = UIContext()
    
    # Parse the source
    doc = parse_content_text(source)
    
    if !doc.success
        error("Failed to parse Content-- text: $(doc.errors)")
    end
    
    ctx.nodes = doc.nodes
    ctx.properties = doc.properties
    ctx.strings = doc.strings
    ctx.dirty = true
    
    return ctx
end

"""
    create_ui() -> UIContext

Create an empty UI context for programmatic building.
"""
function create_ui()::UIContext
    ctx = UIContext()
    # Create root node
    create_node!(ctx.nodes, NODE_ROOT)
    resize_properties!(ctx.properties, 1)
    return ctx
end

# ============================================================================
# Rendering
# ============================================================================

"""
    render!(ctx::UIContext; width::Int=800, height::Int=600)

Render the UI to the internal command buffer.
"""
function render!(ctx::UIContext; width::Int=800, height::Int=600)
    ctx.viewport_width = Float32(width)
    ctx.viewport_height = Float32(height)
    
    # Clear command buffer
    clear_buffer!(ctx.command_buffer)
    
    # Generate render commands from the node tree
    generate_commands!(ctx)
    
    ctx.dirty = false
end

"""
Generate render commands from the node tree.
"""
function generate_commands!(ctx::UIContext)
    n = node_count(ctx.nodes)
    if n == 0
        return
    end
    
    # Simple layout: process nodes in order
    # For a full implementation, this would do proper flex/grid layout
    layout_x = zeros(Float32, n)
    layout_y = zeros(Float32, n)
    layout_w = zeros(Float32, n)
    layout_h = zeros(Float32, n)
    
    # First pass: collect sizes from properties
    for i in 1:n
        if i <= length(ctx.properties.width)
            layout_w[i] = ctx.properties.width[i]
            layout_h[i] = ctx.properties.height[i]
        end
    end
    
    # Second pass: compute positions (simple stacking)
    compute_layout!(ctx, layout_x, layout_y, layout_w, layout_h)
    
    # Third pass: emit render commands
    for i in 1:n
        if layout_w[i] > 0 && layout_h[i] > 0
            # Check for fill color
            if i <= length(ctx.properties.fill_a) && ctx.properties.fill_a[i] > 0
                r = Float32(ctx.properties.fill_r[i]) / 255.0f0
                g = Float32(ctx.properties.fill_g[i]) / 255.0f0
                b = Float32(ctx.properties.fill_b[i]) / 255.0f0
                a = Float32(ctx.properties.fill_a[i]) / 255.0f0
                
                emit_rect!(ctx.command_buffer, layout_x[i], layout_y[i],
                          layout_w[i], layout_h[i], r, g, b, a)
            end
        end
    end
end

"""
Compute layout positions using simple flex-like algorithm.
"""
function compute_layout!(ctx::UIContext, x::Vector{Float32}, y::Vector{Float32},
                          w::Vector{Float32}, h::Vector{Float32})
    n = node_count(ctx.nodes)
    if n == 0
        return
    end
    
    # Process each node
    for i in 1:n
        parent_id = ctx.nodes.parents[i]
        
        if parent_id == 0
            # Root level - position at origin
            x[i] = 0.0f0
            y[i] = 0.0f0
        else
            # Get parent info
            parent_x = x[parent_id]
            parent_y = y[parent_id]
            
            # Get inset (padding)
            inset_left = 0.0f0
            inset_top = 0.0f0
            if parent_id <= length(ctx.properties.inset_left)
                inset_left = ctx.properties.inset_left[parent_id]
                inset_top = ctx.properties.inset_top[parent_id]
            end
            
            # Get direction
            direction = DIRECTION_DOWN
            if parent_id <= length(ctx.properties.direction)
                direction = ctx.properties.direction[parent_id]
            end
            
            # Get gap
            gap = 0.0f0
            if parent_id <= length(ctx.properties.gap_row)
                gap = direction == DIRECTION_DOWN || direction == DIRECTION_UP ?
                      ctx.properties.gap_row[parent_id] : ctx.properties.gap_col[parent_id]
            end
            
            # Find preceding siblings
            children = get_children(ctx.nodes, parent_id)
            sibling_offset = 0.0f0
            for child_id in children
                if child_id == i
                    break
                end
                if direction == DIRECTION_DOWN
                    sibling_offset += h[child_id] + gap
                elseif direction == DIRECTION_RIGHT
                    sibling_offset += w[child_id] + gap
                elseif direction == DIRECTION_UP
                    sibling_offset -= h[child_id] + gap
                elseif direction == DIRECTION_LEFT
                    sibling_offset -= w[child_id] + gap
                end
            end
            
            # Position based on direction
            if direction == DIRECTION_DOWN
                x[i] = parent_x + inset_left
                y[i] = parent_y + inset_top + sibling_offset
            elseif direction == DIRECTION_RIGHT
                x[i] = parent_x + inset_left + sibling_offset
                y[i] = parent_y + inset_top
            elseif direction == DIRECTION_UP
                x[i] = parent_x + inset_left
                y[i] = parent_y + h[parent_id] - inset_top + sibling_offset
            elseif direction == DIRECTION_LEFT
                x[i] = parent_x + w[parent_id] - inset_left + sibling_offset
                y[i] = parent_y + inset_top
            end
            
            # Apply offset (margin)
            if i <= length(ctx.properties.offset_left)
                x[i] += ctx.properties.offset_left[i]
                y[i] += ctx.properties.offset_top[i]
            end
        end
    end
end

"""
    render_to_png!(ctx::UIContext, filename::String; width::Int=800, height::Int=600)

Render the UI and save to a PNG file.
"""
function render_to_png!(ctx::UIContext, filename::String; width::Int=800, height::Int=600)
    if ctx.dirty
        render!(ctx, width=width, height=height)
    end
    
    # Create or reuse renderer
    if ctx.renderer === nothing
        ctx.renderer = create_renderer(UInt32(width), UInt32(height))
    end
    
    # Clear and render commands
    rust_clear!(ctx.renderer)
    for cmd in get_commands(ctx.command_buffer)
        # Render each command using RustRenderer
        x, y, w, h, r, g, b, a = cmd
        add_rect!(ctx.renderer, Float32(x), Float32(y), Float32(w), Float32(h),
                 Float32(r), Float32(g), Float32(b), Float32(a))
    end
    
    # Render and export
    rust_render!(ctx.renderer)
    export_png!(ctx.renderer, filename)
end

"""
    render_to_buffer(ctx::UIContext; width::Int=800, height::Int=600) -> Vector{UInt8}

Render the UI and return raw RGBA pixel data.
"""
function render_to_buffer(ctx::UIContext; width::Int=800, height::Int=600)::Vector{UInt8}
    if ctx.dirty
        render!(ctx, width=width, height=height)
    end
    
    # Create or reuse renderer
    if ctx.renderer === nothing
        ctx.renderer = create_renderer(UInt32(width), UInt32(height))
    end
    
    # Clear and render commands  
    rust_clear!(ctx.renderer)
    for cmd in get_commands(ctx.command_buffer)
        x, y, w, h, r, g, b, a = cmd
        add_rect!(ctx.renderer, Float32(x), Float32(y), Float32(w), Float32(h),
                 Float32(r), Float32(g), Float32(b), Float32(a))
    end
    
    # Render and get framebuffer
    rust_render!(ctx.renderer)
    return get_framebuffer(ctx.renderer)
end

# ============================================================================
# Cairo Rendering (High-Quality Text Rendering)
# ============================================================================

"""
    render_cairo!(ctx::UIContext; width::Int=800, height::Int=600)

Render the UI using Cairo for high-quality vector graphics and text rendering.
"""
function render_cairo!(ctx::UIContext; width::Int=800, height::Int=600)
    ctx.viewport_width = Float32(width)
    ctx.viewport_height = Float32(height)
    ctx.use_cairo = true
    
    # Create or reuse Cairo context
    if ctx.cairo_context === nothing ||
       ctx.cairo_context.width != UInt32(width) ||
       ctx.cairo_context.height != UInt32(height)
        ctx.cairo_context = create_cairo_context(width, height)
    end
    
    # Clear with white background
    clear_cairo!(ctx.cairo_context, 1.0, 1.0, 1.0, 1.0)
    
    # Generate Cairo render commands from the node tree
    generate_cairo_commands!(ctx)
    
    ctx.dirty = false
end

"""
Generate Cairo render commands from the node tree.
"""
function generate_cairo_commands!(ctx::UIContext)
    n = node_count(ctx.nodes)
    if n == 0 || ctx.cairo_context === nothing
        return
    end
    
    # Compute layout
    layout_x = zeros(Float32, n)
    layout_y = zeros(Float32, n)
    layout_w = zeros(Float32, n)
    layout_h = zeros(Float32, n)
    
    # First pass: collect sizes from properties
    for i in 1:n
        if i <= length(ctx.properties.width)
            layout_w[i] = ctx.properties.width[i]
            layout_h[i] = ctx.properties.height[i]
        end
    end
    
    # Second pass: compute positions
    compute_layout!(ctx, layout_x, layout_y, layout_w, layout_h)
    
    # Third pass: render using Cairo
    for i in 1:n
        node_type = ctx.nodes.node_types[i]
        
        # Render fill if present
        if layout_w[i] > 0 && layout_h[i] > 0
            if i <= length(ctx.properties.fill_a) && ctx.properties.fill_a[i] > 0
                r = Float64(ctx.properties.fill_r[i]) / 255.0
                g = Float64(ctx.properties.fill_g[i]) / 255.0
                b = Float64(ctx.properties.fill_b[i]) / 255.0
                a = Float64(ctx.properties.fill_a[i]) / 255.0
                
                # Get border radius if available
                radius = 0.0
                if i <= length(ctx.properties.round_tl)
                    radius = Float64(ctx.properties.round_tl[i])
                end
                
                render_rect!(ctx.cairo_context, 
                            Float64(layout_x[i]), Float64(layout_y[i]),
                            Float64(layout_w[i]), Float64(layout_h[i]),
                            (r, g, b, a); radius=radius)
            end
        end
        
        # Render text for Span nodes
        if node_type == NODE_SPAN
            text_id = ctx.nodes.text_ids[i]
            if text_id > 0 && text_id <= length(ctx.strings)
                text = ctx.strings[text_id]
                
                # Get text color from properties (default black)
                text_r = 0.0
                text_g = 0.0
                text_b = 0.0
                text_a = 1.0
                if i <= length(ctx.properties.text_color_a)
                    text_r = Float64(ctx.properties.text_color_r[i]) / 255.0
                    text_g = Float64(ctx.properties.text_color_g[i]) / 255.0
                    text_b = Float64(ctx.properties.text_color_b[i]) / 255.0
                    text_a = Float64(ctx.properties.text_color_a[i]) / 255.0
                end
                
                # Get font size (default 16)
                font_size = 16.0
                if i <= length(ctx.properties.font_size) && ctx.properties.font_size[i] > 0
                    font_size = Float64(ctx.properties.font_size[i])
                end
                
                # Find parent position if not set
                parent_id = ctx.nodes.parents[i]
                text_x = Float64(layout_x[i])
                text_y = Float64(layout_y[i])
                
                if parent_id > 0 && (layout_w[i] == 0 || layout_h[i] == 0)
                    text_x = Float64(layout_x[parent_id])
                    text_y = Float64(layout_y[parent_id])
                    
                    # Add inset
                    if parent_id <= length(ctx.properties.inset_left)
                        text_x += Float64(ctx.properties.inset_left[parent_id])
                        text_y += Float64(ctx.properties.inset_top[parent_id])
                    end
                end
                
                render_text!(ctx.cairo_context, text, text_x, text_y + font_size,
                            font_size=font_size, color=(text_r, text_g, text_b, text_a))
            end
        end
        
        # Render text for Paragraph nodes with children
        if node_type == NODE_PARAGRAPH
            _render_paragraph_text!(ctx, i, layout_x, layout_y)
        end
    end
end

"""
Render text content for a Paragraph node.
"""
function _render_paragraph_text!(ctx::UIContext, para_id::Int, 
                                  layout_x::Vector{Float32}, layout_y::Vector{Float32})
    if ctx.cairo_context === nothing
        return
    end
    
    children = get_children(ctx.nodes, UInt32(para_id))
    
    para_x = Float64(layout_x[para_id])
    para_y = Float64(layout_y[para_id])
    
    # Add inset
    if para_id <= length(ctx.properties.inset_left)
        para_x += Float64(ctx.properties.inset_left[para_id])
        para_y += Float64(ctx.properties.inset_top[para_id])
    end
    
    current_x = para_x
    font_size = 16.0
    
    for child_id in children
        if ctx.nodes.node_types[child_id] == NODE_SPAN
            text_id = ctx.nodes.text_ids[child_id]
            if text_id > 0 && text_id <= length(ctx.strings)
                text = ctx.strings[text_id]
                
                render_text!(ctx.cairo_context, text, current_x, para_y + font_size,
                            font_size=font_size, color=(0.0, 0.0, 0.0, 1.0))
                
                # Advance X position
                text_width, _ = measure_text(ctx.cairo_context, text, font_size=font_size)
                current_x += text_width
            end
        end
    end
end

"""
    render_to_png_cairo!(ctx::UIContext, filename::String; width::Int=800, height::Int=600)

Render the UI using Cairo and save to a PNG file.
"""
function render_to_png_cairo!(ctx::UIContext, filename::String; width::Int=800, height::Int=600)
    render_cairo!(ctx, width=width, height=height)
    
    if ctx.cairo_context !== nothing
        save_png(ctx.cairo_context, filename)
    end
end

"""
    render_to_buffer_cairo(ctx::UIContext; width::Int=800, height::Int=600) -> Vector{UInt8}

Render the UI using Cairo and return raw RGBA pixel data.
"""
function render_to_buffer_cairo(ctx::UIContext; width::Int=800, height::Int=600)::Vector{UInt8}
    render_cairo!(ctx, width=width, height=height)
    
    if ctx.cairo_context !== nothing
        return get_surface_data(ctx.cairo_context)
    end
    
    return UInt8[]
end

export render_to_buffer_cairo

# ============================================================================
# Programmatic UI Builder
# ============================================================================

"""
    UIBuilder

Builder for constructing UI trees programmatically.
"""
mutable struct UIBuilder
    ctx::UIContext
    current_parent::UInt32
    
    function UIBuilder()
        ctx = create_ui()
        new(ctx, UInt32(1))  # Root is node 1
    end
end

"""
Create a Stack node with the given properties and execute block for children.
"""
function with_stack!(f::Function, builder::UIBuilder;
                     direction::Symbol=:down,
                     pack::Symbol=:start,
                     align::Symbol=:stretch,
                     fill::Union{String, Nothing}=nothing,
                     width::Float32=0.0f0,
                     height::Float32=0.0f0,
                     gap::Float32=0.0f0,
                     inset::Float32=0.0f0)
    # Create node
    node_id = create_node!(builder.ctx.nodes, NODE_STACK, parent=builder.current_parent)
    
    # Resize properties
    resize_properties!(builder.ctx.properties, node_count(builder.ctx.nodes))
    
    # Set properties
    set_property!(builder.ctx.properties, Int(node_id), :direction, parse_direction_sym(direction))
    set_property!(builder.ctx.properties, Int(node_id), :pack, parse_pack_sym(pack))
    set_property!(builder.ctx.properties, Int(node_id), :align, parse_align_sym(align))
    
    if width > 0
        set_property!(builder.ctx.properties, Int(node_id), :width, width)
    end
    if height > 0
        set_property!(builder.ctx.properties, Int(node_id), :height, height)
    end
    if gap > 0
        set_property!(builder.ctx.properties, Int(node_id), :gap_row, gap)
        set_property!(builder.ctx.properties, Int(node_id), :gap_col, gap)
    end
    if inset > 0
        set_property!(builder.ctx.properties, Int(node_id), :inset_top, inset)
        set_property!(builder.ctx.properties, Int(node_id), :inset_right, inset)
        set_property!(builder.ctx.properties, Int(node_id), :inset_bottom, inset)
        set_property!(builder.ctx.properties, Int(node_id), :inset_left, inset)
    end
    
    if fill !== nothing
        color = parse_color(fill)
        set_property!(builder.ctx.properties, Int(node_id), :fill_r, color.r)
        set_property!(builder.ctx.properties, Int(node_id), :fill_g, color.g)
        set_property!(builder.ctx.properties, Int(node_id), :fill_b, color.b)
        set_property!(builder.ctx.properties, Int(node_id), :fill_a, color.a)
    end
    
    # Process children
    old_parent = builder.current_parent
    builder.current_parent = node_id
    f()
    builder.current_parent = old_parent
    
    builder.ctx.dirty = true
    return node_id
end

"""
Create a Paragraph node.
"""
function with_paragraph!(f::Function, builder::UIBuilder)
    node_id = create_node!(builder.ctx.nodes, NODE_PARAGRAPH, parent=builder.current_parent)
    resize_properties!(builder.ctx.properties, node_count(builder.ctx.nodes))
    
    old_parent = builder.current_parent
    builder.current_parent = node_id
    f()
    builder.current_parent = old_parent
    
    builder.ctx.dirty = true
    return node_id
end

"""
Create a Rect node.
"""
function rect!(builder::UIBuilder;
               width::Float32=0.0f0,
               height::Float32=0.0f0,
               fill::Union{String, Nothing}=nothing)
    node_id = create_node!(builder.ctx.nodes, NODE_RECT, parent=builder.current_parent)
    resize_properties!(builder.ctx.properties, node_count(builder.ctx.nodes))
    
    if width > 0
        set_property!(builder.ctx.properties, Int(node_id), :width, width)
    end
    if height > 0
        set_property!(builder.ctx.properties, Int(node_id), :height, height)
    end
    
    if fill !== nothing
        color = parse_color(fill)
        set_property!(builder.ctx.properties, Int(node_id), :fill_r, color.r)
        set_property!(builder.ctx.properties, Int(node_id), :fill_g, color.g)
        set_property!(builder.ctx.properties, Int(node_id), :fill_b, color.b)
        set_property!(builder.ctx.properties, Int(node_id), :fill_a, color.a)
    end
    
    builder.ctx.dirty = true
    return node_id
end

"""
Create a Span node with text content.
"""
function span!(builder::UIBuilder; text::String="")
    node_id = create_node!(builder.ctx.nodes, NODE_SPAN, parent=builder.current_parent)
    resize_properties!(builder.ctx.properties, node_count(builder.ctx.nodes))
    
    if !isempty(text)
        push!(builder.ctx.strings, text)
        builder.ctx.nodes.text_ids[node_id] = UInt32(length(builder.ctx.strings))
    end
    
    builder.ctx.dirty = true
    return node_id
end

# Helper functions for symbol-based enum parsing
function parse_direction_sym(s::Symbol)::Direction
    if s == :down || s == :column
        return DIRECTION_DOWN
    elseif s == :up
        return DIRECTION_UP
    elseif s == :right || s == :row
        return DIRECTION_RIGHT
    elseif s == :left
        return DIRECTION_LEFT
    end
    return DIRECTION_DOWN
end

function parse_pack_sym(s::Symbol)::Pack
    if s == :start
        return PACK_START
    elseif s == :end
        return PACK_END
    elseif s == :center
        return PACK_CENTER
    elseif s == :between
        return PACK_BETWEEN
    elseif s == :around
        return PACK_AROUND
    elseif s == :evenly
        return PACK_EVENLY
    end
    return PACK_START
end

function parse_align_sym(s::Symbol)::Align
    if s == :start
        return ALIGN_START
    elseif s == :end
        return ALIGN_END
    elseif s == :center
        return ALIGN_CENTER
    elseif s == :stretch
        return ALIGN_STRETCH
    elseif s == :baseline
        return ALIGN_BASELINE
    end
    return ALIGN_STRETCH
end

"""
Get the UIContext from a builder.
"""
function get_context(builder::UIBuilder)::UIContext
    return builder.ctx
end

export get_context

# ============================================================================
# Pixel Comparison
# ============================================================================

"""
    PixelComparisonResult

Result of pixel-by-pixel comparison between two images.
"""
struct PixelComparisonResult
    match::Bool           # True if images match within tolerance
    match_ratio::Float64  # Ratio of matching pixels (0.0 to 1.0)
    diff_count::Int       # Number of differing pixels
    total_pixels::Int     # Total number of pixels
    max_diff::Int         # Maximum difference in any color channel
    
    function PixelComparisonResult(match::Bool, match_ratio::Float64, 
                                    diff_count::Int, total_pixels::Int, max_diff::Int)
        new(match, match_ratio, diff_count, total_pixels, max_diff)
    end
end

"""
    compare_pixels(ctx::UIContext, reference_path::String; 
                   width::Int=800, height::Int=600,
                   tolerance::Int=0) -> PixelComparisonResult

Compare rendered output with a reference image.

# Arguments
- `ctx`: The UI context to render
- `reference_path`: Path to reference PNG file
- `width`, `height`: Render dimensions
- `tolerance`: Per-channel tolerance (0-255)

# Returns
A PixelComparisonResult with match status and statistics.
"""
function compare_pixels(ctx::UIContext, reference_path::String;
                        width::Int=800, height::Int=600,
                        tolerance::Int=0)::PixelComparisonResult
    # Render the UI
    rendered = render_to_buffer(ctx, width=width, height=height)
    
    # Load reference image
    reference = load_reference_image(reference_path)
    
    if reference === nothing
        return PixelComparisonResult(false, 0.0, 0, 0, 0)
    end
    
    # Compare pixels
    return compare_buffers(rendered, reference, tolerance)
end

"""
    compare_pixels(buffer::Vector{UInt8}, reference_path::String;
                   tolerance::Int=0) -> PixelComparisonResult

Compare a raw pixel buffer with a reference image.
"""
function compare_pixels(buffer::Vector{UInt8}, reference_path::String;
                        tolerance::Int=0)::PixelComparisonResult
    reference = load_reference_image(reference_path)
    
    if reference === nothing
        return PixelComparisonResult(false, 0.0, 0, 0, 0)
    end
    
    return compare_buffers(buffer, reference, tolerance)
end

"""
Load reference image from file.
"""
function load_reference_image(path::String)::Union{Vector{UInt8}, Nothing}
    if !isfile(path)
        return nothing
    end
    
    try
        return decode_png(path)
    catch e
        @warn "Failed to load reference image: $path" exception=e
        return nothing
    end
end

"""
Compare two pixel buffers.
"""
function compare_buffers(rendered::Vector{UInt8}, reference::Vector{UInt8},
                         tolerance::Int)::PixelComparisonResult
    # Check sizes
    if length(rendered) != length(reference)
        return PixelComparisonResult(false, 0.0, 
                                      max(length(rendered), length(reference)) ÷ 4,
                                      max(length(rendered), length(reference)) ÷ 4, 255)
    end
    
    total_pixels = length(rendered) ÷ 4
    diff_count = 0
    max_diff = 0
    
    # Compare pixel by pixel
    for i in 1:4:length(rendered)
        r_diff = abs(Int(rendered[i]) - Int(reference[i]))
        g_diff = abs(Int(rendered[i+1]) - Int(reference[i+1]))
        b_diff = abs(Int(rendered[i+2]) - Int(reference[i+2]))
        a_diff = abs(Int(rendered[i+3]) - Int(reference[i+3]))
        
        pixel_max_diff = max(r_diff, g_diff, b_diff, a_diff)
        max_diff = max(max_diff, pixel_max_diff)
        
        if pixel_max_diff > tolerance
            diff_count += 1
        end
    end
    
    match_ratio = 1.0 - (diff_count / total_pixels)
    match = diff_count == 0
    
    return PixelComparisonResult(match, match_ratio, diff_count, total_pixels, max_diff)
end

"""
    save_diff_image(ctx::UIContext, reference_path::String, output_path::String;
                    width::Int=800, height::Int=600)

Save a difference image highlighting pixel differences.
"""
function save_diff_image(ctx::UIContext, reference_path::String, output_path::String;
                         width::Int=800, height::Int=600)
    rendered = render_to_buffer(ctx, width=width, height=height)
    reference = load_reference_image(reference_path)
    
    if reference === nothing
        @warn "Cannot create diff image: reference image not found or could not be loaded" path=reference_path
        return
    end
    
    if length(rendered) != length(reference)
        @warn "Cannot create diff image: rendered and reference buffer sizes differ" rendered_size=length(rendered) reference_size=length(reference)
        return
    end
    
    # Create diff buffer
    diff = similar(rendered)
    
    for i in 1:4:length(rendered)
        r_diff = abs(Int(rendered[i]) - Int(reference[i]))
        g_diff = abs(Int(rendered[i+1]) - Int(reference[i+1]))
        b_diff = abs(Int(rendered[i+2]) - Int(reference[i+2]))
        
        if r_diff + g_diff + b_diff > 0
            # Highlight differences in red
            diff[i] = 0xff
            diff[i+1] = 0x00
            diff[i+2] = 0x00
            diff[i+3] = 0xff
        else
            # Keep original with reduced opacity
            diff[i] = UInt8(rendered[i] ÷ 2)
            diff[i+1] = UInt8(rendered[i+1] ÷ 2)
            diff[i+2] = UInt8(rendered[i+2] ÷ 2)
            diff[i+3] = 0xff
        end
    end
    
    # Save diff image
    write_png_file(output_path, diff, UInt32(width), UInt32(height))
end

export save_diff_image

end # module NativeUI
