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
    executables=["memo_app" => "MemoAppMain"],
    force=true,
    include_lazy_artifacts=false,  # Don't include unused artifacts
    filter_stdlibs=true,
    cpu_target="native",           # Optimize for local CPU
    sysimage_build_args=`--optimize=3 --check-bounds=no`  # Aggressive optimization
)
```

**Expected savings**: 20-50 MB
**Trade-off**: Less portable, no runtime bounds checking

### 5. Use Static Compilation (Experimental)

Julia's static compilation is still experimental but can significantly reduce size by removing the JIT compiler:

```julia
# Requires Julia 1.9+ with static compilation support
create_app(
    PROJECT_DIR,
    joinpath(OUTPUT_DIR, APP_NAME),
    precompile_execution_file=PRECOMPILE_FILE,
    executables=["memo_app" => "MemoAppMain"],
    force=true,
    sysimage_build_args=`--compiled-modules=no`
)
```

**Expected savings**: 100-150 MB (removes LLVM and codegen)
**Trade-off**: Significant limitations, may not work with all features

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
3. **Static compilation** (experimental): -100 MB
4. **Remove unused stdlib**: -30 MB

**Expected final size**: 60-100 MB (highly optimized, less portable)

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
