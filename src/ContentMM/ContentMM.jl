"""
    ContentMM

Content-- language implementation based on the v6.0 specification.

Content-- is the **target language** for rendering, designed as a mathematically
intuitive, pre-calculated IR that replaces traditional DOM & CSSOM.

## Design Philosophy

### Two Ways to Input Content--

1. **HTML & CSS (Source Language)**: Familiar authoring format, lowered to Content--
2. **Content-- Text Format (Native)**: Human-readable format for direct authoring

HTML & CSS → (Lowering) → Content-- → (Rendering Engine)
Content-- Text → (Parsing) → Content-- → (Rendering Engine)

### Key Invariant
The rendering engine understands ONLY Content--, never HTML/CSS directly.

## Mathematical Model

Content-- uses a mathematically intuitive approach inspired by linear algebra
and coordinate geometry:

### Vector Types (MathOps)
- `Vec2(x, y)` - 2D position/size vector
- `Box4(top, right, bottom, left)` - 4-sided spacing
- `Rect(origin, size)` - Axis-aligned rectangle
- `Transform2D` - 2D affine transformation matrix

### Layout Equations

Position calculation using vector math:
```julia
child.pos = parent.content_origin + Σ(preceding.size) + child.offset
parent.content_origin = parent.pos + parent.inset
```

Content box (where children are placed):
```julia
content_box = bounds - inset
total_size = content_size + inset + offset
```

### Mathematical Operators

| Operator | Meaning | Example |
|----------|---------|---------|
| `+` | Vector addition | `Vec2(10,20) + Vec2(5,5) = Vec2(15,25)` |
| `*` | Scalar multiply | `Vec2(10,20) * 2 = Vec2(20,40)` |
| `⊕` | Box merge (max) | Combine constraint boxes |
| `⊗` | Hadamard product | Component-wise multiply |
| `⊙` | Dot product | `Vec2(1,0) ⊙ Vec2(0,1) = 0` |

### Coordinate System
- Origin (0,0) at top-left
- X increases rightward (→), Y increases downward (↓)
- All values in device pixels (Float32)

## Architecture

| Feature | Logic Location | Implementation |
| :--- | :--- | :--- |
| Layout Structure | Compiler (AOT) | Generates specialized `.bin` files |
| Text Shaping | Runtime (JIT) | On-demand compilation/caching of Paragraph content |
| Styling | Compiler (AOT) | Flattens all inheritance chains |
| Interaction | WASM Runtime | Event → State update → Direct binary patching |

## Core Modules

- `MathOps`: Mathematical types (Vec2, Box4, Rect) and operators
- `Primitives`: Layout primitives (Stack, Grid, Scroll, Rect) and text primitives (Paragraph, Span, Link)
- `Properties`: Layout semantics (Direction, Pack, Align, Inset, Offset, Size)
- `Styles`: Declarative style system with inheritance flattening
- `SourceMap`: Bidirectional mapping from HTML/CSS to Content-- for debugging
- `Compiler`: AOT compilation to specialized binary format
- `TextJIT`: JIT text shaping for Paragraph nodes
- `Reactive`: Environment switches, variable injection, event bindings
- `Runtime`: WASM-compatible runtime for dynamic interactions
- `HTMLLowering`: Converts HTML/CSS (source) to Content-- (target)
- `TextParser`: Parses Content-- text format (human-readable)
- `NativeUI`: Native UI library interface with pixel comparison testing
"""
module ContentMM

# Mathematical types and operators (must be loaded first)
include("MathOps.jl")

# Core primitive types and enums
include("Primitives.jl")
include("Properties.jl")
include("Styles.jl")
include("Macros.jl")
include("Environment.jl")
include("SourceMap.jl")
include("Compiler.jl")
include("TextJIT.jl")
include("Reactive.jl")
include("Runtime.jl")
include("HTMLLowering.jl")

# Text format parser (human-readable Content-- syntax)
include("TextParser.jl")

# Native UI library interface
include("NativeUI.jl")

# Re-export core types
using .MathOps
using .Primitives
using .Properties
using .Styles
using .Macros
using .Environment
using .SourceMap
using .Compiler
using .TextJIT
using .Reactive
using .Runtime
using .HTMLLowering
using .TextParser
using .NativeUI

export Primitives, Properties, Styles, Macros, Environment, SourceMap, Compiler, TextJIT, Reactive, Runtime, HTMLLowering
export TextParser, NativeUI, MathOps

end # module ContentMM
