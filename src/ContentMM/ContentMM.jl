"""
    ContentMM

Content-- language implementation based on the v6.0 specification.

Content-- is the **target language** for rendering, designed as a mathematically
intuitive, pre-calculated IR that replaces traditional DOM & CSSOM.

## Design Philosophy

HTML & CSS → (Lowering) → Content-- → (Rendering Engine)

1. **Source Language**: HTML & CSS (familiar authoring format)
2. **Target Language**: Content-- (rendering engine's only input)
3. **Key Invariant**: Rendering engine understands ONLY Content--, never HTML/CSS

## Mathematical Model

Content-- uses a simple coordinate system:
- Origin (0,0) at top-left
- X increases rightward, Y increases downward
- All values in device pixels (Float32)

### Layout Computation (Pre-calculated)

For node N with parent P:
    N.x = P.content_x + N.offset_left + Σ(sibling.total_width)
    N.y = P.content_y + N.offset_top + Σ(sibling.total_height)

Where content box:
    P.content_x = P.x + P.inset_left
    P.content_y = P.y + P.inset_top

## Architecture

| Feature | Logic Location | Implementation |
| :--- | :--- | :--- |
| Layout Structure | Compiler (AOT) | Generates specialized `.bin` files |
| Text Shaping | Runtime (JIT) | On-demand compilation/caching of Paragraph content |
| Styling | Compiler (AOT) | Flattens all inheritance chains |
| Interaction | WASM Runtime | Event → State update → Direct binary patching |

## Core Modules

- `Primitives`: Layout primitives (Stack, Grid, Scroll, Rect) and text primitives (Paragraph, Span, Link)
- `Properties`: Layout semantics (Direction, Pack, Align, Inset, Offset, Size)
- `Styles`: Declarative style system with inheritance flattening
- `SourceMap`: Bidirectional mapping from HTML/CSS to Content-- for debugging
- `Compiler`: AOT compilation to specialized binary format
- `TextJIT`: JIT text shaping for Paragraph nodes
- `Reactive`: Environment switches, variable injection, event bindings
- `Runtime`: WASM-compatible runtime for dynamic interactions
- `HTMLLowering`: Converts HTML/CSS (source) to Content-- (target)
"""
module ContentMM

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

# Re-export core types
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

export Primitives, Properties, Styles, Macros, Environment, SourceMap, Compiler, TextJIT, Reactive, Runtime, HTMLLowering

end # module ContentMM
