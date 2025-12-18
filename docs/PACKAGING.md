# Packaging the Memo Application

This guide explains how to create standalone executables of the memo application using two different approaches: JuliaC (includes full Julia runtime with modern features) and StaticCompiler (standalone without runtime).

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Building Rust Libraries](#building-rust-libraries)
3. [Option 1: JuliaC](#option-1-juliac)
4. [Option 2: StaticCompiler](#option-2-staticcompiler)
5. [Comparison](#comparison)
6. [Troubleshooting](#troubleshooting)

## Prerequisites

1. **Julia 1.12+**: Required for JuliaC
2. **Rust toolchain**: Required to build the native libraries
3. **Built Rust libraries**: All three Rust crates must be built before compilation
4. **C compiler**: Required for JuliaC and StaticCompiler (clang or gcc)

## Building Rust Libraries

Before compiling the Julia application, you must build all required Rust libraries:

```bash
# Option 1: Use the unified build script (recommended)
julia deps/build.jl

# Option 2: Build each crate manually
cd rust/dop-parser && cargo build --release
cd ../dop-renderer && cargo build --release
cd ../dop-content-ir && cargo build --release
```

The build script will:
- Compile all Rust crates in release mode
- Copy the built libraries to the `artifacts/` directory
- Verify that all libraries are available

## Compiling the Memo Application

### Option 1: JuliaC

Once the Rust libraries are built, you can compile the memo application with JuliaC:

```bash
# Verify setup
julia --project=. scripts/verify_compilation_setup.jl

# Compile
julia --project=. scripts/compile_memo_app.jl
```

This will:
1. Create a `build/` directory in the project root
2. Compile the DOPBrowser package and all dependencies
3. Create a standalone executable at `build/bin/memo_app`
4. Bundle Julia runtime and libraries in `build/lib/`
5. Generate a size report at `build/size_report.txt`

The compilation process may take **several minutes** depending on your system.

**Binary size**: Smaller than old PackageCompiler approach due to code trimming

**Features**:
- Code trimming (`--trim=safe`) removes unreachable code
- Bundled distribution with relative rpaths
- Faster compilation than PackageCompiler
- Built on top of PackageCompiler.jl with modern enhancements

### Option 2: StaticCompiler

For a smaller standalone executable without the Julia runtime:

```bash
# Verify setup
julia --project=. scripts/verify_static_compilation_setup.jl

# Compile
julia --project=. scripts/static_compile_memo_app.jl
```

This will:
1. Create a `build/` directory in the project root
2. Compile a simplified version of the memo app to native code
3. Create a standalone executable at `build/static_memo_app`
4. Generate a size report at `build/static_size_report.txt`

The compilation process takes **a few minutes** (much faster than JuliaC).

**Binary size**: ~5-20 MB (no Julia runtime)

**Note**: The StaticCompiler version is a simplified memo app due to limitations in what Julia features can be statically compiled. It demonstrates the rendering capabilities but has fewer features than the full JuliaC version.

## Running the Compiled Applications

### JuliaC Version

After compilation, you can run the full-featured executable:

```bash
# Run in interactive mode (default)
./build/bin/memo_app

# Run in simple demo mode
./build/bin/memo_app --simple

# Run in headless mode (no window)
HEADLESS=1 ./build/bin/memo_app
```

The compiled application includes:
- All Julia code and dependencies
- The Julia runtime (bundled in lib/ directory)
- All required Rust libraries
- Font files and other resources

### StaticCompiler Version

After static compilation, run the lightweight executable:

```bash
# Run in headless mode (default - generates PNG)
./build/static_memo_app

# Run in interactive onscreen mode
./build/static_memo_app --onscreen
```

The static executable:
- **Headless mode**: Generates a PNG file `static_memo_output.png`
- **Onscreen mode**: Opens an interactive window with event handling via Rust FFI
- Is a standalone binary with minimal external dependencies (only Rust libraries)
- Does not include the Julia runtime
- Supports real-time rendering and mouse interaction through C-compatible Rust FFI

## Comparison

| Feature | JuliaC | StaticCompiler |
|---------|--------|----------------|
| Binary size | Smaller with trimming | 5-20 MB |
| Compilation time | Several minutes | Few minutes |
| Startup time | Fast (precompiled) | Very fast (native) |
| Julia features | Full support | Limited subset |
| Interactive mode | ✓ | **✓ (via Rust FFI)** |
| Headless mode | ✓ | ✓ |
| Event handling | ✓ | **✓ (via Rust FFI)** |
| External deps | Julia runtime + libs | Rust libs only |
| Distribution | Need full bundle | Single executable |
| Code trimming | ✓ Yes | N/A |

**When to use JuliaC:**
- Full application with all features
- Complex Julia code patterns
- Maximum Julia language support
- Development and testing
- Want smaller binaries than old PackageCompiler

**When to use StaticCompiler:**
- Minimal binary size critical
- Fast startup required
- **Interactive apps with Rust backend**
- Embedded systems or containers
- Simple to moderate complexity

## Size Reduction Techniques

JuliaC provides several options to reduce binary size:

### 1. Code Trimming (Built-in)

The compilation script uses `trim_mode="safe"`, which removes unreachable code and unused IR:

```julia
img = ImageRecipe(
    trim_mode = "safe",  # Removes unreachable code
    # ...
)
```

This significantly reduces binary size compared to old PackageCompiler.

### 2. CPU Target

By default, the script uses `cpu_target="generic"` for maximum portability. For a specific CPU, you can modify the compilation script to use:

```julia
cpu_target = "native"  # Optimize for current CPU
```

### 3. Strip Debug Symbols

After compilation, you can strip debug symbols from the executable:

```bash
strip build/bin/memo_app
```

This can reduce the executable size by 30-50%.

## Troubleshooting

### "Could not find dop-* library"

Ensure all Rust libraries are built and available in the `artifacts/` directory:

```bash
julia deps/build.jl
```

### Compilation fails with "Package not found"

Ensure all Julia dependencies are installed:

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

### Application crashes on startup

Verify that the Rust libraries are compatible with your system:

```bash
# Test in non-compiled mode first
HEADLESS=1 julia --project=. examples/memo_app.jl --simple
```

## Distribution

To distribute the compiled application:

1. Package the entire `build/` directory
2. Or create an archive:

```bash
tar czf memo_app.tar.gz build/
```

Recipients will need:
- A compatible Linux system (if built on Linux)
- No Julia installation required
- No Rust installation required

## Platform-Specific Notes

### Linux
- The executable is dynamically linked against glibc
- Font rendering requires fontconfig and freetype2
- X11 or Wayland for onscreen mode

### macOS
- Code signing may be required for distribution
- Use `cpu_target="generic"` for compatibility across macOS versions

### Windows
- Executable will be `memo_app.exe`
- May require Visual C++ redistributables

## Performance

Compiled applications have:
- **Faster startup time**: No JIT compilation needed
- **Smaller memory footprint**: Only required code is loaded
- **Same runtime performance**: Julia code runs at full speed

For maximum performance, use `cpu_target="native"` when compiling for a specific system.
