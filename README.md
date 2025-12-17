# DOP Browser

A **Data-Oriented Programming (DOP)** browser engine base implementation in Julia.

This project provides a render-friendly Intermediate Representation (IR) that replaces traditional DOM & CSSOM with cache-efficient, SIMD-friendly data structures.

## Simplified Pipeline (FP-Style)

DOPBrowser now includes a **simplified functional programming-style Pipeline** for the Content-- → Rendering → Interaction flow:

```julia
using DOPBrowser.Pipeline

# One-liner: HTML to PNG
html = "<div style='width: 100px; height: 50px; background: red'></div>"
png_data = html |> parse_doc |> layout |> render |> to_png

# Step by step with viewport customization
doc = parse_doc(html)
doc = layout(doc, viewport=(1920, 1080))
buffer = render(doc)
save_png(buffer, "output.png")

# Convenience function
png = render_html("<div style='background: blue; width: 100px; height: 100px'></div>")

# Curried composition with viewport
layout_hd = with_viewport((1920, 1080))
png = html |> parse_doc |> layout_hd |> render |> to_png
```

### Interaction

```julia
using DOPBrowser.Pipeline
using DOPBrowser.ContentMM.MathOps: vec2

# Hit testing
doc = parse_doc("<div style='width: 100px; height: 50px'></div>") |> layout
node_id = hit_test(doc, vec2(50.0f0, 25.0f0))  # Returns 2 (the div)

# Math-style accessors
using DOPBrowser.Pipeline: position, bounds
pos = position(doc, 2)     # Vec2(0, 0)
(p, s) = bounds(doc, 2)    # (Vec2(0,0), Vec2(100, 50))

# Check if Rust implementations are available (for production use)
rust = rust_available()
rust.parser    # true if RustParser is available
rust.renderer  # true if RustRenderer is available
```

## Interactive UI Library

DOPBrowser now includes a **production-ready interactive UI framework** that can be used to build native desktop applications. The framework provides:

- **Reactive State Management**: Signals, computed values, and effects for automatic UI updates
- **Widget Library**: High-level components (Button, TextInput, Checkbox, Slider, etc.)
- **Application Lifecycle**: Full app management with initialization, update loop, and cleanup
- **Window Integration**: Platform-agnostic window abstraction with event handling
- **Onscreen Rendering**: Native desktop windows using Gtk4 backend

### Quick Start (Onscreen Application)

```julia
using DOPBrowser.Application
using DOPBrowser.Widgets
using DOPBrowser.State

# Create reactive state
count = signal(0)

# Create application with Gtk backend for onscreen rendering
app = create_app(title="Counter App", width=400, height=200, backend=:gtk)

# Define UI
set_ui!(app) do
    column(gap=10.0f0) do
        label(text=computed(() -> "Count: \$(count[])"))
        row(gap=5.0f0) do
            button(text="-", on_click=() -> count[] -= 1)
            button(text="+", on_click=() -> count[] += 1)
        end
    end
end

# Run application (opens a desktop window)
run!(app)
```

### Reactive State Management

```julia
using DOPBrowser.State

# Create signals (reactive values)
name = signal("World")
count = signal(0)

# Create computed values (derived state)
greeting = computed(() -> "Hello, \$(name[])! Count: \$(count[])")

# Create effects (side effects)
effect(() -> println(greeting[]))  # Runs on every change

# Update signals
count[] = 1        # Triggers effect automatically
name[] = "Julia"   # Triggers effect automatically

# Batch updates (single notification)
batch(() -> begin
    count[] = 10
    name[] = "Everyone"
end)

# Store pattern for complex state
store = create_store(
    Dict{Symbol,Any}(:todos => [], :filter => :all),
    Dict{Symbol,Function}(
        :add_todo => (state, text) -> Dict(:todos => [state[:todos]..., text])
    )
)
dispatch(store, :add_todo, "Learn Julia")
```

### Available Widgets

| Widget | Description |
|--------|-------------|
| `button` | Clickable button with hover/pressed states |
| `label` | Text display |
| `text_input` | Single-line text entry |
| `checkbox` | Boolean toggle |
| `slider` | Numeric range selection |
| `progress_bar` | Progress indicator |
| `container` | Layout container |
| `row` | Horizontal layout |
| `column` | Vertical layout |
| `spacer` | Flexible spacing |

### Headless Mode

For testing or server-side rendering:

```julia
app = create_app(headless=true, width=800, height=600)
set_ui!(app, my_ui_builder)
render_frame!(app)
save_app_screenshot(app, "output.png")
```

## Modular Architecture

DOPBrowser is organized into well-defined modules for better maintainability:

| Module | Purpose |
|--------|---------|
| **Pipeline** | Simplified FP-style pipeline (parse_doc → layout → render → to_png) |
| **HTMLParser** | HTML tokenization and string interning |
| **CSSParserModule** | CSS parsing and style computation |
| **Layout** | SIMD-friendly layout calculation |
| **DOMCSSOM** | Virtual DOM/CSSOM representation |
| **Compiler** | HTML+CSS to Content-- compilation |
| **ContentMM** | Content-- IR and runtime |
| **Network** | HTTP/HTTPS networking layer |
| **Renderer** | GPU rendering and PNG export |
| **EventLoop** | Browser main event loop |
| **Window** | Platform windowing abstraction |
| **State** | Reactive state management |
| **Widgets** | High-level UI components |
| **Application** | Application lifecycle management |
| **RustParser** | Rust-based HTML/CSS parser (high-performance alternative) |
| **RustRenderer** | Rust-based GPU renderer via wgpu (high-performance alternative) |

See [docs/MODULAR_ARCHITECTURE.md](docs/MODULAR_ARCHITECTURE.md) for detailed information about the module structure.

### Rust vs Julia Implementations

For production use, prefer the Rust-based implementations when available:
- **RustParser**: Uses html5ever and cssparser crates for standards-compliant parsing
- **RustRenderer**: Uses winit/wgpu for GPU-accelerated rendering

The Julia implementations (HTMLParser, CSSParserModule, Renderer) are provided for:
- Rapid prototyping and experimentation
- Environments where Rust libraries are not available
- Educational purposes

## Acid2 Test Support

DOPBrowser now includes **enhanced CSS 2.1 support** for processing the real Acid2 test from webstandards.org. The browser includes:
- Advanced selector matching (attribute selectors, combinators, multiple classes)
- Comprehensive border properties (per-side width, style, color)
- Float and clear properties (parsing complete)
- Min/max width/height constraints
- Extended unit support (px, %, em, mm)

See [docs/ACID2_SUPPORT.md](docs/ACID2_SUPPORT.md) for detailed information about Acid2 compliance.

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

### Mathematical Model

Content-- uses a **math-first** approach inspired by linear algebra. Layout computation uses intuitive vector and box types:

| Type | Description | Example |
| :--- | :--- | :--- |
| `Vec2` | 2D position/size vector | `Vec2(100.0, 50.0)` |
| `Box4` | 4-sided spacing (top, right, bottom, left) | `Box4(10.0)` |
| `Rect` | Rectangle (origin + size) | `Rect(pos, size)` |
| `Transform2D` | 2D affine transformation | `translate(10, 20)` |

**Mathematical Operators:**

| Operator | ASCII | Meaning |
| :--- | :--- | :--- |
| `⊕` | `box_merge` | Maximum of each box side |
| `⊗` | `hadamard` | Component-wise multiply |
| `⊙` | `dot_product` | Dot product of vectors |

**Layout Equations (Vector Form):**

```julia
# Child position calculation
child.pos = parent.content_origin + Σ(preceding.size) + child.offset

# Content origin (where children are placed)
content_origin = pos + inset.start

# Total size including spacing
total_size = size + inset.total + offset.total
```

**Direction as Unit Vector:**

```julia
using DOPBrowser.ContentMM.Properties

# Direction maps to unit vectors for intuitive math
flow_down  = direction_to_vec2(DIRECTION_DOWN)   # Vec2(0, 1)
flow_right = direction_to_vec2(DIRECTION_RIGHT)  # Vec2(1, 0)

# Use in layout calculation
next_pos = current_pos + flow_down * child_height
```

### Input Methods

Content-- supports two input methods:

1. **HTML & CSS**: Traditional web authoring, lowered to Content--
2. **Content-- Text Format**: Human-readable native format for direct authoring

```julia
# Text format example
Stack(Direction: Down, Fill: #FFFFFF) {
    Rect(Size: (200, 100), Fill: #FF0000);
    Paragraph { Span(Text: "Hello World"); }
}
```

### Native UI Library

Use Content-- as a standalone UI library:

```julia
using DOPBrowser.ContentMM.NativeUI

# Create UI from text format
ui = create_ui(\"\"\"
    Stack(Direction: Down, Fill: #FFFFFF) {
        Rect(Size: (100, 50), Fill: #FF0000);
    }
\"\"\")

# Render to PNG
render_to_png!(ui, "output.png", width=800, height=600)

# Pixel comparison testing
result = compare_pixels(ui, "reference.png", width=800, height=600)
@test result.match == true
```

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

### ContentMM.MathOps
Mathematical types and operators for layout computation: Vec2, Box4, Rect, Transform2D. Provides intuitive vector math for layout calculations.

### ContentMM.Primitives
Content-- node types: Stack, Grid, Scroll, Rect, Paragraph, Span, Link, TextCluster.

### ContentMM.Properties
Layout semantics: Direction, Pack, Align, Size, Inset, Offset, Gap, Color. Integrates with MathOps for mathematical conversions.

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

### ContentMM.TextParser
Parser for human-readable Content-- text format. Converts text syntax to Content-- primitives.

### ContentMM.NativeUI
Native UI library interface with programmatic builder API and pixel comparison testing.

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