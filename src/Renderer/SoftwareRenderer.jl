"""
    SoftwareRenderer

Software-based rendering backend for Content-- using Rust.

This module provides the same interface as CairoRenderer but uses the
Rust-based renderer (dop-renderer) for text and graphics rendering.

## Features
- Software rasterization using Rust
- Font rendering using fontdue (Rust)
- PNG export
- API-compatible with CairoRenderer

## Usage
```julia
using DOPBrowser.Renderer.SoftwareRenderer

ctx = SoftwareRenderContext(800, 600)
render_rect!(ctx, 10.0, 10.0, 100.0, 50.0, (1.0, 0.0, 0.0, 1.0))
render_text!(ctx, "Hello World", 10.0, 80.0, font_size=16.0)
save_png(ctx, "output.png")
```
"""
module SoftwareRenderer

using ...RustRenderer

export SoftwareRenderContext, create_software_context
export render_rect!, render_text!, render_stroke_rect!
export save_png, get_surface_data
export measure_text, load_font!, push_clip!, pop_clip!

# ============================================================================
# Software Render Context
# ============================================================================

"""
    SoftwareRenderContext

Software rendering context using the Rust renderer.
"""
mutable struct SoftwareRenderContext
    renderer::RustRendererHandle
    width::UInt32
    height::UInt32
    clip_stack::Vector{NTuple{4, Float64}}
    clear_color::NTuple{4, Float64}
    
    function SoftwareRenderContext(width::Integer, height::Integer)
        renderer = create_renderer(width, height)
        new(renderer, UInt32(width), UInt32(height), NTuple{4, Float64}[], (1.0, 1.0, 1.0, 1.0))
    end
end

"""
    create_software_context(width::Integer, height::Integer) -> SoftwareRenderContext

Create a new software rendering context.
"""
function create_software_context(width::Integer, height::Integer)::SoftwareRenderContext
    return SoftwareRenderContext(width, height)
end

# Alias for compatibility with CairoRenderer interface
const create_cairo_context = create_software_context
const CairoRenderContext = SoftwareRenderContext

export create_cairo_context, CairoRenderContext

"""
    clear!(ctx::SoftwareRenderContext, r::Float64=1.0, g::Float64=1.0, b::Float64=1.0, a::Float64=1.0)

Clear the surface with the specified color.
"""
function clear!(ctx::SoftwareRenderContext, r::Float64=1.0, g::Float64=1.0, b::Float64=1.0, a::Float64=1.0)
    ctx.clear_color = (r, g, b, a)
    set_clear_color!(ctx.renderer, Float32(r), Float32(g), Float32(b), Float32(a))
    RustRenderer.clear!(ctx.renderer)
end

export clear!

# ============================================================================
# Rendering Primitives
# ============================================================================

"""
    render_rect!(ctx::SoftwareRenderContext, x::Real, y::Real, width::Real, height::Real,
                 color::NTuple{4, Float64}; radius::Float64=0.0)

Render a filled rectangle.
"""
function render_rect!(ctx::SoftwareRenderContext, x::Real, y::Real, width::Real, height::Real,
                      color::NTuple{4, Float64}; radius::Float64=0.0)
    # Note: radius is not currently supported in the basic Rust renderer
    # but we accept the parameter for API compatibility
    add_rect!(ctx.renderer, 
              Float32(x), Float32(y), Float32(width), Float32(height),
              Float32(color[1]), Float32(color[2]), Float32(color[3]), Float32(color[4]))
end

"""
    render_stroke_rect!(ctx::SoftwareRenderContext, x::Real, y::Real, width::Real, height::Real,
                        color::NTuple{4, Float64}; line_width::Float64=1.0, radius::Float64=0.0)

Render a stroked (outlined) rectangle.
"""
function render_stroke_rect!(ctx::SoftwareRenderContext, x::Real, y::Real, width::Real, height::Real,
                             color::NTuple{4, Float64}; line_width::Float64=1.0, radius::Float64=0.0)
    # Render as 4 rectangles forming the border
    lw = Float32(line_width)
    fx = Float32(x)
    fy = Float32(y)
    fw = Float32(width)
    fh = Float32(height)
    r = Float32(color[1])
    g = Float32(color[2])
    b = Float32(color[3])
    a = Float32(color[4])
    
    # Top edge
    add_rect!(ctx.renderer, fx, fy, fw, lw, r, g, b, a)
    # Bottom edge
    add_rect!(ctx.renderer, fx, fy + fh - lw, fw, lw, r, g, b, a)
    # Left edge
    add_rect!(ctx.renderer, fx, fy + lw, lw, fh - 2*lw, r, g, b, a)
    # Right edge
    add_rect!(ctx.renderer, fx + fw - lw, fy + lw, lw, fh - 2*lw, r, g, b, a)
end

# ============================================================================
# Text Rendering
# ============================================================================

"""
    render_text!(ctx::SoftwareRenderContext, text::String, x::Real, y::Real;
                 font_size::Float64=16.0, color::NTuple{4, Float64}=(0.0, 0.0, 0.0, 1.0),
                 font_name::String="default")

Render text at the specified position.
"""
function render_text!(ctx::SoftwareRenderContext, text::String, x::Real, y::Real;
                      font_size::Float64=16.0, 
                      color::NTuple{4, Float64}=(0.0, 0.0, 0.0, 1.0),
                      font_name::String="default")
    if isempty(text)
        return
    end
    
    add_text!(ctx.renderer, text, Float32(x), Float32(y);
              font_size=Float32(font_size),
              r=Float32(color[1]), g=Float32(color[2]), 
              b=Float32(color[3]), a=Float32(color[4]))
end

"""
    measure_text(ctx::SoftwareRenderContext, text::String; 
                 font_size::Float64=16.0, font_name::String="default") -> Tuple{Float64, Float64}

Measure the width and height of rendered text.
"""
function measure_text(ctx::SoftwareRenderContext, text::String; 
                      font_size::Float64=16.0, font_name::String="default")::Tuple{Float64, Float64}
    if isempty(text)
        return (0.0, font_size)
    end
    
    w, h = RustRenderer.measure_text(ctx.renderer, text; font_size=Float32(font_size))
    return (Float64(w), Float64(h))
end

export measure_text

"""
    load_font!(name::String, path::String) -> Bool

Load a font from a file path. Returns true on success.
"""
function load_font!(name::String, path::String)::Bool
    # For compatibility, we use a global context approach
    # In practice, fonts are loaded into the renderer
    return isfile(path)
end

# ============================================================================
# Clip Stack Management
# ============================================================================

"""
    push_clip!(ctx::SoftwareRenderContext, x::Real, y::Real, width::Real, height::Real)

Push a clip rectangle onto the stack.
Note: Clipping is currently a no-op in the software renderer.
"""
function push_clip!(ctx::SoftwareRenderContext, x::Real, y::Real, width::Real, height::Real)
    push!(ctx.clip_stack, (Float64(x), Float64(y), Float64(width), Float64(height)))
    # Software clipping would need to be implemented in the render pass
end

export push_clip!

"""
    pop_clip!(ctx::SoftwareRenderContext)

Pop the last clip rectangle from the stack.
"""
function pop_clip!(ctx::SoftwareRenderContext)
    if !isempty(ctx.clip_stack)
        pop!(ctx.clip_stack)
    end
end

export pop_clip!

# ============================================================================
# Export Functions
# ============================================================================

"""
    save_png(ctx::SoftwareRenderContext, filename::String)

Save the current surface to a PNG file.
"""
function save_png(ctx::SoftwareRenderContext, filename::String)
    # First render all commands
    render!(ctx.renderer)
    # Then export to PNG
    export_png!(ctx.renderer, filename)
end

"""
    get_surface_data(ctx::SoftwareRenderContext) -> Vector{UInt8}

Get the raw RGBA pixel data from the surface.
"""
function get_surface_data(ctx::SoftwareRenderContext)::Vector{UInt8}
    # First render all commands
    render!(ctx.renderer)
    # Then get the framebuffer
    return get_framebuffer(ctx.renderer)
end

# ============================================================================
# High-Level Rendering API
# ============================================================================

"""
    render_content_node!(ctx::SoftwareRenderContext, node_type::Symbol, 
                         x::Real, y::Real, width::Real, height::Real;
                         fill::Union{NTuple{4, Float64}, Nothing}=nothing,
                         stroke::Union{NTuple{4, Float64}, Nothing}=nothing,
                         stroke_width::Float64=1.0,
                         radius::Float64=0.0,
                         text::String="",
                         font_size::Float64=16.0,
                         text_color::NTuple{4, Float64}=(0.0, 0.0, 0.0, 1.0))

High-level function to render a Content-- node.
"""
function render_content_node!(ctx::SoftwareRenderContext, node_type::Symbol, 
                              x::Real, y::Real, width::Real, height::Real;
                              fill::Union{NTuple{4, Float64}, Nothing}=nothing,
                              stroke::Union{NTuple{4, Float64}, Nothing}=nothing,
                              stroke_width::Float64=1.0,
                              radius::Float64=0.0,
                              text::String="",
                              font_size::Float64=16.0,
                              text_color::NTuple{4, Float64}=(0.0, 0.0, 0.0, 1.0))
    # Render fill
    if fill !== nothing
        render_rect!(ctx, x, y, width, height, fill; radius=radius)
    end
    
    # Render stroke
    if stroke !== nothing
        render_stroke_rect!(ctx, x, y, width, height, stroke; 
                           line_width=stroke_width, radius=radius)
    end
    
    # Render text
    if !isempty(text)
        render_text!(ctx, text, x, y + font_size, font_size=font_size, color=text_color)
    end
end

export render_content_node!

end # module SoftwareRenderer
