# DOP Browser

A **Data-Oriented Programming (DOP)** browser engine base implementation in Julia.

This project provides a render-friendly Intermediate Representation (IR) that replaces traditional DOM & CSSOM with cache-efficient, SIMD-friendly data structures.

## Key Design Principles

- **Structure of Arrays (SoA)**: DOM treated as flat arrays, not object trees
- **Zero-Copy Parsing**: Flat token tape with immediate string interning
- **Index-based Nodes**: Use `UInt32` indices instead of pointers
- **Archetype System**: Solve unique style combinations once, memcpy to nodes
- **SIMD-friendly Layout**: Contiguous float arrays for vectorized computation
- **Linear Render Buffer**: Direct WebGPU upload-ready command buffer
- **Cache Maximization**: Batch costly operations for optimal CPU cache usage

## Content-- Language Support

This browser implements the **Content-- v6.0 specification**, a design-first, data-oriented, performance-over-flexibility UI language.

### Hybrid AOT/JIT Model

| Feature | Logic Location | Implementation | Benefit |
| :--- | :--- | :--- | :--- |
| **Layout Structure** | Compiler (AOT) | Generates specialized `.bin` files | Zero runtime branching |
| **Text Shaping** | Runtime (JIT) | On-demand compilation/caching | Correct kerning and ligatures |
| **Styling** | Compiler (AOT) | Flattens all inheritance chains | Zero runtime lookup cost |
| **Interaction** | WASM Runtime | Event → State → Binary patching | Dynamic effects without reflow |

### Layout Primitives

- `Stack`: Universal Flex container (Direction, Pack, Align, Gap)
- `Grid`: 2D Cartesian layout (Cols, Rows)
- `Scroll`: Viewport wrapper for overflow
- `Rect`: Simple color block

### Text Primitives (JIT Targets)

- `Paragraph`: Container for flowing text (triggers JIT shaping)
- `Span/Link`: Inline text units
- `TextCluster`: Internal GPU command (output of JIT)

### Layout Semantics

| Legacy CSS | Content-- | Description |
| :--- | :--- | :--- |
| flex-direction | `Direction` | Vector of flow (Up, Down, Right, Left) |
| justify-content | `Pack` | Distribution along the Direction |
| align-items | `Align` | Alignment perpendicular to Direction |
| padding | `Inset` | Space inside the node |
| margin | `Offset` | Space outside the node |
| width/height | `Size` | Dimensions with range syntax |

## Core Modules

### StringInterner
Zero-copy string interning for efficient memory usage and fast comparisons. Strings are stored once and referenced by `UInt32` IDs.

### TokenTape
Flat token tape for HTML parsing. Generates a linear sequence of tokens that can be processed sequentially, maximizing cache efficiency during DOM construction.

### NodeTable
Structure of Arrays (SoA) DOM representation where nodes are IDs in a table. Uses `UInt32` indices instead of pointers for cache-friendly traversal.

### StyleArchetypes
Archetype-based style system for efficient style computation. Unique combinations of CSS classes are solved once and results are copied to all nodes sharing that archetype.

### LayoutArrays
SIMD-friendly layout computation using contiguous float arrays. Layout data is stored in SoA format, enabling vectorized computation across multiple nodes.

### RenderBuffer
Linear command buffer for direct WebGPU upload. Generates a sequence of render commands that can be uploaded directly to the GPU.

### Core
Central browser context that ties together all modules. Provides a unified API for document processing with batched operations.

## Content-- IR Modules

### ContentMM.Primitives
Content-- node types: Stack, Grid, Scroll, Rect, Paragraph, Span, Link, TextCluster.

### ContentMM.Properties
Layout semantics: Direction, Pack, Align, Size, Inset, Offset, Gap, Color.

### ContentMM.Styles
Style system with AOT inheritance flattening. All inheritance resolved at compile time.

### ContentMM.Compiler
AOT compiler generating specialized binary files per environment.

### ContentMM.TextJIT
JIT text shaping for Paragraph nodes with caching.

### ContentMM.Reactive
Event bindings, variable injection (var()), and environment switches.

### ContentMM.Runtime
WASM-compatible runtime with sticky positioning resolver and virtual JS interface.

## Network Layer

### Network.NetworkContext
Complete networking layer with:
- HTTP/HTTPS request handling
- Connection pooling
- Resource caching with LRU eviction
- DNS resolution caching

## Rendering Pipeline

### Renderer.GPURenderer
WebGPU-style GPU rendering with:
- Vertex/index buffer management
- Render batch optimization
- Clip/scissor stack management

### Renderer.PNGExport
Lossless PNG export from GPU framebuffer.

## Installation

```julia
using Pkg
Pkg.add(path="path/to/dop-browser")
```

## Usage

### Low-Level API

```julia
using DOPBrowser

# Create a browser context
ctx = create_context(viewport_width=1920.0f0, viewport_height=1080.0f0)

# Process an HTML document
html = """
<!DOCTYPE html>
<html>
<head><title>Example</title></head>
<body>
    <div id="main">
        <h1>Hello World</h1>
        <p>This is a test.</p>
    </div>
</body>
</html>
"""

result = process_document!(ctx, html)

println("Nodes: $(result.node_count)")
println("Archetypes: $(result.archetype_count)")
println("Render commands: $(result.command_count)")
```

### Complete Browser API

```julia
using DOPBrowser

# Create a browser instance
browser = Browser(width=UInt32(1920), height=UInt32(1080))

# Load and render HTML
load_html!(browser, """
<div style="width: 200px; height: 200px; background-color: red;">
    <p>Hello World</p>
</div>
""")

# Render to PNG
render_to_png!(browser, "output.png")

# Or get PNG data as bytes
png_data = get_png_data(browser)

# Use virtual JS interface
left = js_eval(browser, UInt32(1), :offsetLeft)
rect = js_call(browser, UInt32(1), :getBoundingClientRect, Any[])

# Scroll the viewport
scroll_to!(browser, 0.0f0, 100.0f0)
```

## Testing

```julia
using Pkg
Pkg.test("DOPBrowser")
```

## Architecture

### Core Pipeline
```
┌─────────────────────────────────────────────────────────────────┐
│                        BrowserContext                            │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │ StringPool   │  │  Tokenizer   │  │   DOMTable   │          │
│  │ (interning)  │──│ (flat tape)  │──│    (SoA)     │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
│         │                                    │                   │
│         ▼                                    ▼                   │
│  ┌──────────────┐                    ┌──────────────┐          │
│  │ArchetypeTable│────────────────────│  LayoutData  │          │
│  │(style cache) │                    │(float arrays)│          │
│  └──────────────┘                    └──────────────┘          │
│                                              │                   │
│                                              ▼                   │
│                                      ┌──────────────┐          │
│                                      │CommandBuffer │          │
│                                      │(GPU upload)  │          │
│                                      └──────────────┘          │
└─────────────────────────────────────────────────────────────────┘
```

### Complete Browser Pipeline
```
┌────────────────────────────────────────────────────────────────────┐
│                          Browser                                    │
├────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   ┌─────────────┐    ┌─────────────┐    ┌─────────────────────┐   │
│   │   Network   │───→│    Parse    │───→│    Content-- IR     │   │
│   │  (HTTP/S)   │    │   (HTML)    │    │  (Primitives/Props) │   │
│   └─────────────┘    └─────────────┘    └─────────────────────┘   │
│                                                  │                  │
│                                                  ▼                  │
│   ┌─────────────┐    ┌─────────────┐    ┌─────────────────────┐   │
│   │   PNG Out   │←───│ GPURenderer │←───│   Runtime Layout    │   │
│   │             │    │  (WebGPU)   │    │ (Sticky/Flex/Grid)  │   │
│   └─────────────┘    └─────────────┘    └─────────────────────┘   │
│         ▲                                        │                  │
│         │                                        ▼                  │
│         │                                ┌───────────────┐         │
│         └────────────────────────────────│  JS Interface │         │
│                                          │ (Virtual DOM) │         │
│                                          └───────────────┘         │
└────────────────────────────────────────────────────────────────────┘
```

## Content-- Design Constraints

By design, Content-- sacrifices the following for performance:

1. **No Inline Box Flow**: Cannot place interactive Stack inside flowing Paragraph
2. **No Contextual Selectors**: Cannot style based on arbitrary parent/sibling context
3. **No Text Floats**: Cannot wrap text around non-rectangular shapes
4. **Limited Global Text Selection**: Selection is difficult across different Paragraph nodes

## Performance Considerations

1. **Cache Efficiency**: All data structures use contiguous memory layouts
2. **SIMD Ready**: Float arrays are laid out for automatic vectorization
3. **Minimal Allocations**: String interning and index-based references reduce GC pressure
4. **Batch Processing**: Operations are designed for bulk updates
5. **Zero Runtime Style Lookup**: All inheritance flattened at AOT compile time
6. **JIT Text Caching**: Paragraph shapes cached by (text_hash, max_width)

## License

MIT