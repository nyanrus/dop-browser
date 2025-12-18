"""
    DOPBrowser

A Data-Oriented Programming (DOP) browser engine base implementation in Julia.

This module provides a render-friendly Intermediate Representation (IR) that replaces
traditional DOM & CSSOM with cache-efficient, SIMD-friendly data structures.

## Architecture

The rendering pipeline follows a clear separation between Rust and Julia:

### Content Text Rendering
```
Content Text Format In → Parse in Rust → Compute Layout in Julia → Flatten Content IR in Rust and Render
```

### Web Rendering  
```
HTML&CSS In w/ Network → Parse in Rust → Lower in Rust → Compute Layout in Julia → Flatten Content IR in Rust and Render
```

### Interaction
```
Extract action-related codes (:hover, :click, etc.) in Julia → Pass to Rendering
```

### Feedback
```
Window and Eventloop in Rust → Apply in Content IR → Compute layout in Julia if needed → Flatten and Render in Rust
```

## Key Design Principles

- **Structure of Arrays (SoA)**: DOM treated as flat arrays, not object trees
- **SIMD-friendly Layout**: Contiguous float arrays for vectorized computation in Julia
- **Rust for Performance**: Parsing, lowering, and rendering done in Rust
- **Julia for Flexibility**: Layout computation and interaction logic in Julia
"""
module DOPBrowser

# =============================================================================
# Modular Architecture
# =============================================================================
# The browser engine is organized into the following modules:
#
# RUST SIDE (Required):
# - RustParser: HTML/CSS parsing using html5ever/cssparser
# - RustContent: Content IR building
# - RustRenderer: GPU rendering via wgpu, window management via winit
#
# JULIA SIDE (Layout & Interaction):
# - ContentIR: Core IR types (MathOps, Primitives, Properties)
# - Layout: SIMD-friendly layout calculation
# - Pipeline: Orchestration of the rendering pipeline
# - State: Reactive state management
# - Widgets: High-level UI components
# - Application: Application lifecycle
# - Window: Window abstraction
# - EventLoop: Browser event loop
#
# INTERNAL/LEGACY (Backward Compatibility):
# - HTMLParser, CSSParserModule: Used internally by legacy pipeline
# - DOMCSSOM, Core: Legacy virtual DOM/CSSOM and browser context
# - ContentMM: Legacy Content IR (use ContentIR for new code)

# =============================================================================
# Core Content IR Module (NEW - Clean Architecture)
# =============================================================================

# Content IR - MathOps, Primitives, Properties
include("ContentIR/ContentIR.jl")

# =============================================================================
# Rust-based Modules (REQUIRED)
# =============================================================================

# Rust-based Content IR builder
include("RustContent/RustContent.jl")

# Rust-based HTML/CSS parser and Content IR compiler
include("RustParser/RustParser.jl")

# Rust-based rendering engine (winit + wgpu)
include("RustRenderer/RustRenderer.jl")

# =============================================================================
# Internal/Legacy Modules (Used by legacy pipeline, not for direct use)
# =============================================================================

# HTMLParser - Internal HTML tokenization (use RustParser for new code)
include("HTMLParser/HTMLParser.jl")

# CSSParser - Internal CSS parsing (use RustParser for new code)
include("CSSParser/CSSParserModule.jl")

# Layout module (LayoutArrays) - Still active for Julia-side layout computation
include("Layout/Layout.jl")

# DOM/CSSOM module - Legacy virtual DOM/CSSOM (use ContentIR for new code)
include("DOMCSSOM/DOMCSSOM.jl")

# Event Loop module
include("EventLoop/EventLoop.jl")

# ContentMM - Legacy Content IR (use ContentIR for new code)
include("ContentMM/ContentMM.jl")

# Network layer
include("Network/Network.jl")

# Core browser context (legacy)
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
# Re-exports from ContentIR (NEW - Clean Architecture)
# =============================================================================

# ContentIR exports
using .ContentIR
export ContentIR

# Re-export MathOps types
using .ContentIR.MathOps: Vec2, Box4, Rect, Transform2D, vec2, box4, rect
using .ContentIR.MathOps: lerp, clamp01, remap, smoothstep
using .ContentIR.MathOps: ZERO_VEC2, UNIT_VEC2, ZERO_BOX4, ZERO_RECT
using .ContentIR.MathOps: norm, normalize, magnitude, dot
using .ContentIR.MathOps: horizontal, vertical, total
using .ContentIR.MathOps: IDENTITY_TRANSFORM, translate, scale, rotate
using .ContentIR.MathOps: contains, intersects, intersection, inset_rect, outset_rect

# Re-export Primitives
using .ContentIR.Primitives: NodeType, NODE_ROOT, NODE_STACK, NODE_GRID, NODE_SCROLL, NODE_RECT
using .ContentIR.Primitives: NODE_PARAGRAPH, NODE_SPAN, NODE_LINK, NODE_TEXT_CLUSTER, NODE_EXTERNAL
using .ContentIR.Primitives: ContentNode, NodeTable
using .ContentIR.Primitives: create_node! as create_content_node!, get_node, add_child!, get_children

# Re-export Properties
using .ContentIR.Properties: Direction, DIRECTION_DOWN, DIRECTION_UP, DIRECTION_RIGHT, DIRECTION_LEFT
using .ContentIR.Properties: Pack, PACK_START, PACK_END, PACK_CENTER, PACK_BETWEEN, PACK_AROUND, PACK_EVENLY
using .ContentIR.Properties: Align, ALIGN_START, ALIGN_END, ALIGN_CENTER, ALIGN_STRETCH, ALIGN_BASELINE
using .ContentIR.Properties: Color, color_to_rgba
# Note: parse_color from ContentIR.Properties is NOT exported to avoid conflict with CSSParserModule
# Use ContentIR.Properties.parse_color for the struct-based version
using .ContentIR.Properties: direction_to_vec2, to_vec2, to_box4

# =============================================================================
# Re-exports from Legacy Modules (Backward Compatibility)
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

# Re-exports from Core
using .Core: BrowserContext, create_context, parse_html!, apply_styles!,
             compute_layouts!, generate_render_commands!, process_document!

# Export modules for direct access
export HTMLParser, Layout, DOMCSSOM, EventLoop, CSSParserModule

# Export Core functions
export BrowserContext, create_context, parse_html!, apply_styles!,
       compute_layouts!, generate_render_commands!, process_document!

# Export legacy types for backward compatibility (tests)
export StringPool, intern!, get_string, get_id
export TokenType, Token, Tokenizer, tokenize!, reset!, get_tokens
export NodeKind, DOMTable, add_node!, node_count, get_parent, get_first_child, get_next_sibling, get_tag
export set_parent!, set_first_child!, set_next_sibling!
export NODE_ELEMENT, NODE_TEXT, NODE_COMMENT, NODE_DOCUMENT, NODE_DOCTYPE
export get_id_attr, get_class_attr, get_style_attr, set_attributes!
export StyleProperty, Archetype, ArchetypeTable, get_or_create_archetype!, apply_archetype!, get_archetype, archetype_count
export RenderCommand, CommandBuffer, emit_rect!, emit_text!, emit_image!, emit_stroke!, clear!, get_commands, command_count
export LayoutData, resize_layout!, set_bounds!, get_bounds, set_position!, get_position, compute_layout!
export set_css_position!, set_offsets!, set_margins!, set_paddings!, set_overflow!, set_visibility!, set_z_index!
export set_background_color!, get_background_color, set_borders!, has_border

# Re-export CSSParser functions for backward compatibility (legacy tests)
using .CSSParserModule.CSSCore: parse_color, parse_inline_style, parse_length
using .CSSParserModule.CSSCore: POSITION_STATIC, POSITION_RELATIVE, POSITION_ABSOLUTE, POSITION_FIXED
using .CSSParserModule.CSSCore: OVERFLOW_VISIBLE, OVERFLOW_HIDDEN
using .CSSParserModule.CSSCore: DISPLAY_BLOCK, DISPLAY_INLINE, DISPLAY_NONE, DISPLAY_TABLE
export parse_color, parse_inline_style, parse_length
export POSITION_STATIC, POSITION_RELATIVE, POSITION_ABSOLUTE, POSITION_FIXED
export OVERFLOW_VISIBLE, OVERFLOW_HIDDEN
export DISPLAY_BLOCK, DISPLAY_INLINE, DISPLAY_NONE, DISPLAY_TABLE

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
