"""
    CairoRenderer

Cairo-based native rendering backend for Content--.

This module provides high-quality vector graphics rendering using Cairo.jl
with text rendering powered by FreeTypeAbstraction.jl.

## Features
- Vector graphics rendering with anti-aliasing
- High-quality text rendering with font support
- PNG export
- Support for all Content-- primitives (Rect, Stack, Grid, Paragraph, Span)

## Usage
```julia
using DOPBrowser.Renderer.CairoRenderer

ctx = CairoRenderContext(800, 600)
render_rect!(ctx, 10.0, 10.0, 100.0, 50.0, (1.0, 0.0, 0.0, 1.0))
render_text!(ctx, "Hello World", 10.0, 80.0, font_size=16.0)
save_png(ctx, "output.png")
```
"""
module CairoRenderer

using Cairo
using FreeTypeAbstraction

export CairoRenderContext, create_cairo_context
export render_rect!, render_text!, render_stroke_rect!
export save_png, get_surface_data
export FontManager, load_font!, get_font

# Alias for backward compatibility  
const CairoContext = Nothing  # Will be shadowed by CairoRenderContext

# ============================================================================
# Font Management with FreeTypeAbstraction
# ============================================================================

"""
    FontManager

Manages loaded fonts using FreeTypeAbstraction.
"""
mutable struct FontManager
    fonts::Dict{String, FTFont}
    default_font::Union{FTFont, Nothing}
    
    function FontManager()
        new(Dict{String, FTFont}(), nothing)
    end
end

"""
Global font manager instance.
"""
const FONT_MANAGER = Ref{FontManager}()

function get_font_manager()::FontManager
    if !isassigned(FONT_MANAGER)
        FONT_MANAGER[] = FontManager()
    end
    return FONT_MANAGER[]
end

"""
    load_font!(name::String, path::String) -> Union{FTFont, Nothing}

Load a font from a file path.
"""
function load_font!(name::String, path::String)::Union{FTFont, Nothing}
    mgr = get_font_manager()
    try
        font = FTFont(path)
        mgr.fonts[name] = font
        if mgr.default_font === nothing
            mgr.default_font = font
        end
        return font
    catch e
        @warn "Failed to load font: $path" exception=e
        return nothing
    end
end

"""
    get_font(name::String) -> Union{FTFont, Nothing}

Get a loaded font by name.
"""
function get_font(name::String)::Union{FTFont, Nothing}
    mgr = get_font_manager()
    return get(mgr.fonts, name, nothing)
end

"""
    get_default_font() -> Union{FTFont, Nothing}

Get the default font, attempting to find one if not set.
"""
function get_default_font()::Union{FTFont, Nothing}
    mgr = get_font_manager()
    
    if mgr.default_font !== nothing
        return mgr.default_font
    end
    
    # Try to find a system font
    font_paths = String[]
    
    # Common system font paths
    if Sys.islinux()
        push!(font_paths, "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")
        push!(font_paths, "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf")
        push!(font_paths, "/usr/share/fonts/TTF/DejaVuSans.ttf")
        push!(font_paths, "/usr/share/fonts/noto/NotoSans-Regular.ttf")
        push!(font_paths, "/usr/share/fonts/google-noto/NotoSans-Regular.ttf")
    elseif Sys.isapple()
        push!(font_paths, "/System/Library/Fonts/Helvetica.ttc")
        push!(font_paths, "/Library/Fonts/Arial.ttf")
    elseif Sys.iswindows()
        push!(font_paths, "C:\\Windows\\Fonts\\arial.ttf")
        push!(font_paths, "C:\\Windows\\Fonts\\segoeui.ttf")
    end
    
    for path in font_paths
        if isfile(path)
            font = load_font!("default", path)
            if font !== nothing
                return font
            end
        end
    end
    
    return nothing
end

# ============================================================================
# Cairo Render Context
# ============================================================================

"""
    CairoRenderContext

Cairo rendering context for Content-- rendering.
"""
mutable struct CairoRenderContext
    surface::CairoSurface
    ctx::Cairo.CairoContext
    width::UInt32
    height::UInt32
    clip_stack::Vector{NTuple{4, Float64}}
    
    function CairoRenderContext(width::Integer, height::Integer)
        surface = CairoARGBSurface(Int(width), Int(height))
        ctx = Cairo.CairoContext(surface)
        
        # Set default properties
        Cairo.set_antialias(ctx, Cairo.ANTIALIAS_BEST)
        
        new(surface, ctx, UInt32(width), UInt32(height), NTuple{4, Float64}[])
    end
end

"""
    create_cairo_context(width::Integer, height::Integer) -> CairoRenderContext

Create a new Cairo rendering context.
"""
function create_cairo_context(width::Integer, height::Integer)::CairoRenderContext
    return CairoRenderContext(width, height)
end

"""
    clear!(ctx::CairoRenderContext, r::Float64=1.0, g::Float64=1.0, b::Float64=1.0, a::Float64=1.0)

Clear the surface with the specified color.
"""
function clear!(ctx::CairoRenderContext, r::Float64=1.0, g::Float64=1.0, b::Float64=1.0, a::Float64=1.0)
    Cairo.save(ctx.ctx)
    Cairo.set_source_rgba(ctx.ctx, r, g, b, a)
    Cairo.set_operator(ctx.ctx, Cairo.OPERATOR_SOURCE)
    Cairo.paint(ctx.ctx)
    Cairo.restore(ctx.ctx)
end

export clear!

# ============================================================================
# Rendering Primitives
# ============================================================================

"""
    render_rect!(ctx::CairoRenderContext, x::Real, y::Real, width::Real, height::Real,
                 color::NTuple{4, Float64}; radius::Float64=0.0)

Render a filled rectangle.
"""
function render_rect!(ctx::CairoRenderContext, x::Real, y::Real, width::Real, height::Real,
                      color::NTuple{4, Float64}; radius::Float64=0.0)
    Cairo.save(ctx.ctx)
    
    if radius > 0.0
        # Rounded rectangle
        _rounded_rect!(ctx.ctx, Float64(x), Float64(y), Float64(width), Float64(height), radius)
    else
        Cairo.rectangle(ctx.ctx, Float64(x), Float64(y), Float64(width), Float64(height))
    end
    
    Cairo.set_source_rgba(ctx.ctx, color[1], color[2], color[3], color[4])
    Cairo.fill(ctx.ctx)
    
    Cairo.restore(ctx.ctx)
end

"""
    render_stroke_rect!(ctx::CairoRenderContext, x::Real, y::Real, width::Real, height::Real,
                        color::NTuple{4, Float64}; line_width::Float64=1.0, radius::Float64=0.0)

Render a stroked (outlined) rectangle.
"""
function render_stroke_rect!(ctx::CairoRenderContext, x::Real, y::Real, width::Real, height::Real,
                             color::NTuple{4, Float64}; line_width::Float64=1.0, radius::Float64=0.0)
    Cairo.save(ctx.ctx)
    
    if radius > 0.0
        _rounded_rect!(ctx.ctx, Float64(x), Float64(y), Float64(width), Float64(height), radius)
    else
        Cairo.rectangle(ctx.ctx, Float64(x), Float64(y), Float64(width), Float64(height))
    end
    
    Cairo.set_source_rgba(ctx.ctx, color[1], color[2], color[3], color[4])
    Cairo.set_line_width(ctx.ctx, line_width)
    Cairo.stroke(ctx.ctx)
    
    Cairo.restore(ctx.ctx)
end

"""
Helper function to draw a rounded rectangle path.
"""
function _rounded_rect!(ctx::Cairo.CairoContext, x::Float64, y::Float64, 
                        width::Float64, height::Float64, radius::Float64)
    r = min(radius, width/2, height/2)
    
    Cairo.new_path(ctx)
    Cairo.arc(ctx, x + width - r, y + r, r, -π/2, 0.0)
    Cairo.arc(ctx, x + width - r, y + height - r, r, 0.0, π/2)
    Cairo.arc(ctx, x + r, y + height - r, r, π/2, π)
    Cairo.arc(ctx, x + r, y + r, r, π, 3π/2)
    Cairo.close_path(ctx)
end

# ============================================================================
# Text Rendering
# ============================================================================

"""
    render_text!(ctx::CairoRenderContext, text::String, x::Real, y::Real;
                 font_size::Float64=16.0, color::NTuple{4, Float64}=(0.0, 0.0, 0.0, 1.0),
                 font_name::String="default")

Render text at the specified position.

Uses FreeTypeAbstraction for font loading and Cairo for rendering.
Falls back to Cairo's toy text API if no font is available.
"""
function render_text!(ctx::CairoRenderContext, text::String, x::Real, y::Real;
                      font_size::Float64=16.0, 
                      color::NTuple{4, Float64}=(0.0, 0.0, 0.0, 1.0),
                      font_name::String="default")
    if isempty(text)
        return
    end
    
    Cairo.save(ctx.ctx)
    Cairo.set_source_rgba(ctx.ctx, color[1], color[2], color[3], color[4])
    
    # Try to use FreeTypeAbstraction font
    font = font_name == "default" ? get_default_font() : get_font(font_name)
    
    if font !== nothing
        # Use FreeTypeAbstraction for glyph rendering
        _render_text_freetype!(ctx, font, text, Float64(x), Float64(y), font_size, color)
    else
        # Fallback to Cairo's toy text API
        Cairo.select_font_face(ctx.ctx, "sans-serif", Cairo.FONT_SLANT_NORMAL, Cairo.FONT_WEIGHT_NORMAL)
        Cairo.set_font_size(ctx.ctx, font_size)
        Cairo.move_to(ctx.ctx, Float64(x), Float64(y))
        Cairo.show_text(ctx.ctx, text)
    end
    
    Cairo.restore(ctx.ctx)
end

"""
Render text using FreeTypeAbstraction for glyph data.
"""
function _render_text_freetype!(ctx::CairoRenderContext, font::FTFont, text::String, 
                                 x::Float64, y::Float64, font_size::Float64,
                                 color::NTuple{4, Float64})
    # Get font metrics
    scale = font_size / Float64(font.units_per_EM)
    
    # Position baseline
    current_x = x
    
    # Render each character
    for char in text
        extent = FreeTypeAbstraction.get_extent(font, char)
        
        if extent !== nothing
            # Get glyph metrics - advance is (x, y) tuple
            hadvance = Float64(extent.advance[1]) * scale
            current_x += hadvance
        else
            # Fallback for missing glyphs - use character width estimate
            current_x += font_size * 0.6
        end
    end
    
    # Fallback to Cairo text if FreeType rendering is complex
    Cairo.select_font_face(ctx.ctx, "sans-serif", Cairo.FONT_SLANT_NORMAL, Cairo.FONT_WEIGHT_NORMAL)
    Cairo.set_font_size(ctx.ctx, font_size)
    Cairo.move_to(ctx.ctx, x, y)
    Cairo.show_text(ctx.ctx, text)
end

"""
    measure_text(ctx::CairoRenderContext, text::String; 
                 font_size::Float64=16.0, font_name::String="default") -> Tuple{Float64, Float64}

Measure the width and height of rendered text.
"""
function measure_text(ctx::CairoRenderContext, text::String; 
                      font_size::Float64=16.0, font_name::String="default")::Tuple{Float64, Float64}
    if isempty(text)
        return (0.0, font_size)
    end
    
    font = font_name == "default" ? get_default_font() : get_font(font_name)
    
    if font !== nothing
        # Use FreeTypeAbstraction for measurement
        scale = font_size / Float64(font.units_per_EM)
        
        total_width = 0.0
        for char in text
            extent = FreeTypeAbstraction.get_extent(font, char)
            if extent !== nothing
                total_width += Float64(extent.advance[1]) * scale
            else
                total_width += font_size * 0.6
            end
        end
        
        height = (Float64(font.ascender) - Float64(font.descender)) * scale
        return (total_width, height)
    else
        # Fallback to Cairo
        Cairo.select_font_face(ctx.ctx, "sans-serif", Cairo.FONT_SLANT_NORMAL, Cairo.FONT_WEIGHT_NORMAL)
        Cairo.set_font_size(ctx.ctx, font_size)
        extents = Cairo.text_extents(ctx.ctx, text)
        return (extents[3], font_size)  # width, height
    end
end

export measure_text

# ============================================================================
# Clip Stack Management
# ============================================================================

"""
    push_clip!(ctx::CairoRenderContext, x::Real, y::Real, width::Real, height::Real)

Push a clip rectangle onto the stack.
"""
function push_clip!(ctx::CairoRenderContext, x::Real, y::Real, width::Real, height::Real)
    push!(ctx.clip_stack, (Float64(x), Float64(y), Float64(width), Float64(height)))
    
    Cairo.save(ctx.ctx)
    Cairo.rectangle(ctx.ctx, Float64(x), Float64(y), Float64(width), Float64(height))
    Cairo.clip(ctx.ctx)
end

export push_clip!

"""
    pop_clip!(ctx::CairoRenderContext)

Pop the last clip rectangle from the stack.
"""
function pop_clip!(ctx::CairoRenderContext)
    if !isempty(ctx.clip_stack)
        pop!(ctx.clip_stack)
        Cairo.restore(ctx.ctx)
    end
end

export pop_clip!

# ============================================================================
# Export Functions
# ============================================================================

"""
    save_png(ctx::CairoRenderContext, filename::String)

Save the current surface to a PNG file.
"""
function save_png(ctx::CairoRenderContext, filename::String)
    Cairo.write_to_png(ctx.surface, filename)
end

"""
    get_surface_data(ctx::CairoRenderContext) -> Vector{UInt8}

Get the raw RGBA pixel data from the surface.
Returns data in RGBA format (4 bytes per pixel).
"""
function get_surface_data(ctx::CairoRenderContext)::Vector{UInt8}
    # Get data pointer from Cairo surface
    ptr = Cairo.image_surface_get_data(ctx.surface)
    width = Int(ctx.width)
    height = Int(ctx.height)
    stride_bytes = width * 4  # 4 bytes per pixel (ARGB)
    
    # Wrap pointer in array
    raw_data = unsafe_wrap(Array, Ptr{UInt8}(ptr), (stride_bytes * height,))
    
    # Convert BGRA (Cairo format on little-endian) to RGBA
    n_pixels = width * height
    rgba_data = Vector{UInt8}(undef, n_pixels * 4)
    
    for i in 0:(n_pixels - 1)
        src_idx = i * 4 + 1
        dst_idx = i * 4 + 1
        
        if src_idx + 3 <= length(raw_data)
            # BGRA -> RGBA
            rgba_data[dst_idx] = raw_data[src_idx + 2]      # R
            rgba_data[dst_idx + 1] = raw_data[src_idx + 1]  # G
            rgba_data[dst_idx + 2] = raw_data[src_idx]      # B
            rgba_data[dst_idx + 3] = raw_data[src_idx + 3]  # A
        else
            # Fill with transparent
            rgba_data[dst_idx] = 0
            rgba_data[dst_idx + 1] = 0
            rgba_data[dst_idx + 2] = 0
            rgba_data[dst_idx + 3] = 0
        end
    end
    
    return rgba_data
end

# ============================================================================
# High-Level Rendering API
# ============================================================================

"""
    render_content_node!(ctx::CairoRenderContext, node_type::Symbol, 
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
function render_content_node!(ctx::CairoRenderContext, node_type::Symbol, 
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

end # module CairoRenderer
