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

## Modules

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

## Installation

```julia
using Pkg
Pkg.add(path="path/to/dop-browser")
```

## Usage

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

## Testing

```julia
using Pkg
Pkg.test("DOPBrowser")
```

## Architecture

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

## Performance Considerations

1. **Cache Efficiency**: All data structures use contiguous memory layouts
2. **SIMD Ready**: Float arrays are laid out for automatic vectorization
3. **Minimal Allocations**: String interning and index-based references reduce GC pressure
4. **Batch Processing**: Operations are designed for bulk updates

## License

MIT