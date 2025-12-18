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
- **Onscreen Rendering**: Native desktop windows using Rust backend with winit (requires display server)
- **Headless Mode**: Automatic fallback for CI/testing environments without display servers

### Quick Start (Onscreen Application)

**Note**: Onscreen rendering requires a display server (X11/Wayland on Linux, native on macOS/Windows).
In headless environments (e.g., CI systems), the application will automatically switch to headless mode.

```julia
using DOPBrowser.Application
using DOPBrowser.Widgets
using DOPBrowser.State

# Create reactive state
count = signal(0)

# Create application with Rust backend
# Automatically detects headless environment
app = create_app(title="Counter App", width=400, height=200, backend=:rust)

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

# Run application (opens a desktop window if display is available)
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

| Module | Purpose | Status |
|--------|---------|--------|
| **Pipeline** | Simplified FP-style pipeline (parse_doc → layout → render → to_png) | Active |
| **RustParser** | Rust-based HTML/CSS parser using html5ever and cssparser | **Required** |
| **RustRenderer** | Rust-based GPU renderer via wgpu | **Required** |
| **Layout** | SIMD-friendly layout calculation | Active |
| **DOMCSSOM** | Virtual DOM/CSSOM representation | Active |
| **Compiler** | HTML+CSS to Content-- compilation | Active |
| **ContentMM** | Content IR and runtime | Active |
| **Network** | HTTP/HTTPS networking layer | Active |
| **EventLoop** | Browser main event loop | Active |
| **Window** | Platform windowing abstraction | Active |
| **State** | Reactive state management | Active |
| **Widgets** | High-level UI components | Active |
| **Application** | Application lifecycle management | Active |
| **HTMLParser** | HTML tokenization and string interning | **Deprecated** |
| **CSSParserModule** | CSS parsing and style computation | **Deprecated** |
| **Renderer** | GPU rendering and PNG export | **Deprecated** |

See [docs/MODULAR_ARCHITECTURE.md](docs/MODULAR_ARCHITECTURE.md) for detailed information about the module structure.

### Rust Implementation (Required)

**DOPBrowser now requires Rust libraries to be built and available.**

The Rust-based implementations are mandatory for production use:
- **RustParser**: Uses html5ever and cssparser crates for standards-compliant parsing
- **RustRenderer**: Uses winit/wgpu for GPU-accelerated rendering

To build the Rust libraries:
```bash
cd rust/dop-parser && cargo build --release
cd ../dop-renderer && cargo build --release
```

The Julia implementations (HTMLParser, CSSParserModule, Renderer) are **deprecated** and maintained only for backward compatibility. They will be removed in a future version.

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

Content-- uses a **math-first** approach inspired by linear algebra, leveraging mature Julia libraries for high performance:

**Performance-Optimized Types:**

| Type | Implementation | Description | Example |
| :--- | :--- | :--- | :--- |
| `Vec2` | `StaticArrays.SVector{2,T}` | 2D position/size vector | `Vec2(100.0, 50.0)` |
| `Box4` | `StaticArrays.SVector{4,T}` | 4-sided spacing (top, right, bottom, left) | `Box4(10.0)` |
| `Rect` | Custom struct | Rectangle (origin + size) | `Rect(pos, size)` |
| `Transform2D` | Affine matrix | 2D affine transformation | `translate(10, 20)` |

**Mathematical Operators (Unicode Support):**

| Operator | Unicode | ASCII | Meaning | Library |
| :--- | :--- | :--- | :--- | :--- |
| `⊕` | `\oplus` | `box_merge` | Maximum of each box side | Custom |
| `⊗` | `\otimes` | `hadamard` | Component-wise multiply (Hadamard product) | Custom |
| `⊙` | `\odot` | `dot_product` | Dot product of vectors | `LinearAlgebra` |
| `norm()` | N/A | `norm` | Vector magnitude/length | `LinearAlgebra` |

**Key Benefits:**
- **StaticArrays.jl**: Immutable, stack-allocated vectors for zero-cost abstractions
- **LinearAlgebra**: Standard library for mathematical operations (norm, dot, normalize)
- **Type Stability**: All operations preserve type information for maximum performance
- **SIMD-Ready**: StaticArrays enables automatic vectorization

**Layout Equations (Vector Form):**

```julia
using DOPBrowser.ContentMM.MathOps
using LinearAlgebra

# Child position calculation with Unicode operators
v₁ = Vec2(10.0f0, 20.0f0)
v₂ = Vec2(5.0f0, 10.0f0)
result = v₁ ⊙ v₂  # Dot product: 200.0

# Vector magnitude using LinearAlgebra
‖v₁‖ = norm(v₁)  # 22.36...

# Box merge for constraint composition
b₁ = Box4(10.0f0, 20.0f0, 30.0f0, 40.0f0)
b₂ = Box4(15.0f0)
merged = b₁ ⊕ b₂  # Box4(15.0, 20.0, 30.0, 40.0)

# Traditional ASCII notation still supported
child.pos = parent.content_origin + Σ(preceding.size) + child.offset
content_origin = pos + inset.start
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
2. **Content Text Format**: Human-readable native format for direct authoring

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

## Content IR Modules

### ContentMM.MathOps
**High-performance mathematical types and operators for layout computation.**

Built on mature Julia libraries:
- **StaticArrays.jl**: Immutable, stack-allocated vectors (Vec2, Box4) for zero-cost abstractions
- **LinearAlgebra**: Standard mathematical operations (norm, dot, normalize)
- **Unicode operators**: Expressive notation (⊕, ⊗, ⊙) for mathematical clarity

Provides types: `Vec2`, `Box4`, `Rect`, `Transform2D`

Key features:
- SIMD-ready operations through StaticArrays
- Type-stable for maximum performance
- Full Unicode operator support for mathematical expressiveness
- Backward compatible with ASCII function names

📖 **See [docs/MATH_REFACTORING.md](docs/MATH_REFACTORING.md) for detailed migration guide and performance benefits.**

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
Parser for human-readable Content Text Format. Converts text syntax to Content IR primitives.

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

### RustRenderer (GPU & Software Rendering)
The rendering pipeline is now implemented in Rust for optimal performance:
- Hardware-accelerated GPU rendering via wgpu
- Software fallback rendering using tiny-skia
- Cross-platform window management via winit
- Lossless PNG export
- Text shaping and font rendering

Note: The old Julia `Renderer` module has been deprecated. Use `RustRenderer` for all rendering operations.

## Installation

### Prerequisites

1. **Julia 1.10+**: The minimum required Julia version
2. **Rust toolchain**: Required to build the native libraries

### Build Steps

First, build the required Rust libraries:

```bash
# Build the parser library
cd rust/dop-parser && cargo build --release

# Build the renderer library  
cd ../dop-renderer && cargo build --release
```

Then install the Julia package:

```julia
using Pkg
Pkg.add(path="path/to/dop-browser")
```

Or for development:

```julia
using Pkg
Pkg.develop(path="path/to/dop-browser")
```

### Verify Installation

```julia
using DOPBrowser

# Check that Rust libraries are available
rust = DOPBrowser.Pipeline.rust_available()
println("Parser available: ", rust.parser)
println("Renderer available: ", rust.renderer)
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
│   │   Network   │───→│    Parse    │───→│    Content IR     │   │
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