# Compilation Scripts

This directory contains scripts for compiling the DOPBrowser memo application into standalone executables.

## Scripts Overview

### 1. JuliaC (Recommended - Full Runtime with Modern Features)

**verify_compilation_setup.jl**
- Verifies that all prerequisites are installed for JuliaC
- Checks Rust libraries, Julia dependencies, and entry points
- Run before attempting full compilation

**compile_memo_app.jl**
- Compiles the full memo application with JuliaC
- Creates a standalone executable with trimmed code
- Includes the complete Julia runtime in a bundled directory
- Takes several minutes to compile
- Features code trimming for smaller binaries compared to PackageCompiler

**precompile_memo_app.jl**
- Legacy precompilation execution file (not used by JuliaC)
- Kept for reference only

### 2. StaticCompiler (Minimal Runtime)

**verify_static_compilation_setup.jl**
- Verifies prerequisites for StaticCompiler
- Checks for clang compiler, Rust libraries, and StaticCompiler installation
- Run before attempting static compilation

**static_compile_memo_app.jl**
- Compiles a lightweight memo application with StaticCompiler
- Creates a ~5-20 MB standalone executable
- No Julia runtime included
- Takes a few minutes to compile
- Supports both headless and interactive modes via Rust FFI

## Usage

### Quick Start - JuliaC

```bash
# 1. Build Rust libraries
julia deps/build.jl

# 2. Verify setup
julia --project=. scripts/verify_compilation_setup.jl

# 3. Compile application
julia --project=. scripts/compile_memo_app.jl

# 4. Run compiled app
./build/bin/memo_app
```

### Quick Start - StaticCompiler

```bash
# 1. Build Rust libraries
julia deps/build.jl

# 2. Verify setup
julia --project=. scripts/verify_static_compilation_setup.jl

# 3. Compile application
julia --project=. scripts/static_compile_memo_app.jl

# 4. Run in headless mode
./build/static_memo_app

# 5. Or run in interactive mode
./build/static_memo_app --onscreen
```

## Comparison

| Aspect | JuliaC | StaticCompiler |
|--------|--------|----------------|
| Binary Size | Smaller than PackageCompiler (with trimming) | 5-20 MB |
| Compilation Time | Several minutes | Few minutes |
| Julia Runtime | Included (bundled) | Not included |
| Features | Full | Subset (with Rust FFI) |
| Interactive Mode | ✓ Full Julia | ✓ Via Rust FFI |
| Startup Time | Fast | Very fast |
| Code Trimming | ✓ Yes (--trim=safe) | N/A |

## Requirements

### Common Requirements
- Julia 1.12+
- Rust toolchain (cargo, rustc)
- Built Rust libraries (run `julia deps/build.jl`)

### Additional for JuliaC
- C compiler (clang or gcc)
- Automatically uses PackageCompiler as backend

### Additional for StaticCompiler
- Clang compiler (`sudo apt-get install clang` on Linux)
- StaticCompiler.jl package (automatically installed)

## Troubleshooting

### "Could not find dop-* library"
```bash
julia deps/build.jl
```

### "Package not found"
```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

### JuliaC: "clang not found"
```bash
# Linux
sudo apt-get install clang

# macOS
brew install llvm
```

### StaticCompiler: "clang not found"
```bash
# Linux
sudo apt-get install clang

# macOS
brew install llvm
```

### Compilation fails
1. Check verification script output
2. Ensure all Rust libraries are built
3. Check available disk space (need ~2GB)
4. Review error messages for specific issues

## Output Locations

- **JuliaC**: `build/`
  - Executable: `build/bin/memo_app`
  - Libraries: `build/lib/` and `build/lib/julia/`
  - Size report: `build/size_report.txt`

- **StaticCompiler**: `build/`
  - Executable: `build/static_memo_app`
  - Size report: `build/static_size_report.txt`

## More Information

See the documentation in `docs/`:
- `PACKAGING.md` - Detailed packaging instructions
- `BINARY_SIZE_REDUCTION.md` - Optimization strategies
