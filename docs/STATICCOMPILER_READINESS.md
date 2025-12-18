# StaticCompiler Readiness Guide

This document explains the StaticCompiler compatibility status of DOPBrowser source files and provides guidance for future development.

For comprehensive distribution strategies targeting sub-10MB binaries, see [STATICCOMPILER_DISTRIBUTION_GUIDE.md](./STATICCOMPILER_DISTRIBUTION_GUIDE.md).

## Overview

DOPBrowser uses a hybrid approach for StaticCompiler compatibility:
- **Mathematical types** (Vec2, Box4) use `StaticArrays.SVector` ✅
- **Core data structures** use dynamic `Vector` for flexibility ⚠️
- **Entry points** like `StaticMemoMain.jl` are fully StaticCompiler-compatible ✅
- **StaticCore module** provides pure StaticCompiler-compatible types ✅ NEW

## StaticCompiler Limitations

StaticCompiler cannot handle:
- ❌ GC-allocated types: `Vector`, `Array`, `String`, `Dict`
- ❌ Dynamic dispatch
- ❌ Runtime compilation (eval, generated functions)
- ❌ Most standard library functions

StaticCompiler CAN handle:
- ✅ Type-stable code with concrete types
- ✅ Stack-allocated types (structs, primitives)
- ✅ `StaticArrays.SVector`, `MVector`, etc. (fixed size)
- ✅ `StaticTools.MallocArray` (manual memory management)
- ✅ FFI calls to external libraries (C, Rust)

## Module Compatibility Status

### Fully Compatible ✅

**src/ContentIR/StaticCore.jl** (NEW)
- Pure StaticCompiler-compatible module
- Re-exports all safe types from MathOps, Properties, Primitives
- Adds StaticNode, StaticNodeTable for bounded static contexts
- Includes StaticColor, StaticInset for zero-allocation layouts
- See [STATICCOMPILER_DISTRIBUTION_GUIDE.md](./STATICCOMPILER_DISTRIBUTION_GUIDE.md) for usage

**src/StaticMemoMain.jl**
- Pure StaticCompiler-compatible entry point
- Uses only FFI to Rust, stack allocation, and MallocArray
- Demonstrates best practices for StaticCompiler

**src/ContentIR/MathOps.jl** (with limitations)
- Mathematical types (Vec2, Box4, Rect) use StaticArrays ✅
- All functions are type-stable with inline hints ✅
- Can be used in StaticCompiler contexts for math operations

**src/ContentIR/Properties.jl** (with limitations)
- Enum types (Direction, Pack, Align) are compatible ✅
- Simple structs (Color, Size, Inset, Offset) are compatible ✅
- Conversion functions have inline hints for performance ✅
- PropertyTable uses Vector (NOT compatible) ⚠️

### Partially Compatible ⚠️

**src/ContentIR/Primitives.jl**
- ✅ Enum types (NodeType)
- ✅ ContentNode struct
- ❌ NodeTable (uses Vector - requires dynamic sizing)

**src/ContentMM/** (legacy modules)
- Same compatibility status as ContentIR equivalents
- Prefer ContentIR for new code

### Not Compatible ❌

The following modules fundamentally require dynamic data structures:

- **src/DOMCSSOM/** - DOM/CSSOM trees (dynamic)
- **src/HTMLParser/** - Token streams (dynamic)
- **src/Layout/** - Layout arrays (dynamic, SIMD-optimized)
- **src/State/** - Reactive state (uses closures)
- **src/Widgets/** - Widget trees (dynamic)
- **src/Application/** - Application state (dynamic)
- **src/Network/** - HTTP client (dynamic buffers)
- **src/RustRenderer/** - FFI wrappers (can be adapted)
- **src/RustParser/** - FFI wrappers (can be adapted)

## Development Guidelines

### When Writing StaticCompiler-Compatible Code

1. **Use Stack Allocation**
   ```julia
   # Good: Fixed-size stack-allocated
   position = Vec2(10.0f0, 20.0f0)
   bounds = Box4(5.0f0)
   
   # Bad: Heap-allocated
   data = Vector{Float32}(undef, 100)
   ```

2. **Use StaticArrays for Fixed-Size Arrays**
   ```julia
   # Good: Compile-time size
   vertices = SVector{4, Vec2{Float32}}(...)
   
   # Bad: Runtime size
   vertices = Vector{Vec2}(undef, 4)
   ```

3. **Use MallocArray for Dynamic Arrays**
   ```julia
   using StaticTools
   
   # Manual memory management
   events = MallocArray{DopEvent}(undef, 10)
   # ... use events ...
   free(events)  # Must free manually!
   ```

4. **Ensure Type Stability**
   ```julia
   # Good: Return type is known
   function compute_size(w::Float32, h::Float32)::Vec2{Float32}
       Vec2(w, h)
   end
   
   # Bad: Return type depends on runtime value
   function maybe_size(flag::Bool)
       flag ? Vec2(1.0f0, 1.0f0) : nothing
   end
   ```

5. **Add @inline Hints**
   ```julia
   # Hot-path functions should be inlined
   @inline function clamp01(x::Float32)::Float32
       clamp(x, 0.0f0, 1.0f0)
   end
   ```

6. **Use Rust FFI for System Operations**
   ```julia
   # Delegate to Rust for I/O, windowing, etc.
   function render_to_window(handle::WindowHandle)
       # Call Rust via ccall
       ccall((:update_window, LIBRENDERER), Cvoid, (Ptr{Cvoid},), handle)
   end
   ```

### When Using DOPBrowser Modules

**For StaticCompiler projects:**
- ✅ Use `ContentIR.MathOps` for mathematical operations
- ✅ Use `ContentIR.Properties` enum types and simple structs
- ✅ Follow `StaticMemoMain.jl` as a template
- ❌ Do NOT use `NodeTable`, `PropertyTable`, or other dynamic structures

**For regular Julia projects:**
- ✅ Use all modules normally
- ✅ Benefit from SIMD-optimized SoA (Structure of Arrays) design
- ✅ Leverage dynamic data structures for flexibility

## Performance Optimizations

### Inline Hints
We've added `@inline` to hot-path functions:
- Mathematical operations: `lerp`, `clamp01`, `remap`, `smoothstep`
- Box utilities: `horizontal`, `vertical`, `total`
- Rect operations: `contains`, `intersects`, `intersection`
- Layout helpers: `compute_content_box`, `compute_total_size`, `compute_child_position`
- Conversions: `color_to_rgba`, `direction_to_vec2`, `to_vec2`, `to_box4`

### Type Annotations
All public functions have explicit return type annotations for type stability.

### StaticArrays Usage
- `Vec2{T}` uses `SVector{2,T}` internally
- `Box4{T}` uses `SVector{4,T}` internally
- Zero-cost abstractions with SIMD support

## Architecture Patterns

### Pattern 1: Standalone Entry Point (Recommended)
```julia
# Like StaticMemoMain.jl
using StaticCompiler
using StaticTools

# Minimal dependencies, mostly FFI
Base.@ccallable function c_main(argc::Int32, argv::Ptr{Ptr{UInt8}})::Int32
    # Use stack allocation, MallocArray, and Rust FFI
    render_app()  # Calls Rust for actual work
    Int32(0)
end
```

### Pattern 2: Math-Heavy Computation
```julia
# Use ContentIR.MathOps for mathematical operations
using StaticArrays

function compute_layout_positions(count::Int32)::MallocArray{Vec2{Float32}}
    positions = MallocArray{Vec2{Float32}}(undef, count)
    for i in 1:count
        positions[i] = Vec2(Float32(i * 10), Float32(i * 10))
    end
    return positions
end
```

### Pattern 3: FFI-Based Architecture
```julia
# Delegate complex logic to Rust
# Julia handles high-level logic and math
# Rust handles I/O, memory management, system calls

# Julia side
function process_data(data_ptr::Ptr{Float32}, count::Int32)::Int32
    # Type-stable mathematical processing
    ccall((:rust_process, LIBNAME), Cvoid, (Ptr{Float32}, Int32), data_ptr, count)
    Int32(0)
end
```

## Testing StaticCompiler Compatibility

```bash
# Verify setup
julia --project=. scripts/verify_static_compilation_setup.jl

# Compile a StaticCompiler-compatible module
julia --project=. -e 'using StaticCompiler; compile_executable(c_main, (Int32, Ptr{Ptr{UInt8}}), "output")'

# Check binary size
ls -lh output
```

## Migration Strategy

To make existing code more StaticCompiler-ready:

1. **Identify hot paths** - Focus on performance-critical code first
2. **Add type annotations** - Ensure type stability
3. **Add @inline hints** - Help compiler optimize
4. **Extract math operations** - Move to StaticArrays-based functions
5. **Consider FFI** - Delegate system operations to Rust

## References

- [StaticCompiler.jl](https://github.com/tshort/StaticCompiler.jl)
- [StaticTools.jl](https://github.com/brenhinkeller/StaticTools.jl)
- [StaticArrays.jl](https://github.com/JuliaArrays/StaticArrays.jl)
- [docs/STATICCOMPILER_IMPLEMENTATION.md](./STATICCOMPILER_IMPLEMENTATION.md)
- [src/StaticMemoMain.jl](../src/StaticMemoMain.jl) - Reference implementation

## Summary

DOPBrowser takes a pragmatic approach to StaticCompiler compatibility:

**What's compatible:**
- Mathematical types and operations (Vec2, Box4, Rect)
- Type-stable pure functions with inline hints
- Standalone entry points using FFI and manual memory management

**What's not compatible:**
- Dynamic data structures (NodeTable, PropertyTable, etc.)
- Full application framework (State, Widgets, etc.)

**Best practice:**
- Write StaticCompiler entry points as thin wrappers
- Use Rust FFI for system operations and complex logic
- Use DOPBrowser's mathematical types for computation
- Keep main application logic in regular Julia for expressiveness
