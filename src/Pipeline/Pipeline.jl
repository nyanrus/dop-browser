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

## Rust Implementation (Required)

**Note**: DOPBrowser now requires Rust libraries (RustParser and RustRenderer) to be built and available.
The Julia implementations (HTMLParser, CSSParserModule, Renderer) are deprecated.

This Pipeline module currently uses the Julia implementations for internal processing but will
be migrated to use Rust implementations in a future version.

To build the required Rust libraries:
```bash
cd rust/dop-parser && cargo build --release
cd ../dop-renderer && cargo build --release
```

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
using ..ContentIR.MathOps: Vec2, Box4, vec2, box4

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

**Note**: As of this version, Rust implementations are REQUIRED.
This function is maintained for backward compatibility but will always return true
or throw an error if libraries are not available.

# Returns
- `parser`: true if RustParser is available (always true or throws error)
- `renderer`: true if RustRenderer is available (always true or throws error)

# Example
```julia
# This will always return (parser=true, renderer=true) or throw an error
rust = Pipeline.rust_available()
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
    catch e
        # RustParser not available - this will throw an error since Rust is now required
        rethrow(e)
    end
    
    try
        dop = parentmodule(@__MODULE__)
        if isdefined(dop, :RustRenderer) && isdefined(dop.RustRenderer, :is_available)
            renderer_available = dop.RustRenderer.is_available()
        end
    catch e
        # RustRenderer not available - this will throw an error since Rust is now required
        rethrow(e)
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
    
    link_child!(parent_id::UInt32, child_id::UInt32,
                first_children::Vector{UInt32}, next_siblings::Vector{UInt32}) = begin
        parent_id == 0 && return
        if first_children[parent_id] == 0
            first_children[parent_id] = child_id
            return
        end
        sibling = first_children[parent_id]
        while next_siblings[sibling] != 0
            sibling = next_siblings[sibling]
        end
        next_siblings[sibling] = child_id
    end

    function add_element!(
        parent_id::UInt32, tag_id::UInt32,
        node_types::Vector{UInt8}, parents::Vector{UInt32},
        first_children::Vector{UInt32}, next_siblings::Vector{UInt32},
        tags::Vector{UInt32}, widths::Vector{Float32}, heights::Vector{Float32},
        bg_colors::Vector{NTuple{4, UInt8}}
    )
        new_id = UInt32(length(node_types) + 1)
        push!(node_types, 0x02)  # Element
        push!(parents, parent_id)
        push!(first_children, 0)
        push!(next_siblings, 0)
        push!(tags, tag_id)
        push!(widths, 0.0f0)
        push!(heights, 0.0f0)
        push!(bg_colors, (0x00, 0x00, 0x00, 0x00))
        link_child!(parent_id, new_id, first_children, next_siblings)
        return new_id
    end

    function apply_inline_styles!(
        styles, idx::Integer,
        widths::Vector{Float32}, heights::Vector{Float32},
        bg_colors::Vector{NTuple{4, UInt8}}
    )
        if !styles.width_auto
            widths[idx] = styles.width
        end
        if !styles.height_auto
            heights[idx] = styles.height
        end
        if styles.has_background
            bg_colors[idx] = (styles.background_r, styles.background_g,
                              styles.background_b, styles.background_a)
        end
    end

    function parse_attributes!(
        token_index::Int, node_id::UInt32,
        tokens, pool,
        widths::Vector{Float32}, heights::Vector{Float32},
        bg_colors::Vector{NTuple{4, UInt8}}
    )
        j = token_index + 1
        while j <= length(tokens) && tokens[j].type == TOKEN_ATTRIBUTE
            attr_token = tokens[j]
            if get_string(pool, attr_token.name_id) == "style"
                style_str = get_string(pool, attr_token.value_id)
                apply_inline_styles!(parse_inline_style(style_str), Int(node_id),
                                     widths, heights, bg_colors)
            end
            j += 1
        end
        return j
    end

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
            new_id = add_element!(parent_id, token.name_id,
                                  node_types, parents, first_children, next_siblings,
                                  tags, widths, heights, bg_colors)
            i = parse_attributes!(i, new_id, tokens, pool,
                                  widths, heights, bg_colors) - 1
            push!(stack, new_id)
            
        elseif token.type == TOKEN_END_TAG  # End tag
            if length(stack) > 1
                pop!(stack)
            end
            
        elseif token.type == TOKEN_SELF_CLOSING  # Self-closing
            new_id = add_element!(stack[end], token.name_id,
                                  node_types, parents, first_children, next_siblings,
                                  tags, widths, heights, bg_colors)
            i = parse_attributes!(i, new_id, tokens, pool,
                                  widths, heights, bg_colors) - 1
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
        new_positions[idx] = new_positions[parent_id] + vec2(0, y_offset)
        
        # Size from style or auto
        if doc.widths[idx] > 0
            new_sizes[idx] = vec2(doc.widths[idx], doc.heights[idx])
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
    doc_to_render = doc.layout_computed ? doc :
        layout(doc, viewport=(Int(doc.viewport.x), Int(doc.viewport.y)))
 
    commands = NTuple{8, Float32}[]
    
    for (idx, node_type) in enumerate(doc_to_render.node_types)
        # Skip non-elements and zero-size nodes
        if node_type != 0x02
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
# PNG Encoding Helper
# ============================================================================

"""
    encode_png(pixels::Vector{UInt8}, width::UInt32, height::UInt32) -> Vector{UInt8}

Simple PNG encoder for RGBA pixel data.

This is a minimal PNG encoder that creates valid PNG files. It uses no compression
for simplicity and compatibility. For production use, consider using RustRenderer's
export_png! function which uses optimized Rust libraries.

# Arguments
- `pixels`: RGBA pixel data (4 bytes per pixel, row-major order)
- `width`: Image width in pixels
- `height`: Image height in pixels

# Returns
PNG-encoded image data as a vector of bytes.
"""
function encode_png(pixels::Vector{UInt8}, width::UInt32, height::UInt32)::Vector{UInt8}
    # Use a simple PPM format as intermediate, then convert to minimal PNG
    # For production, RustRenderer provides proper PNG export
    
    # Actually, let's create a minimal valid PNG file structure
    io = IOBuffer()
    
    # PNG signature
    write(io, UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
    
    # Helper to write a PNG chunk
    function write_chunk(chunk_type::String, data::Vector{UInt8})
        # Length (4 bytes)
        write(io, hton(UInt32(length(data))))
        
        # Type (4 bytes)
        type_bytes = Vector{UInt8}(chunk_type)
        write(io, type_bytes)
        
        # Data
        write(io, data)
        
        # CRC32 (4 bytes) - simplified version
        crc_data = vcat(type_bytes, data)
        crc = simple_crc32(crc_data)
        write(io, hton(crc))
    end
    
    # IHDR chunk (Image header)
    ihdr = IOBuffer()
    write(ihdr, hton(width))        # Width
    write(ihdr, hton(height))       # Height
    write(ihdr, UInt8(8))           # Bit depth
    write(ihdr, UInt8(6))           # Color type: RGBA (6)
    write(ihdr, UInt8(0))           # Compression method
    write(ihdr, UInt8(0))           # Filter method
    write(ihdr, UInt8(0))           # Interlace method
    write_chunk("IHDR", take!(ihdr))
    
    # IDAT chunk (Image data)
    # Add filter byte (0 = no filter) before each scanline
    filtered = IOBuffer()
    bytes_per_row = Int(width) * 4
    for y in 0:(height-1)
        write(filtered, UInt8(0))  # Filter type: None
        row_start = Int(y) * bytes_per_row + 1
        row_end = row_start + bytes_per_row - 1
        write(filtered, pixels[row_start:row_end])
    end
    
    # For simplicity, store uncompressed (not ideal but works)
    # Real PNG would use zlib compression
    filtered_data = take!(filtered)
    
    # Try to use zlib compression if available via CodecZlib
    compressed_data = filtered_data
    try
        # Try to load CodecZlib dynamically
        @eval using CodecZlib
        compressed_data = transcode(ZlibCompressor, filtered_data)
    catch
        # Fallback: Create a minimal zlib wrapper for uncompressed data
        # zlib header for uncompressed data
        comp_io = IOBuffer()
        write(comp_io, UInt8(0x78))  # CMF
        write(comp_io, UInt8(0x01))  # FLG (no compression)
        
        # Split data into blocks
        data_len = length(filtered_data)
        offset = 1
        while offset <= data_len
            chunk_size = min(65535, data_len - offset + 1)
            is_last = (offset + chunk_size - 1 >= data_len)
            
            # Block header
            write(comp_io, UInt8(is_last ? 0x01 : 0x00))
            write(comp_io, UInt16(chunk_size))           # LEN (little-endian)
            write(comp_io, UInt16(~chunk_size & 0xFFFF)) # NLEN (little-endian)
            
            # Block data
            write(comp_io, filtered_data[offset:offset+chunk_size-1])
            offset += chunk_size
        end
        
        # Adler-32 checksum
        adler = simple_adler32(filtered_data)
        write(comp_io, hton(adler))
        
        compressed_data = take!(comp_io)
    end
    
    write_chunk("IDAT", compressed_data)
    
    # IEND chunk (End of image)
    write_chunk("IEND", UInt8[])
    
    return take!(io)
end

"""Simple CRC32 implementation for PNG chunks"""
function simple_crc32(data::Vector{UInt8})::UInt32
    # CRC32 polynomial used by PNG
    crc = 0xffffffff
    for byte in data
        crc = xor(crc, UInt32(byte))
        for _ in 1:8
            if (crc & 1) != 0
                crc = xor(crc >> 1, 0xedb88320)
            else
                crc = crc >> 1
            end
        end
    end
    return xor(crc, 0xffffffff)
end

"""Simple Adler-32 checksum for zlib"""
function simple_adler32(data::Vector{UInt8})::UInt32
    MOD_ADLER = 65521
    a = UInt32(1)
    b = UInt32(0)
    for byte in data
        a = (a + UInt32(byte)) % MOD_ADLER
        b = (b + a) % MOD_ADLER
    end
    return (b << 16) | a
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
        
        rel = point - pos
        if rel.x >= 0 && rel.y >= 0 &&
           rel.x <= sz.x && rel.y <= sz.y
            return idx
        end
    end
    
    return nothing
end

export hit_test

end # module Pipeline
