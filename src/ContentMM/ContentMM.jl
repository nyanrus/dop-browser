"""
    ContentMM

Content-- language implementation based on the v6.0 specification.

The Content-- language is a **Design-First, Data-Oriented, Performance-Over-Flexibility** 
UI language that replaces traditional DOM & CSSOM with a hybrid AOT/JIT model.

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
- `Compiler`: AOT compilation to specialized binary format
- `TextJIT`: JIT text shaping for Paragraph nodes
- `Reactive`: Environment switches, variable injection, event bindings
- `Runtime`: WASM-compatible runtime for dynamic interactions
"""
module ContentMM

# Core primitive types and enums
include("Primitives.jl")
include("Properties.jl")
include("Styles.jl")
include("Macros.jl")
include("Environment.jl")
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
using .Compiler
using .TextJIT
using .Reactive
using .Runtime
using .HTMLLowering

export Primitives, Properties, Styles, Macros, Environment, Compiler, TextJIT, Reactive, Runtime, HTMLLowering

end # module ContentMM
