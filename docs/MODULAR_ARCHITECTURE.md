# Modular Architecture

DOPBrowser has been refactored into a modular architecture for better organization, maintainability, and extensibility.

## Module Overview

The browser engine is organized into the following modules:

| Module | Purpose | Location |
|--------|---------|----------|
| **HTMLParser** | HTML tokenization and string interning | `src/HTMLParser/` |
| **CSSParserModule** | CSS parsing and style computation | `src/CSSParser/` |
| **Layout** | SIMD-friendly layout calculation | `src/Layout/` |
| **DOMCSSOM** | Virtual DOM/CSSOM representation | `src/DOMCSSOM/` |
| **Compiler** | HTML+CSS to Content-- compilation | `src/Compiler/` |
| **ContentMM** | Content-- IR and runtime | `src/ContentMM/` |
| **Network** | HTTP/HTTPS networking layer | `src/Network/` |
| **Renderer** | GPU rendering and PNG export | `src/Renderer/` |
| **EventLoop** | Browser main event loop | `src/EventLoop/` |

## Module Details

### HTMLParser

The HTML parsing module provides:
- **StringInterner**: Zero-copy string interning for efficient memory usage
- **TokenTape**: Flat token tape for cache-efficient DOM construction

```julia
using DOPBrowser.HTMLParser

pool = StringPool()
tokenizer = Tokenizer(pool)
tokens = tokenize!(tokenizer, "<div><p>Hello</p></div>")
```

### CSSParserModule

The CSS parsing module provides:
- Style parsing (inline and block)
- Color parsing (hex, rgb, rgba, named colors)
- Length parsing (px, %, em, mm, auto)
- Comprehensive CSS property support

```julia
using DOPBrowser.CSSParserModule

styles = parse_inline_style("width: 100px; background-color: red;")
color = parse_color("#ff0000")
(px, is_auto) = parse_length("50%", 800.0f0)
```

### Layout

SIMD-friendly layout calculation using Structure of Arrays (SoA) format:

```julia
using DOPBrowser.Layout

layout = LayoutData()
resize_layout!(layout, 100)
set_bounds!(layout, 1, 200.0f0, 150.0f0)
compute_layout!(layout, parents, first_children, next_siblings)
```

### DOMCSSOM

Virtual DOM and CSSOM representation:
- **NodeTable**: SoA DOM representation
- **StyleArchetypes**: Efficient style computation via archetypes
- **RenderBuffer**: Linear command buffer for GPU upload
- **StringInterner**: Shared string pool

```julia
using DOPBrowser.DOMCSSOM

pool = StringPool()
dom = DOMTable(pool)
root_id = add_node!(dom, NODE_DOCUMENT)
```

### Compiler

HTML+CSS to Content-- compilation with pre-evaluation:

```julia
using DOPBrowser.Compiler

ctx = CompilerContext()
result = compile_document!(ctx, html_source, css_source)
```

### EventLoop

Browser main event loop following HTML5 specification:
- Task scheduling
- Microtask queue
- Animation frame callbacks
- Timer management

```julia
using DOPBrowser.EventLoop

loop = BrowserEventLoop()
schedule_task!(loop, TASK_DOM, my_callback)
request_animation_frame!(loop, render_callback)
run_until_idle!(loop)
```

### Network

HTTP/HTTPS networking layer:
- Connection pooling
- Resource caching with LRU eviction
- DNS resolution caching

```julia
using DOPBrowser.Network

ctx = NetworkContext()
response = fetch!(ctx, "https://example.com")
```

### Renderer

GPU rendering pipeline (via RustRenderer):
- Hardware-accelerated GPU rendering via wgpu
- Software fallback using tiny-skia
- PNG export

```julia
using DOPBrowser.RustRenderer

# Create a renderer
renderer = create_renderer(UInt32(800), UInt32(600))

# Add rendering commands
add_rect!(renderer, 10.0f0, 10.0f0, 100.0f0, 50.0f0, 1.0f0, 0.0f0, 0.0f0, 1.0f0)

# Render and export
render!(renderer)
export_png!(renderer, "output.png")
```

Note: The old Julia `Renderer` module has been deprecated. Use `RustRenderer` for production.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                            DOPBrowser                                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────────────────┐ │
│  │  Network    │───→│  HTMLParser │───→│     DOMCSSOM                │ │
│  │  (HTTP/S)   │    │ (Tokenize)  │    │  (NodeTable, Archetypes)    │ │
│  └─────────────┘    └─────────────┘    └─────────────────────────────┘ │
│                            │                        │                    │
│                            ▼                        │                    │
│                     ┌─────────────┐                │                    │
│                     │CSSParserMod │                │                    │
│                     │ (Styles)    │────────────────┘                    │
│                     └─────────────┘                                     │
│                            │                                             │
│                            ▼                                             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────────────────┐ │
│  │  Compiler   │───→│   Layout    │───→│       ContentMM             │ │
│  │ (HTML→IR)   │    │   (Calc)    │    │   (Content-- Runtime)       │ │
│  └─────────────┘    └─────────────┘    └─────────────────────────────┘ │
│                            │                        │                    │
│                            ▼                        │                    │
│  ┌─────────────┐    ┌─────────────┐                │                    │
│  │  EventLoop  │    │  Renderer   │◀───────────────┘                    │
│  │  (Tasks)    │───→│  (GPU/PNG)  │                                     │
│  └─────────────┘    └─────────────┘                                     │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

## Backward Compatibility

The legacy flat module structure is maintained for backward compatibility. All existing code using:

```julia
using DOPBrowser
# StringPool, Tokenizer, DOMTable, etc. still work
```

will continue to work as before. The new modular architecture is available via:

```julia
using DOPBrowser.HTMLParser
using DOPBrowser.CSSParserModule
using DOPBrowser.Layout
using DOPBrowser.DOMCSSOM
using DOPBrowser.Compiler
using DOPBrowser.EventLoop
```

## Design Principles

1. **Separation of Concerns**: Each module has a single, well-defined responsibility
2. **Dependency Management**: Clear dependency graph between modules
3. **Backward Compatibility**: Legacy API remains functional
4. **SIMD-Friendly**: Data structures designed for vectorized operations
5. **Cache Efficiency**: Structure of Arrays layout for CPU cache optimization
6. **Zero-Copy**: String interning and index-based references minimize allocations

## Future Enhancements

- Complete integration of Compiler module with ContentMM
- Enhanced JIT compilation in EventLoop
- WASM compilation target for Compiler
- Improved GPU utilization in Renderer
