# Binary Size Reduction Strategies

This document outlines strategies to reduce the size of the compiled memo application binary.

## Current Size Estimates

With JuliaC and code trimming enabled, the compiled application size is significantly reduced compared to older PackageCompiler approaches.

### JuliaC with Trimming
- **Code trimming** (`--trim=safe`) removes unreachable code and unused IR
- Bundled Julia runtime and libraries
- Executable plus bundled libraries
- Total size varies based on trimming effectiveness

### Rust Libraries (~15 MB)
- **dop-renderer**: 11.74 MB
- **dop-parser**: 2.73 MB
- **dop-content-ir**: 0.41 MB

## Size Reduction Techniques

### 1. Code Trimming (Recommended - Already Enabled)

JuliaC's built-in code trimming is the most effective size reduction technique:

```julia
# In scripts/compile_memo_app.jl
img = ImageRecipe(
    trim_mode = "safe",  # Removes unreachable code
    # ...
)
```

This removes:
- Unreachable code paths
- Unused IR (intermediate representation)
- Unused metadata

**Expected savings**: Significant reduction compared to non-trimmed builds
**Trade-off**: None - "safe" mode is conservative and stable

### 2. Strip Debug Symbols (30-50% reduction)

After compilation, strip debug symbols from the executable and libraries:

```bash
# Strip the main executable
strip build/bin/memo_app

# Strip all shared libraries
find build/lib -name "*.so" -exec strip {} \;
```

**Expected savings**: 30-50% of binary size
**Trade-off**: Loss of debug information

### 3. Compress with UPX

Use UPX (Ultimate Packer for eXecutables) to compress the binary:

```bash
# Install UPX
sudo apt-get install upx

# Compress the executable
upx --best --lzma build/bin/memo_app

# Compress libraries (optional, may affect load time)
find build/lib -name "*.so" -exec upx --best {} \;
```

**Expected savings**: 40-60% compression ratio
**Trade-off**: Slower startup time, higher memory usage during startup

### 4. CPU Target Optimization

By default, JuliaC uses `cpu_target="generic"` for portability. For a specific CPU:

```julia
# In scripts/compile_memo_app.jl
img = ImageRecipe(
    cpu_target = "native",  # Optimize for current CPU
    # ...
)
```

**Expected savings**: Minimal size impact, but better performance
**Trade-off**: Less portable across different CPUs

Build Rust libraries with size optimization:

```bash
# In each Rust crate directory
cd rust/dop-renderer

# Edit Cargo.toml to add optimization profile:
# [profile.release]
# opt-level = "z"      # Optimize for size
# lto = true           # Link-time optimization
# codegen-units = 1    # Better optimization
# strip = true         # Strip symbols

cargo build --release
```

**Expected savings**: 3-5 MB
**Trade-off**: Slightly slower runtime performance

### 7. Remove Unnecessary Dependencies

Review and remove unused dependencies from `Project.toml`:

```bash
# Check dependency tree
julia --project=. -e 'using Pkg; Pkg.status()'

# Remove unused packages
julia --project=. -e 'using Pkg; Pkg.rm("UnusedPackage")'
```

**Expected savings**: Varies by dependencies

### 8. Split Application

For distribution, consider splitting the application:

```
memo_app/
├── bin/memo_app          # Small executable (10-20 MB)
├── lib/                  # Shared libraries (optional download)
│   ├── julia/            # Julia runtime (one-time download)
│   └── rust/             # Rust libraries
└── data/                 # Application data
```

Users can download the Julia runtime separately (shared across applications).

## Recommended Approach

For **maximum size reduction** with JuliaC:

1. **Code trimming** (already enabled): Significant reduction
2. **Strip debug symbols** (easy, safe): Additional 30-50%
3. **Optimize Rust libraries** (easy): -5 MB
4. **Compress with UPX** (optional): Additional 40-60% compression

For **minimal size** (with trade-offs):

Use StaticCompiler instead of JuliaC for ~5-20 MB binaries (see below).

### 8. StaticCompiler (Best Size Reduction)

For the smallest possible binaries, use StaticCompiler instead of JuliaC. This creates a truly standalone executable without the Julia runtime. **Now supports interactive onscreen mode via Rust FFI!**

```bash
# Install StaticCompiler (already in Project.toml)
julia --project=. -e 'using Pkg; Pkg.instantiate()'

# Verify setup
julia --project=. scripts/verify_static_compilation_setup.jl

# Compile with StaticCompiler
julia --project=. scripts/static_compile_memo_app.jl

# Run headless mode
./build/static_memo_app

# Run interactive onscreen mode
./build/static_memo_app --onscreen
```

**Binary size**: ~5-20 MB (vs. larger JuliaC builds)

**Trade-offs**: 
- Limited Julia feature support (but Rust FFI provides rich functionality)
- Requires C-compatible entry points and calling conventions
- No dynamic dispatch or runtime compilation

**Capabilities**:
- ✓ Headless rendering to PNG
- ✓ **Interactive window with mouse/keyboard events via Rust FFI**
- ✓ Real-time rendering loop
- ✓ Full event handling (clicks, resize, close)
- ✓ **Natural Julia code (just type-stable and allocation-aware)**

**When to use**:
- Minimal binary size is critical
- **Interactive applications with Rust backend support**
- Embedded systems or containers
- Fast startup time required  
- Batch processing and rendering

**How it works**:
StaticCompiler compiles Julia code to native machine code without the Julia runtime. You can write natural Julia code as long as it's type-stable and avoids GC allocations. For system operations like window management, we use C-compatible FFI to call Rust functions directly. This gives us clean Julia code with tiny binaries and full interactivity!

**Key principles**:
- Write type-stable Julia code (checked by the compiler)
- Use stack allocation (StaticArrays, NamedTuples, Tuples)
- Use manual memory management when needed (StaticTools.MallocArray)
- Leverage Rust FFI for system-level operations (windowing, file I/O)
- Use `@device_override` to replace incompatible standard library methods

## Benchmarking

To measure actual size after applying optimizations:

```bash
# Build and report size
julia --project=. scripts/compile_memo_app.jl

# View the size report
cat build/size_report.txt

# Or manually measure
du -sh build/memo_app/
```

## Testing After Optimization

Always test the optimized binary to ensure it still works:

```bash
# Test in headless mode
HEADLESS=1 ./build/memo_app/bin/memo_app --simple

# Test in interactive mode (requires display)
./build/memo_app/bin/memo_app --interactive
```
