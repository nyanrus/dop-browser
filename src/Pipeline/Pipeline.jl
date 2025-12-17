"""
    Pipeline

Simplified, functional programming-style pipeline for Content-- → Rendering → Interaction.

This module provides a clean, composable API that follows functional programming principles
with math-style operators for layout computation.

## Design Philosophy

1. **Pure Functions**: Stateless transformations where possible
2. **Composition**: Pipelines built from composable functions using |>
3. **Math-Style**: Layout uses intuitive Vec2, Box4 operations
4. **Minimal API**: Essential operations only, no redundancy

## Note on Rust Implementations

For production use, prefer the Rust-based implementations when available:
- **RustParser**: Uses html5ever and cssparser crates for standards-compliant parsing
- **RustRenderer**: Uses winit/wgpu for GPU-accelerated rendering

This Pipeline module uses the Julia implementations for maximum portability.
Use `Pipeline.rust_available()` to check if Rust implementations are available.

## Quick Start

```julia
using DOPBrowser.Pipeline

# Simple functional pipeline
html = "<div style='width: 100px; height: 50px; background: red'></div>"
png_data = html |> parse_doc |> layout |> render |> to_png

# Or step by step
doc = parse_doc(html)
doc = layout(doc, viewport=(800, 600))
buffer = render(doc)
save_png(buffer, "output.png")
```

## Composition Examples

```julia
# Create custom pipeline
my_pipeline = parse_doc ∘ layout ∘ render

# Use with viewport
render_html_fn = html -> html |> parse_doc |> layout(viewport=(1920, 1080)) |> render
```
"""
module Pipeline

using ..HTMLParser.StringInterner: StringPool, intern!, get_string
using ..HTMLParser.TokenTape: Tokenizer, tokenize!, get_tokens, 
                               TOKEN_START_TAG, TOKEN_END_TAG, TOKEN_SELF_CLOSING, TOKEN_ATTRIBUTE, TOKEN_TEXT
using ..DOMCSSOM.NodeTable: DOMTable, add_node!, node_count, NODE_DOCUMENT, NODE_ELEMENT, NODE_TEXT
using ..DOMCSSOM.RenderBuffer: CommandBuffer, emit_rect!, command_count, get_commands
import ..DOMCSSOM.RenderBuffer: clear!
using ..Layout.LayoutArrays: LayoutData, resize_layout!, set_bounds!, set_position!, compute_layout!
using ..CSSParserModule.CSSCore: parse_inline_style
using ..Renderer: RenderPipeline, create_pipeline, render_frame!
using ..Renderer.PNGExport: encode_png, write_png_file
using ..ContentMM.MathOps: Vec2, Box4, vec2, box4

export Document, RenderBuffer
export parse_doc, layout, render, to_png, save_png
export with_viewport, render_html
export rust_available

# ============================================================================
# Rust Implementation Check
# ============================================================================

"""
    rust_available() -> NamedTuple{(:parser, :renderer), Tuple{Bool, Bool}}

Check if Rust implementations are available.

# Returns
- `parser`: true if RustParser is available
- `renderer`: true if RustRenderer is available

# Example
```julia
if Pipeline.rust_available().parser
    println("Rust parser available for high-performance parsing")
end
```
"""
function rust_available()
    parser_available = false
    renderer_available = false
    
    # Use parentmodule to get DOPBrowser module without tight coupling to Main
    try
        dop = parentmodule(@__MODULE__)
        if isdefined(dop, :RustParser) && isdefined(dop.RustParser, :is_available)
            parser_available = dop.RustParser.is_available()
        end
    catch
        # RustParser not loaded or not available
    end
    
    try
        dop = parentmodule(@__MODULE__)
        if isdefined(dop, :RustRenderer) && isdefined(dop.RustRenderer, :is_available)
            renderer_available = dop.RustRenderer.is_available()
        end
    catch
        # RustRenderer not loaded or not available
    end
    
    return (parser=parser_available, renderer=renderer_available)
end

# ============================================================================
# Core Types (Immutable where possible for FP purity)
# ============================================================================

"""
    Document

Immutable document representation after parsing.
Contains all data needed for layout and rendering.
"""
struct Document
    # DOM data
    node_types::Vector{UInt8}
    parents::Vector{UInt32}
    first_children::Vector{UInt32}
    next_siblings::Vector{UInt32}
    tags::Vector{UInt32}
    
    # Style data
    widths::Vector{Float32}
    heights::Vector{Float32}
    bg_colors::Vector{NTuple{4, UInt8}}  # (r, g, b, a)
    
    # Layout computed
    positions::Vector{Vec2{Float32}}
    sizes::Vector{Vec2{Float32}}
    
    # Strings
    strings::Vector{String}
    
    # Viewport
    viewport::Vec2{Float32}
    
    # Flags
    layout_computed::Bool
end

"""
    RenderBuffer

Minimal render buffer for GPU upload.
"""
struct RenderBuffer
    commands::Vector{NTuple{8, Float32}}  # (x, y, w, h, r, g, b, a)
    width::UInt32
    height::UInt32
end

# ============================================================================
# Parse Functions (HTML → Document)
# ============================================================================

"""
    parse_doc(html::AbstractString) -> Document

Parse HTML into a Document structure.

This is a pure function - same input always produces same output.

# Examples
```julia
doc = parse_doc("<div style='width: 100px;'></div>")
```
"""
function parse_doc(html::AbstractString)::Document
    pool = StringPool()
    tokenizer = Tokenizer(pool)
    tokens = tokenize!(tokenizer, html)
    
    # Build document arrays
    node_types = UInt8[]
    parents = UInt32[]
    first_children = UInt32[]
    next_siblings = UInt32[]
    tags = UInt32[]
    widths = Float32[]
    heights = Float32[]
    bg_colors = NTuple{4, UInt8}[]
    strings = String[]
    
    # Simple state machine for parsing
    stack = UInt32[0]  # Parent stack
    
    # Add root
    push!(node_types, 0x01)  # Document
    push!(parents, 0)
    push!(first_children, 0)
    push!(next_siblings, 0)
    push!(tags, 0)
    push!(widths, 0.0f0)
    push!(heights, 0.0f0)
    push!(bg_colors, (0x00, 0x00, 0x00, 0x00))
    stack[1] = 1
    
    # Process tokens
    i = 1
    while i <= length(tokens)
        token = tokens[i]
        
        if token.type == TOKEN_START_TAG  # Start tag
            parent_id = stack[end]
            new_id = UInt32(length(node_types) + 1)
            
            push!(node_types, 0x02)  # Element
            push!(parents, parent_id)
            push!(first_children, 0)
            push!(next_siblings, 0)
            push!(tags, token.name_id)
            push!(widths, 0.0f0)
            push!(heights, 0.0f0)
            push!(bg_colors, (0x00, 0x00, 0x00, 0x00))
            
            # Link to parent
            if parent_id > 0
                if first_children[parent_id] == 0
                    first_children[parent_id] = new_id
                else
                    # Find last sibling
                    sibling = first_children[parent_id]
                    while next_siblings[sibling] != 0
                        sibling = next_siblings[sibling]
                    end
                    next_siblings[sibling] = new_id
                end
            end
            
            # Parse inline styles from following attribute tokens
            j = i + 1
            while j <= length(tokens) && tokens[j].type == TOKEN_ATTRIBUTE  # Attribute
                attr_token = tokens[j]
                attr_name = get_string(pool, attr_token.name_id)
                if attr_name == "style"
                    style_str = get_string(pool, attr_token.value_id)
                    styles = parse_inline_style(style_str)
                    if !styles.width_auto
                        widths[end] = styles.width
                    end
                    if !styles.height_auto
                        heights[end] = styles.height
                    end
                    if styles.has_background
                        bg_colors[end] = (styles.background_r, styles.background_g, 
                                          styles.background_b, styles.background_a)
                    end
                end
                j += 1
            end
            i = j - 1
            
            push!(stack, new_id)
            
        elseif token.type == TOKEN_END_TAG  # End tag
            if length(stack) > 1
                pop!(stack)
            end
            
        elseif token.type == TOKEN_SELF_CLOSING  # Self-closing
            parent_id = stack[end]
            new_id = UInt32(length(node_types) + 1)
            
            push!(node_types, 0x02)
            push!(parents, parent_id)
            push!(first_children, 0)
            push!(next_siblings, 0)
            push!(tags, token.name_id)
            push!(widths, 0.0f0)
            push!(heights, 0.0f0)
            push!(bg_colors, (0x00, 0x00, 0x00, 0x00))
            
            # Link to parent (same logic as start tags)
            if parent_id > 0
                if first_children[parent_id] == 0
                    first_children[parent_id] = new_id
                else
                    # Find last sibling
                    sibling = first_children[parent_id]
                    while next_siblings[sibling] != 0
                        sibling = next_siblings[sibling]
                    end
                    next_siblings[sibling] = new_id
                end
            end
        end
        
        i += 1
    end
    
    # Collect strings (copy from pool)
    strings = copy(pool.strings)
    
    # Initialize positions and sizes
    n = length(node_types)
    positions = [vec2(0, 0) for _ in 1:n]
    sizes = [vec2(widths[idx], heights[idx]) for idx in 1:n]
    
    return Document(
        node_types, parents, first_children, next_siblings, tags,
        widths, heights, bg_colors,
        positions, sizes,
        strings,
        vec2(800, 600),  # Default viewport
        false
    )
end

# ============================================================================
# Layout Functions (Document → Document with layout)
# ============================================================================

"""
    layout(doc::Document; viewport::Tuple{Int,Int}=(800, 600)) -> Document

Compute layout positions for all nodes.

Returns a new Document with layout computed.

# Examples
```julia
doc = parse(html)
doc = layout(doc, viewport=(1920, 1080))
```
"""
function layout(doc::Document; viewport::Tuple{Int,Int}=(800, 600))::Document
    vp = vec2(Float32(viewport[1]), Float32(viewport[2]))
    n = length(doc.node_types)
    
    # Copy arrays (immutability)
    new_positions = copy(doc.positions)
    new_sizes = copy(doc.sizes)
    
    # Set root to viewport
    if n >= 1
        new_positions[1] = vec2(0, 0)
        new_sizes[1] = vp
    end
    
    # Simple block layout (top-down)
    for idx in 2:n
        parent_id = doc.parents[idx]
        if parent_id == 0
            continue
        end
        
        # Find position among siblings
        y_offset = 0.0f0
        sibling = doc.first_children[parent_id]
        while sibling != 0 && sibling != UInt32(idx)
            y_offset += new_sizes[sibling].y
            sibling = doc.next_siblings[sibling]
        end
        
        # Position relative to parent
        new_positions[idx] = Vec2(
            new_positions[parent_id].x,
            new_positions[parent_id].y + y_offset
        )
        
        # Size from style or auto
        if doc.widths[idx] > 0
            new_sizes[idx] = Vec2(doc.widths[idx], doc.heights[idx])
        end
    end
    
    return Document(
        doc.node_types, doc.parents, doc.first_children, doc.next_siblings, doc.tags,
        doc.widths, doc.heights, doc.bg_colors,
        new_positions, new_sizes,
        doc.strings,
        vp,
        true
    )
end

"""
    with_viewport(viewport::Tuple{Int,Int})

Create a layout function with specific viewport.

# Examples
```julia
layout_fn = with_viewport((1920, 1080))
doc = html |> parse |> layout_fn
```
"""
function with_viewport(viewport::Tuple{Int,Int})
    doc -> layout(doc; viewport=viewport)
end

# ============================================================================
# Render Functions (Document → RenderBuffer)
# ============================================================================

"""
    render(doc::Document) -> RenderBuffer

Generate render commands from a laid-out document.

# Examples
```julia
buffer = doc |> render
```
"""
function render(doc::Document)::RenderBuffer
    local doc_to_render = doc
    if !doc.layout_computed
        # Auto-compute layout if needed
        doc_to_render = layout(doc, viewport=(Int(doc.viewport.x), Int(doc.viewport.y)))
    end
    
    commands = NTuple{8, Float32}[]
    
    n = length(doc_to_render.node_types)
    for idx in 1:n
        # Skip non-elements and zero-size nodes
        if doc_to_render.node_types[idx] != 0x02
            continue
        end
        
        pos = doc_to_render.positions[idx]
        sz = doc_to_render.sizes[idx]
        
        if sz.x <= 0 || sz.y <= 0
            continue
        end
        
        # Check for background color
        bg = doc_to_render.bg_colors[idx]
        if bg[4] > 0  # Has alpha
            r = Float32(bg[1]) / 255.0f0
            g = Float32(bg[2]) / 255.0f0
            b = Float32(bg[3]) / 255.0f0
            a = Float32(bg[4]) / 255.0f0
            
            push!(commands, (pos.x, pos.y, sz.x, sz.y, r, g, b, a))
        end
    end
    
    return RenderBuffer(commands, UInt32(doc_to_render.viewport.x), UInt32(doc_to_render.viewport.y))
end

# ============================================================================
# Output Functions (RenderBuffer → PNG)
# ============================================================================

"""
    to_png(buffer::RenderBuffer) -> Vector{UInt8}

Convert render buffer to PNG data.

# Examples
```julia
png_bytes = buffer |> to_png
```
"""
function to_png(buffer::RenderBuffer)::Vector{UInt8}
    # Create framebuffer
    width = Int(buffer.width)
    height = Int(buffer.height)
    pixels = fill(UInt8(255), width * height * 4)  # White background
    
    # Render commands to framebuffer
    for cmd in buffer.commands
        x, y, w, h, r, g, b, a = cmd
        
        x1 = max(1, Int(floor(x)) + 1)
        y1 = max(1, Int(floor(y)) + 1)
        x2 = min(width, Int(floor(x + w)))
        y2 = min(height, Int(floor(y + h)))
        
        for py in y1:y2
            for px in x1:x2
                idx = ((py - 1) * width + (px - 1)) * 4 + 1
                pixels[idx] = UInt8(round(r * 255))
                pixels[idx + 1] = UInt8(round(g * 255))
                pixels[idx + 2] = UInt8(round(b * 255))
                pixels[idx + 3] = UInt8(round(a * 255))
            end
        end
    end
    
    return encode_png(pixels, buffer.width, buffer.height)
end

"""
    save_png(buffer::RenderBuffer, filename::String)

Save render buffer to PNG file.

# Examples
```julia
buffer |> save_png("output.png")
```
"""
function save_png(buffer::RenderBuffer, filename::String)
    png_data = to_png(buffer)
    open(filename, "w") do f
        write(f, png_data)
    end
end

# Curried version for pipeline
save_png(filename::String) = buffer -> (save_png(buffer, filename); buffer)

# ============================================================================
# Convenience Pipelines
# ============================================================================

"""
    render_html(html::AbstractString; viewport=(800, 600)) -> Vector{UInt8}

Convenience function to render HTML directly to PNG data.

# Examples
```julia
png = render_html("<div style='background: red; width: 100px; height: 100px'></div>")
```
"""
function render_html(html::AbstractString; viewport::Tuple{Int,Int}=(800, 600))::Vector{UInt8}
    html |> parse_doc |> with_viewport(viewport) |> render |> to_png
end

export render_html

# ============================================================================
# Math-Style Operators for Layout
# ============================================================================

"""
    position(doc::Document, node_id::Int) -> Vec2

Get the position of a node as a Vec2.
"""
function position(doc::Document, node_id::Int)::Vec2{Float32}
    doc.positions[node_id]
end

"""
    size(doc::Document, node_id::Int) -> Vec2

Get the size of a node as a Vec2.
"""
function Base.size(doc::Document, node_id::Int)::Vec2{Float32}
    doc.sizes[node_id]
end

"""
    bounds(doc::Document, node_id::Int) -> Tuple{Vec2, Vec2}

Get the position and size of a node.
"""
function bounds(doc::Document, node_id::Int)
    (doc.positions[node_id], doc.sizes[node_id])
end

export position, bounds

# ============================================================================
# Interaction Functions
# ============================================================================

"""
    hit_test(doc::Document, point::Vec2) -> Union{Int, Nothing}

Find the topmost node at a given point.

# Examples
```julia
node_id = hit_test(doc, vec2(100, 50))
```
"""
function hit_test(doc::Document, point::Vec2{Float32})::Union{Int, Nothing}
    n = length(doc.node_types)
    
    # Search from end (topmost) to beginning
    for idx in n:-1:1
        if doc.node_types[idx] != 0x02
            continue
        end
        
        pos = doc.positions[idx]
        sz = doc.sizes[idx]
        
        if point.x >= pos.x && point.x <= pos.x + sz.x &&
           point.y >= pos.y && point.y <= pos.y + sz.y
            return idx
        end
    end
    
    return nothing
end

export hit_test

end # module Pipeline
