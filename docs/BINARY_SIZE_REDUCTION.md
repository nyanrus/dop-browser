# Binary Size Reduction Strategies

This document outlines strategies to reduce the size of the compiled memo application binary.

## Current Size Estimates

Based on PackageCompiler bundling, the compiled application includes:

### Base Julia Libraries (~285 MB)
- **libLLVM.so**: 105.5 MB - LLVM compiler infrastructure
- **libjulia-codegen.so**: 77.4 MB - Julia code generation
- **OpenBLAS**: 34.2 MB - Linear algebra library
- **libstdc++**: 20.4 MB - C++ standard library
- **libjulia-internal.so**: 14.1 MB - Julia internals
- **libgfortran.so**: 9.6 MB - Fortran runtime
- **OpenSSL**: 7.6 MB - Cryptography
- **Other libraries**: ~16 MB

### Application Code (~50-100 MB estimated)
- Julia stdlib modules
- DOPBrowser package and dependencies
- Precompiled functions

### Rust Libraries (~15 MB)
- **dop-renderer**: 11.74 MB
- **dop-parser**: 2.73 MB
- **dop-content-ir**: 0.41 MB

### **Total Estimated Size: 350-400 MB**

## Size Reduction Techniques

### 1. Strip Debug Symbols (30-50% reduction)

After compilation, strip debug symbols from the executable and libraries:

```bash
# Strip the main executable
strip build/memo_app/bin/memo_app

# Strip all shared libraries
find build/memo_app/lib -name "*.so" -exec strip {} \;
```

**Expected savings**: 100-150 MB

### 2. Filter Standard Libraries (Already Enabled)

The compilation script uses `filter_stdlibs=true`, which excludes unused Julia standard library modules.

**Current savings**: ~50 MB (already applied)

### 3. Compress with UPX

Use UPX (Ultimate Packer for eXecutables) to compress the binary:

```bash
# Install UPX
sudo apt-get install upx

# Compress the executable
upx --best --lzma build/memo_app/bin/memo_app

# Compress libraries (optional, may affect load time)
find build/memo_app/lib -name "*.so" -exec upx --best {} \;
```

**Expected savings**: 40-60% compression ratio
**Trade-off**: Slower startup time, higher memory usage during startup

### 4. Remove Unused Julia Features

PackageCompiler allows creating a minimal system image. Modify the compilation script to exclude features:

```julia
create_app(
    PROJECT_DIR,
    joinpath(OUTPUT_DIR, APP_NAME),
    precompile_execution_file=PRECOMPILE_FILE,
    executables=["memo_app" => "julia_main"],
    force=true,
    include_lazy_artifacts=false,  # Don't include unused artifacts (WARNING: may break Rust library loading)
    filter_stdlibs=true,
    cpu_target="native",           # Optimize for local CPU
    sysimage_build_args=`--optimize=3 --check-bounds=no`  # Aggressive optimization
)
```

**Expected savings**: 20-50 MB
**Trade-off**: Less portable, no runtime bounds checking
**Warning**: Setting `include_lazy_artifacts=false` may prevent Rust libraries from loading if they are stored as artifacts. Test thoroughly after applying this option.

### 5. Minimize Precompilation Scope

To reduce compilation time and potentially size, you can modify the precompile execution file to include only the most common code paths. Edit `scripts/precompile_memo_app.jl` to reduce the amount of code being precompiled.

**Expected savings**: 10-30 MB
**Trade-off**: Slower startup for non-precompiled code paths

### 6. Optimize Rust Libraries

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

For **maximum size reduction** while maintaining functionality:

1. **Strip debug symbols** (easy, safe): -100 MB
2. **Use `filter_stdlibs=true`** (already done): -50 MB
3. **Optimize Rust libraries** (easy): -5 MB
4. **Compress with UPX** (optional): Additional 40-60% compression

**Expected final size**: 140-180 MB (compressed) or 200-250 MB (uncompressed)

For **minimal size** (with trade-offs):

1. All the above, plus:
2. **Aggressive Julia optimization flags**: -50 MB
3. **Remove unused stdlib**: -30 MB

**Expected final size**: 60-100 MB (highly optimized, less portable)

### 9. StaticCompiler (Experimental - Best Size Reduction)

For the smallest possible binaries, use StaticCompiler instead of PackageCompiler. This creates a truly standalone executable without the Julia runtime. **Now supports interactive onscreen mode via Rust FFI!**

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

**Expected savings**: -330 MB (from ~350 MB to ~5-20 MB)

**Trade-offs**: 
- Limited Julia feature support (but Rust FFI provides rich functionality)
- Requires C-compatible entry points and calling conventions
- No dynamic dispatch or runtime compilation

**Capabilities**:
- ✓ Headless rendering to PNG
- ✓ **Interactive window with mouse/keyboard events via Rust FFI**
- ✓ Real-time rendering loop
- ✓ Full event handling (clicks, resize, close)

**When to use**:
- Minimal binary size is critical
- **Interactive applications with Rust backend support**
- Embedded systems or containers
- Fast startup time required
- Batch processing and rendering

**How it works**:
StaticCompiler compiles Julia code to native machine code without the Julia runtime. For features not supported by StaticCompiler (like window management), we use C-compatible FFI to call Rust functions directly, giving us the best of both worlds: tiny binaries with full interactivity!

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
