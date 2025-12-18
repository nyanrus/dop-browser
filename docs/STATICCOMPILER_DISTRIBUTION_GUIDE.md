# StaticCompiler Distribution Guide

This guide outlines strategies for making `src/**/*.jl` files usable in StaticCompiler and distributing Content IR-based native UI applications under 10MB (ideally 1-5MB).

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Making src/**/*.jl StaticCompiler-Usable](#making-srcjl-staticcompiler-usable)
3. [Sub-10MB Distribution Strategies](#sub-10mb-distribution-strategies)
4. [Julia Mathematical Aesthetics with Rust](#julia-mathematical-aesthetics-with-rust)
5. [Architecture Patterns](#architecture-patterns)
6. [Implementation Roadmap](#implementation-roadmap)

---

## Executive Summary

### Goals

| Goal | Target | Current Status |
|------|--------|----------------|
| StaticCompiler-usable Julia files | All `src/**/*.jl` | Partial (MathOps, Properties enums) |
| Binary size (memo app) | 1-5 MB | ~5-20 MB (StaticCompiler) |
| Mathematical expressiveness | Full Julia aesthetic | ✅ Achieved (Vec2, Box4, Unicode ops) |
| Rust integration | Seamless FFI | ✅ Achieved |

### Key Insight

The optimal architecture separates:
- **Julia**: Mathematical layout computation, type definitions, algorithm expression
- **Rust**: System operations (windowing, rendering, file I/O), memory management

---

## Making src/**/*.jl StaticCompiler-Usable

### Current Compatibility Matrix

| Module | StaticCompiler Status | Notes |
|--------|----------------------|-------|
| `ContentIR/MathOps.jl` | ✅ Compatible | StaticArrays-based, no GC |
| `ContentIR/Properties.jl` | ⚠️ Partial | Enums/structs OK, PropertyTable uses Vector |
| `ContentIR/Primitives.jl` | ⚠️ Partial | NodeType enum OK, NodeTable uses Vector |
| `StaticMemoMain.jl` | ✅ Compatible | Reference implementation |
| Other modules | ❌ Not compatible | Use dynamic structures |

### Strategy 1: Layered Module Design

Create StaticCompiler-compatible "core" versions of modules:

```
src/
├── ContentIR/
│   ├── MathOps.jl           # Already compatible ✅
│   ├── Properties.jl         # Enums/structs compatible, PropertyTable not
│   ├── Primitives.jl         # Enums/structs compatible, NodeTable not
│   └── StaticCore.jl         # NEW: Pure static types for StaticCompiler
├── StaticMemoMain.jl         # Entry point using StaticCore
└── ...
```

#### Proposed `StaticCore.jl`

```julia
"""
    StaticCore

StaticCompiler-compatible core types extracted from ContentIR.
Uses only stack-allocated, fixed-size types.

Design principle: Mathematical elegance for layout computation
without dynamic memory allocation.
"""
module StaticCore

using StaticArrays
using LinearAlgebra

# Re-export MathOps (already compatible)
using ..MathOps
export Vec2, Box4, Rect, Transform2D
export vec2, box4, rect, lerp, clamp01
export ⊕, ⊗, ⊙  # Unicode operators

# Property enums (already StaticCompiler-compatible)
export Direction, Pack, Align
export DIRECTION_DOWN, DIRECTION_UP, DIRECTION_RIGHT, DIRECTION_LEFT
export PACK_START, PACK_END, PACK_CENTER
export ALIGN_START, ALIGN_END, ALIGN_CENTER, ALIGN_STRETCH

# Color as fixed-size struct
export Color, color_to_rgba

# Fixed-size node representation for StaticCompiler
"""
    StaticNode{N}

Fixed-size node array for StaticCompiler contexts.
N is the maximum number of children (compile-time constant).
"""
struct StaticNode{N}
    node_type::UInt8
    parent::UInt32
    children::SVector{N, UInt32}
    child_count::UInt8
    # Layout cache (pre-computed positions)
    position::Vec2{Float32}
    size::Vec2{Float32}
end

"""
    LayoutResult

Immutable layout result for a single node.
Stack-allocated for zero-cost abstraction.
"""
struct LayoutResult
    position::Vec2{Float32}
    size::Vec2{Float32}
    content_origin::Vec2{Float32}
end

end # module StaticCore
```

### Strategy 2: Compile-Time Node Limits

For StaticCompiler, use compile-time known sizes:

```julia
# Maximum nodes for static compilation (tune based on use case)
const MAX_STATIC_NODES = 64
const MAX_CHILDREN_PER_NODE = 8

# Stack-allocated node array using StaticArrays
struct StaticNodeTable
    nodes::MVector{MAX_STATIC_NODES, StaticNode{MAX_CHILDREN_PER_NODE}}
    count::Int32
end
```

### Strategy 3: Rust-Side Dynamic Structures

Delegate dynamic data structures to Rust and expose via FFI:

```julia
# Julia side (StaticCompiler-compatible)
function create_ui_tree()::Ptr{Cvoid}
    # Rust allocates and manages the tree
    ccall((:content_tree_new, LIBCONTENT), Ptr{Cvoid}, ())
end

function add_node!(tree::Ptr{Cvoid}, node_type::UInt8, parent::UInt32)::UInt32
    ccall((:content_tree_add_node, LIBCONTENT), UInt32, 
          (Ptr{Cvoid}, UInt8, UInt32), tree, node_type, parent)
end
```

```rust
// Rust side (dop-content-ir/src/ffi.rs)
#[no_mangle]
pub extern "C" fn content_tree_new() -> *mut ContentTree {
    Box::into_raw(Box::new(ContentTree::new()))
}

#[no_mangle]
pub extern "C" fn content_tree_add_node(
    tree: *mut ContentTree,
    node_type: u8,
    parent: u32
) -> u32 {
    unsafe { (*tree).add_node(node_type.into(), parent) }
}
```

---

## Sub-10MB Distribution Strategies

### Current State Analysis

| Component | Size | Notes |
|-----------|------|-------|
| StaticCompiler binary | 5-20 MB | Includes LLVM-generated code |
| Rust renderer (libdop_renderer) | ~11 MB | winit + wgpu + fonts |
| Rust parser (libdop_parser) | ~3 MB | html5ever + cssparser |
| Rust content-ir (libdop_content_ir) | ~0.4 MB | Minimal dependencies |
| **Total current** | ~15-35 MB | With all components |

### Target: 1-5 MB Distribution

#### Tier 1: Minimal UI (1-2 MB target)

**Components:**
- StaticCompiler binary: ~1-3 MB (optimized)
- Rust software renderer: ~0.5-1 MB (tiny-skia only)
- Bundled font: ~0.2-0.5 MB (single weight)

**Optimizations:**

```toml
# rust/dop-renderer/Cargo.toml
[profile.release]
opt-level = "z"      # Optimize for size (not "s" for balanced)
lto = "fat"          # Full link-time optimization
codegen-units = 1    # Better optimization
panic = "abort"      # No unwinding
strip = "symbols"    # Strip debug symbols

[features]
default = []         # No features by default
minimal = ["tiny-skia"]  # Only software rendering
```

**Font optimization:**
```bash
# Subset font to only needed glyphs
pyftsubset NotoSans-Regular.ttf \
    --text="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+-*/= .,:;!?@#$%&()" \
    --output-file=subset.ttf
# Result: ~50KB instead of ~500KB
```

#### Tier 2: Standard UI (3-5 MB target)

**Components:**
- StaticCompiler binary: ~2-4 MB
- Rust renderer (software mode): ~1-2 MB
- Font subset: ~0.3 MB

**Build command:**
```bash
# Build Rust with size optimization
cd rust/dop-renderer
RUSTFLAGS="-C link-arg=-s" cargo build --release \
    --features minimal \
    --no-default-features

# Strip the result
strip -s target/release/libdop_renderer.so
```

#### Tier 3: Full-Featured UI (5-10 MB target)

**Components:**
- Full StaticCompiler binary: ~3-5 MB
- Rust renderer (GPU + software): ~3-5 MB
- Multiple fonts: ~1-2 MB

### Size Reduction Techniques

#### 1. Aggressive LTO (Link-Time Optimization)

```julia
# In static_compile_memo_app.jl
compile_executable(
    c_main,
    (Int32, Ptr{Ptr{UInt8}}),
    output_path;
    # Use aggressive optimization flags
    cflags = ["-Os", "-flto", "-ffunction-sections", "-fdata-sections"],
    lflags = ["-Wl,--gc-sections", "-flto"]
)
```

#### 2. Remove Unused Code (Dead Code Elimination)

```rust
// Cargo.toml - Feature flags for conditional compilation
[features]
default = ["software"]
software = ["dep:tiny-skia", "dep:softbuffer"]
gpu = ["dep:wgpu"]
text = ["dep:fontdue"]  # Make text optional

# For minimal build:
# cargo build --release --no-default-features --features software
```

#### 3. Compressed Distribution

```bash
# UPX compression (40-60% reduction)
upx --best --lzma static_memo_app

# Or use zstd for better decompression speed
zstd -19 static_memo_app -o static_memo_app.zst
```

#### 4. Single-Binary Bundling

Bundle Rust libraries into the executable:

```julia
# Modified static compilation approach
# Link Rust libraries statically instead of dynamically

# In build configuration:
const LINK_STATIC = true

if LINK_STATIC
    # Use .a (static library) instead of .so
    const LIBRENDERER = "libdop_renderer.a"
    # Add to linker flags
    push!(lflags, "-L$(RUST_LIB_PATH)", "-ldop_renderer")
end
```

### Realistic Size Estimates

| Configuration | Estimated Size | Features |
|--------------|----------------|----------|
| Ultra-minimal | 1.5-2.5 MB | Basic shapes, embedded font, software render |
| Minimal | 2.5-4 MB | Text rendering, basic UI, software render |
| Standard | 4-6 MB | Full UI toolkit, software render |
| Full (GPU) | 8-12 MB | GPU acceleration, multiple fonts |

---

## Julia Mathematical Aesthetics with Rust

### Design Philosophy

Julia excels at expressing mathematical concepts clearly. The Content-- layout system leverages this:

```julia
# Natural mathematical expression for layout
child_pos = parent.content_origin + flow_direction * accumulated_size + child.offset

# Using Unicode operators for clarity
v₁ ⊙ v₂  # Dot product
b₁ ⊕ b₂  # Box merge (max of each side)
v₁ ⊗ v₂  # Hadamard (element-wise) product
‖v‖      # Norm (magnitude)
```

### Mathematical Types (StaticArrays-backed)

```julia
# Vec2: 2D position/size vector
pos = Vec2(100.0f0, 200.0f0)
size = Vec2(50.0f0, 30.0f0)
end_pos = pos + size  # Natural addition

# Box4: 4-sided values (padding, margin, border)
inset = Box4(10.0f0)                        # All sides equal
inset = Box4(10.0f0, 20.0f0)                # Vertical, Horizontal
inset = Box4(10.0f0, 20.0f0, 30.0f0, 40.0f0)  # T, R, B, L

# Rect: Rectangle with origin and size
bounds = Rect(pos, size)
content_box = inset_rect(bounds, inset)  # Mathematical operation
```

### Layout Equations

Content-- layout follows clear mathematical rules:

```julia
# Child positioning equation
child.position = parent.content_origin + Σ(preceding.size × flow_direction) + child.offset

# Content origin computation
content_origin = bounds.origin + inset.start_offset

# Size constraint resolution
effective_size = clamp(intrinsic_size, min_size, max_size)
```

### Rust Integration Pattern

Rust handles what Julia shouldn't:

| Julia Responsibility | Rust Responsibility |
|---------------------|---------------------|
| Layout algorithm expression | Memory allocation |
| Mathematical operations | System I/O |
| Type definitions | Window management |
| Property computation | GPU rendering |
| Tree traversal logic | Event loop |

#### FFI Bridge Design

```julia
# Julia: Express the algorithm mathematically
function compute_layout!(nodes::Ptr{Cvoid}, viewport::Vec2)::Int32
    # Call Rust to get node count
    count = ccall((:get_node_count, LIBCONTENT), Int32, (Ptr{Cvoid},), nodes)
    
    # For each node, compute layout using Julia math
    for i in 1:count
        # Get node data via FFI
        parent_pos = get_node_position(nodes, i)
        parent_size = get_node_size(nodes, i)
        
        # Julia mathematical computation
        content_origin = parent_pos + get_inset_start(nodes, i)
        
        # Set computed values via FFI
        set_node_content_origin(nodes, i, content_origin)
    end
    
    Int32(0)
end
```

```rust
// Rust: Manage memory and provide data access
#[no_mangle]
pub extern "C" fn get_node_position(tree: *const ContentTree, id: u32) -> Vec2 {
    unsafe { (*tree).get_position(id) }
}

#[no_mangle]
pub extern "C" fn set_node_content_origin(tree: *mut ContentTree, id: u32, origin: Vec2) {
    unsafe { (*tree).set_content_origin(id, origin); }
}
```

---

## Architecture Patterns

### Pattern 1: Static Entry Point with Rust Backend

The recommended pattern for StaticCompiler applications:

```
┌─────────────────────────────────────────────────────────────────┐
│                 StaticCompiler Entry Point                       │
│  (Julia: c_main, type-stable, no GC allocations)                │
└────────────────────────┬────────────────────────────────────────┘
                         │ FFI calls
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Rust Backend                                │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐ │
│  │ Content IR  │  │  Renderer   │  │    Window Manager       │ │
│  │  Builder    │  │ (Software/  │  │    (winit + events)     │ │
│  │             │  │   GPU)      │  │                         │ │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### Pattern 2: Mathematical Computation Layer

For layout-heavy applications:

```
┌─────────────────────────────────────────────────────────────────┐
│              Julia Mathematical Layer                            │
│  (Vec2, Box4, Rect, layout algorithms)                          │
│  - Fully type-stable                                             │
│  - Uses StaticArrays                                             │
│  - No runtime allocation                                         │
└────────────────────────┬────────────────────────────────────────┘
                         │ FFI for data exchange
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│              Rust Data Management Layer                          │
│  - Dynamic node trees                                            │
│  - String interning                                              │
│  - Property tables                                               │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│              Rust Rendering Layer                                │
│  - GPU/Software rendering                                        │
│  - Text shaping                                                  │
│  - Image handling                                                │
└─────────────────────────────────────────────────────────────────┘
```

### Pattern 3: Hybrid Static/Dynamic

For maximum flexibility:

```julia
# Static part (StaticCompiler-compatible)
module StaticUI
    using StaticArrays
    
    # Pure math operations - no allocations
    @inline function layout_child(parent::Rect, child_size::Vec2, 
                                  direction::UInt8, offset::Vec2)::Vec2
        origin = parent.origin + Vec2(parent.inset_left, parent.inset_top)
        return origin + offset
    end
end

# Dynamic part (regular Julia)
module DynamicUI
    using ..StaticUI
    using ..ContentIR
    
    # Dynamic tree building
    function build_tree(spec::String)::NodeTable
        # Uses dynamic allocation
        table = NodeTable()
        parse_spec!(table, spec)
        return table
    end
end
```

---

## Implementation Roadmap

### Phase 1: Core Static Types (Completed ✅)

- [x] `MathOps.jl` with StaticArrays-based Vec2, Box4, Rect
- [x] Unicode operators (⊕, ⊗, ⊙)
- [x] `StaticMemoMain.jl` reference implementation
- [x] Rust FFI integration

### Phase 2: Static Core Module (Recommended)

- [ ] Create `ContentIR/StaticCore.jl`
- [ ] Extract StaticCompiler-compatible subset of Properties
- [ ] Fixed-size node representation for static contexts
- [ ] Documentation for static vs. dynamic usage

### Phase 3: Size Optimization

- [ ] Create minimal Rust renderer build profile
- [ ] Implement font subsetting
- [ ] Add UPX/compression to build pipeline
- [ ] Benchmark and document size reductions

### Phase 4: Enhanced FFI

- [ ] Expand Rust Content IR FFI for layout computation
- [ ] Add batch operations for efficient data transfer
- [ ] Implement layout computation in Julia calling Rust data

### Phase 5: Distribution Packaging

- [ ] Single-binary bundling (static linking)
- [ ] Platform-specific optimizations
- [ ] Automated CI builds with size reporting

---

## References

- [StaticCompiler.jl Documentation](https://github.com/tshort/StaticCompiler.jl)
- [StaticArrays.jl](https://github.com/JuliaArrays/StaticArrays.jl)
- [docs/STATICCOMPILER_READINESS.md](./STATICCOMPILER_READINESS.md)
- [docs/BINARY_SIZE_REDUCTION.md](./BINARY_SIZE_REDUCTION.md)
- [src/StaticMemoMain.jl](../src/StaticMemoMain.jl) - Reference implementation

---

## Summary

Achieving sub-10MB Content IR-based native UI distribution requires:

1. **Julia side**: Use StaticArrays-based types, avoid GC allocations
2. **Rust side**: Handle dynamic structures, provide thin FFI layer
3. **Build system**: Aggressive optimization flags, font subsetting, compression
4. **Architecture**: Clear separation between mathematical Julia and system Rust

The mathematical aesthetics of Julia (Vec2 arithmetic, Unicode operators, clear layout equations) are preserved while Rust handles the "messy" system-level details, creating an elegant and efficient hybrid system.
