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

# Core modules
include("StringInterner.jl")
include("TokenTape.jl")
include("NodeTable.jl")
include("StyleArchetypes.jl")
include("LayoutArrays.jl")
include("RenderBuffer.jl")
include("CSSParser.jl")
include("Core.jl")

# Content-- IR modules
include("ContentMM/ContentMM.jl")

# Network layer
include("Network/Network.jl")

# Rendering pipeline
include("Renderer/Renderer.jl")

# Re-exports from submodules
using .StringInterner: StringPool, intern!, get_string, get_id
using .TokenTape: TokenType, Token, Tokenizer, tokenize!, reset!, get_tokens
using .NodeTable: NodeKind, DOMTable, add_node!, get_parent, get_first_child, get_next_sibling, get_tag, set_parent!, set_first_child!, set_next_sibling!, node_count,
                  NODE_ELEMENT, NODE_TEXT, NODE_COMMENT, NODE_DOCUMENT, NODE_DOCTYPE,
                  get_id_attr, get_class_attr, get_style_attr, set_attributes!
using .StyleArchetypes: StyleProperty, Archetype, ArchetypeTable, get_or_create_archetype!, apply_archetype!, get_archetype, archetype_count
using .LayoutArrays: LayoutData, resize_layout!, set_bounds!, get_bounds, set_position!, get_position, compute_layout!,
                    set_css_position!, set_offsets!, set_margins!, set_paddings!, set_overflow!, set_visibility!, set_z_index!,
                    set_background_color!, get_background_color
using .RenderBuffer: RenderCommand, CommandBuffer, emit_rect!, emit_text!, emit_image!, clear!, get_commands, command_count
using .CSSParser: CSSStyles, parse_inline_style, parse_color, parse_length,
                  POSITION_STATIC, POSITION_RELATIVE, POSITION_ABSOLUTE, POSITION_FIXED,
                  OVERFLOW_VISIBLE, OVERFLOW_HIDDEN,
                  DISPLAY_BLOCK, DISPLAY_INLINE, DISPLAY_NONE

export StringPool, intern!, get_string, get_id
export TokenType, Token, Tokenizer, tokenize!, reset!, get_tokens
export NodeKind, DOMTable, add_node!, get_parent, get_first_child, get_next_sibling, get_tag, set_parent!, set_first_child!, set_next_sibling!, node_count,
       NODE_ELEMENT, NODE_TEXT, NODE_COMMENT, NODE_DOCUMENT, NODE_DOCTYPE,
       get_id_attr, get_class_attr, get_style_attr, set_attributes!
export StyleProperty, Archetype, ArchetypeTable, get_or_create_archetype!, apply_archetype!, get_archetype, archetype_count
export LayoutData, resize_layout!, set_bounds!, get_bounds, set_position!, get_position, compute_layout!,
       set_css_position!, set_offsets!, set_margins!, set_paddings!, set_overflow!, set_visibility!, set_z_index!,
       set_background_color!, get_background_color
export RenderCommand, CommandBuffer, emit_rect!, emit_text!, emit_image!, clear!, get_commands, command_count
export CSSStyles, parse_inline_style, parse_color, parse_length,
       POSITION_STATIC, POSITION_RELATIVE, POSITION_ABSOLUTE, POSITION_FIXED,
       OVERFLOW_VISIBLE, OVERFLOW_HIDDEN,
       DISPLAY_BLOCK, DISPLAY_INLINE, DISPLAY_NONE

# Core API
using .Core: BrowserContext, create_context, parse_html!, apply_styles!, compute_layouts!, generate_render_commands!, process_document!
export BrowserContext, create_context, parse_html!, apply_styles!, compute_layouts!, generate_render_commands!, process_document!

# Content-- IR
using .ContentMM
export ContentMM

# Network layer
using .Network
export Network

# Rendering pipeline
using .Renderer
export Renderer

# ============================================================================
# Complete Browser Process
# ============================================================================

"""
    Browser

Complete browser instance with full pipeline:
Network → Parse → Style → Layout → Render → GPU/PNG Output

## Usage
```julia
browser = Browser(width=1920, height=1080)
load!(browser, "https://example.com")
render_to_png!(browser, "output.png")
```
"""
mutable struct Browser
    # Core context
    context::BrowserContext
    
    # Content-- runtime
    runtime::ContentMM.Runtime.RuntimeContext
    
    # Networking
    network::Network.NetworkContext
    
    # Rendering
    render_pipeline::Renderer.RenderPipeline
    
    # JS interface
    js_interface::ContentMM.Runtime.JSInterface
    
    # State
    current_url::String
    title::String
    is_loading::Bool
    
    function Browser(; width::UInt32 = UInt32(1920), height::UInt32 = UInt32(1080))
        ctx = create_context(viewport_width=Float32(width), viewport_height=Float32(height))
        runtime = ContentMM.Runtime.RuntimeContext(Float32(width), Float32(height))
        network = Network.NetworkContext()
        pipeline = Renderer.RenderPipeline(width, height)
        js = ContentMM.Runtime.JSInterface(runtime)
        
        new(ctx, runtime, network, pipeline, js, "", "", false)
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
    
    # Parse HTML
    html = String(response.body)
    process_document!(browser.context, html)
    
    # Initialize Content-- runtime with parsed DOM
    ContentMM.Runtime.initialize!(
        browser.runtime,
        ContentMM.Primitives.NodeTable(),
        ContentMM.Properties.PropertyTable()
    )
    
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

Render the current document.
"""
function render!(browser::Browser)
    # Update runtime
    ContentMM.Runtime.update!(browser.runtime, 0.016f0)  # ~60fps
    
    # Render to pipeline
    Renderer.render_frame!(browser.render_pipeline, browser.context.render_buffer)
end

export render!

"""
    render_to_png!(browser::Browser, filename::String)

Render and export to PNG.
"""
function render_to_png!(browser::Browser, filename::String)
    render!(browser)
    Renderer.export_png!(browser.render_pipeline, filename)
end

export render_to_png!

"""
    get_png_data(browser::Browser) -> Vector{UInt8}

Render and get PNG data as bytes.
"""
function get_png_data(browser::Browser)::Vector{UInt8}
    render!(browser)
    return Renderer.get_png_data(browser.render_pipeline)
end

export get_png_data

"""
    set_viewport!(browser::Browser, width::UInt32, height::UInt32)

Resize the browser viewport.
"""
function set_viewport!(browser::Browser, width::UInt32, height::UInt32)
    browser.context.viewport_width = Float32(width)
    browser.context.viewport_height = Float32(height)
    browser.runtime.viewport_width = Float32(width)
    browser.runtime.viewport_height = Float32(height)
    Renderer.resize!(browser.render_pipeline, width, height)
end

export set_viewport!

"""
    scroll_to!(browser::Browser, x::Float32, y::Float32)

Scroll the viewport.
"""
function scroll_to!(browser::Browser, x::Float32, y::Float32)
    browser.runtime.scroll_x = x
    browser.runtime.scroll_y = y
    ContentMM.Runtime.resolve_sticky!(browser.runtime)
end

export scroll_to!

"""
    dispatch_event!(browser::Browser, node_id::UInt32, 
                    event_type::ContentMM.Reactive.EventType,
                    event_data::Dict{Symbol, Any}) -> Bool

Dispatch an event to a node.
"""
function dispatch_event!(browser::Browser, node_id::UInt32,
                         event_type::ContentMM.Reactive.EventType,
                         event_data::Dict{Symbol, Any})::Bool
    return ContentMM.Runtime.dispatch_event!(browser.runtime, node_id, 
                                              event_type, event_data)
end

export dispatch_event!

"""
    js_eval(browser::Browser, node_id::UInt32, property::Symbol) -> Any

Get a property value via the virtual JS interface.
"""
function js_eval(browser::Browser, node_id::UInt32, property::Symbol)::Any
    return ContentMM.Runtime.js_get_property(browser.js_interface, node_id, property)
end

export js_eval

"""
    js_call(browser::Browser, node_id::UInt32, 
            method::Symbol, args::Vector{Any}) -> Any

Call a method via the virtual JS interface.
"""
function js_call(browser::Browser, node_id::UInt32,
                 method::Symbol, args::Vector{Any})::Any
    return ContentMM.Runtime.js_call_method(browser.js_interface, node_id, method, args)
end

export js_call

end # module DOPBrowser
