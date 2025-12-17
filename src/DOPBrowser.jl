"""
    DOPBrowser

A Data-Oriented Programming (DOP) browser engine base implementation in Julia.

This module provides a render-friendly Intermediate Representation (IR) that replaces
traditional DOM & CSSOM with cache-efficient, SIMD-friendly data structures.

## Key Design Principles

- **Structure of Arrays (SoA)**: DOM treated as flat arrays, not object trees
- **Zero-Copy Parsing**: Flat token tape with immediate string interning
- **Index-based Nodes**: Use UInt32 indices instead of pointers
- **Archetype System**: Solve unique style combinations once, memcpy to nodes
- **SIMD-friendly Layout**: Contiguous float arrays for vectorized computation
- **Linear Render Buffer**: Direct WebGPU upload-ready command buffer
- **Cache Maximization**: Batch costly operations for optimal CPU cache usage

## Content-- Language Support

This browser implements the Content-- v6.0 specification:
- **Hybrid AOT/JIT Model**: AOT for static structure, JIT for dynamic text
- **Layout Primitives**: Stack, Grid, Scroll, Rect
- **Text Primitives**: Paragraph, Span, Link (JIT-compiled TextClusters)
- **Reactive System**: Environment switches, variable injection, event bindings
- **Virtual JS Interface**: DOM-like API without actual DOM

## Complete Browser Pipeline

1. **Network** → Fetch HTML, CSS, images, fonts
2. **Parse** → HTML tokenization → DOM construction
3. **Style** → CSS parsing → Archetype resolution → Style flattening
4. **Layout** → Content-- layout engine → Position computation
5. **Render** → GPU command buffer → WebGPU rendering → PNG export
"""
module DOPBrowser

# =============================================================================
# Modular Architecture
# =============================================================================
# The browser engine is organized into the following modules:
# 1. RustParser - Rust-based HTML/CSS parser (REQUIRED for production)
# 2. RustRenderer - Rust-based GPU renderer (REQUIRED for production)
# 3. Layout - SIMD-friendly layout calculation
# 4. DOMCSSOM - Virtual DOM/CSSOM representation
# 5. Compiler - HTML+CSS to Content-- compilation
# 6. ContentMM - Content-- IR and runtime
# 7. Network - HTTP/HTTPS networking layer
# 8. EventLoop - Browser main event loop
#
# DEPRECATED modules (maintained for compatibility, will be removed):
# - HTMLParser (use RustParser instead)
# - CSSParserModule (use RustParser instead)
# - Renderer (use RustRenderer instead)

# Rust-based Content-- builder (REQUIRED)
include("RustContent/RustContent.jl")

# Rust-based HTML/CSS parser and Content-- compiler (REQUIRED)
include("RustParser/RustParser.jl")

# Rust-based rendering engine (winit + wgpu) (REQUIRED)
include("RustRenderer/RustRenderer.jl")

# DEPRECATED: Julia implementations (for backward compatibility only)
include("HTMLParser/HTMLParser.jl")
include("CSSParser/CSSParserModule.jl")

# Layout module (LayoutArrays)
include("Layout/Layout.jl")

# DOM/CSSOM module (NodeTable + StyleArchetypes + RenderBuffer + StringInterner)
include("DOMCSSOM/DOMCSSOM.jl")

# Compiler module (HTML+CSS to Content--)
include("Compiler/Compiler.jl")

# Event Loop module
include("EventLoop/EventLoop.jl")

# Network layer
include("Network/Network.jl")

# Core browser context (uses the modular components)
include("Core.jl")

# =============================================================================
# Simplified Functional Pipeline
# =============================================================================

# FP-style pipeline for Content-- → Rendering → Interaction
include("Pipeline/Pipeline.jl")

# =============================================================================
# Interactive UI Library Modules (Production-Ready)
# =============================================================================

# Window management for platform integration
include("Window/Window.jl")

# Reactive state management
include("State/State.jl")

# High-level widget components
include("Widgets/Widgets.jl")

# Application lifecycle management
include("Application/Application.jl")

# =============================================================================
# Re-exports from Modular Submodules
# =============================================================================

# Re-exports from HTMLParser
using .HTMLParser: StringPool, intern!, get_string, get_id
using .HTMLParser: TokenType, Token, Tokenizer, tokenize!, reset!, get_tokens

# Re-exports from DOMCSSOM
using .DOMCSSOM: NodeKind, DOMTable, add_node!, get_parent, get_first_child, get_next_sibling, get_tag, set_parent!, set_first_child!, set_next_sibling!, node_count,
                  NODE_ELEMENT, NODE_TEXT, NODE_COMMENT, NODE_DOCUMENT, NODE_DOCTYPE,
                  get_id_attr, get_class_attr, get_style_attr, set_attributes!
using .DOMCSSOM: StyleProperty, Archetype, ArchetypeTable, get_or_create_archetype!, apply_archetype!, get_archetype, archetype_count
using .DOMCSSOM: RenderCommand, CommandBuffer, emit_rect!, emit_text!, emit_image!, emit_stroke!, clear!, get_commands, command_count

# Re-exports from Layout
using .Layout: LayoutData, resize_layout!, set_bounds!, get_bounds, set_position!, get_position, compute_layout!,
                    set_css_position!, set_offsets!, set_margins!, set_paddings!, set_overflow!, set_visibility!, set_z_index!,
                    set_background_color!, get_background_color, set_borders!, has_border

# Export modules for direct access
export HTMLParser, Layout, DOMCSSOM, Compiler, EventLoop, CSSParserModule

# Rust Content-- builder
using .RustContent
export RustContent

# ============================================================================
# Complete Browser Process
# ============================================================================

"""
    Browser

Complete browser instance with full pipeline:
Network → Parse → Style → Layout → Render → GPU/PNG Output

NOTE: This is a legacy compatibility layer. For new applications,
use the Application/Widgets framework with RustContent builder.

## Usage
```julia
browser = Browser(width=1920, height=1080)
load_html!(browser, "<div>Hello World</div>")
render_to_png!(browser, "output.png")
```
"""
mutable struct Browser
    # Core context
    context::BrowserContext
    
    # Networking
    network::Network.NetworkContext
    
    # Rust Renderer handle
    renderer::RustRenderer.RustRendererHandle
    
    # Dimensions
    width::UInt32
    height::UInt32
    
    # State
    current_url::String
    title::String
    is_loading::Bool
    
    function Browser(; width::UInt32 = UInt32(1920), height::UInt32 = UInt32(1080))
        ctx = create_context(viewport_width=Float32(width), viewport_height=Float32(height))
        network = Network.NetworkContext()
        renderer = RustRenderer.create_renderer(Int(width), Int(height))
        
        new(ctx, network, renderer, width, height, "", "", false)
    end
end

export Browser

"""
    load!(browser::Browser, url::String) -> Bool

Load a URL and process the document.
"""
function load!(browser::Browser, url::String)::Bool
    browser.is_loading = true
    browser.current_url = url
    
    # Fetch the document
    response = Network.fetch!(browser.network, url, 
                               resource_type=Network.RESOURCE_HTML)
    
    if response.status_code != 200
        browser.is_loading = false
        return false
    end
    
    # Parse HTML using traditional pipeline
    html = String(response.body)
    process_document!(browser.context, html)
    
    browser.is_loading = false
    return true
end

export load!

"""
    load_html!(browser::Browser, html::String)

Load HTML directly (for testing).
"""
function load_html!(browser::Browser, html::String)
    browser.is_loading = true
    browser.current_url = "about:blank"
    
    process_document!(browser.context, html)
    
    browser.is_loading = false
end

export load_html!

"""
    render!(browser::Browser)

Render the current document using the Rust renderer.
"""
function render!(browser::Browser)
    # Clear renderer
    RustRenderer.clear!(browser.renderer)
    RustRenderer.set_clear_color!(browser.renderer, 1.0f0, 1.0f0, 1.0f0, 1.0f0)
    
    # Get render commands and submit to Rust renderer
    cmds = get_commands(browser.context.render_buffer)
    for cmd in cmds
        RustRenderer.add_rect!(browser.renderer,
            Float32(cmd.x), Float32(cmd.y), 
            Float32(cmd.width), Float32(cmd.height),
            Float32(cmd.color_r), Float32(cmd.color_g), 
            Float32(cmd.color_b), Float32(cmd.color_a))
    end
    
    # Render
    RustRenderer.render!(browser.renderer)
end

export render!

"""
    render_to_png!(browser::Browser, filename::String)

Render and export to PNG using Rust renderer.
"""
function render_to_png!(browser::Browser, filename::String)
    render!(browser)
    RustRenderer.export_png!(browser.renderer, filename)
end

export render_to_png!

"""
    get_png_data(browser::Browser) -> Vector{UInt8}

Render and get PNG-encoded data as bytes.
"""
function get_png_data(browser::Browser)::Vector{UInt8}
    render!(browser)
    framebuffer = RustRenderer.get_framebuffer(browser.renderer)
    return Pipeline.encode_png(framebuffer, browser.width, browser.height)
end

export get_png_data

"""
    set_viewport!(browser::Browser, width::UInt32, height::UInt32)

Resize the browser viewport.
"""
function set_viewport!(browser::Browser, width::UInt32, height::UInt32)
    browser.context.viewport_width = Float32(width)
    browser.context.viewport_height = Float32(height)
    browser.width = width
    browser.height = height
    RustRenderer.renderer_resize!(browser.renderer, Int(width), Int(height))
end

export set_viewport!

# ============================================================================
# Module Initialization - Verify Rust Libraries
# ============================================================================

function __init__()
    # Verify that required Rust libraries are available
    try
        RustParser.is_available()
        @info "RustParser library loaded successfully"
    catch e
        rust_dir = joinpath("rust", "dop-parser")
        @error "Failed to load RustParser library. Please build it with: cd $(rust_dir) && cargo build --release" exception=e
        rethrow(e)
    end
    
    try
        RustRenderer.is_available()
        @info "RustRenderer library loaded successfully"
    catch e
        rust_dir = joinpath("rust", "dop-renderer")
        @error "Failed to load RustRenderer library. Please build it with: cd $(rust_dir) && cargo build --release" exception=e
        rethrow(e)
    end
end

end # module DOPBrowser
