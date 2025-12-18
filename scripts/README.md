# Compilation Scripts

This directory contains scripts for compiling the DOPBrowser memo application into standalone executables.

## Scripts Overview

### 1. PackageCompiler (Full Runtime)

**verify_compilation_setup.jl**
- Verifies that all prerequisites are installed for PackageCompiler
- Checks Rust libraries, Julia dependencies, and entry points
- Run before attempting full compilation

**compile_memo_app.jl**
- Compiles the full memo application with PackageCompiler
- Creates a ~350-400 MB standalone executable
- Includes the complete Julia runtime
- Takes 10-20 minutes to compile

**precompile_memo_app.jl**
- Precompilation execution file for PackageCompiler
- Traces code paths that should be precompiled
- Used automatically by compile_memo_app.jl

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

### Quick Start - PackageCompiler

```bash
# 1. Build Rust libraries
julia deps/build.jl

# 2. Verify setup
julia --project=. scripts/verify_compilation_setup.jl

# 3. Compile application
julia --project=. scripts/compile_memo_app.jl

# 4. Run compiled app
./build/memo_app/bin/memo_app
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

| Aspect | PackageCompiler | StaticCompiler |
|--------|----------------|----------------|
| Binary Size | 350-400 MB | 5-20 MB |
| Compilation Time | 10-20 minutes | Few minutes |
| Julia Runtime | Included | Not included |
| Features | Full | Subset (with Rust FFI) |
| Interactive Mode | ✓ Full Julia | ✓ Via Rust FFI |
| Startup Time | Fast | Very fast |

## Requirements

### Common Requirements
- Julia 1.10+
- Rust toolchain (cargo, rustc)
- Built Rust libraries (run `julia deps/build.jl`)

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
3. Check available disk space (need ~2GB for PackageCompiler)
4. Review error messages for specific issues

## Output Locations

- **PackageCompiler**: `build/memo_app/`
  - Executable: `build/memo_app/bin/memo_app`
  - Size report: `build/size_report.txt`

- **StaticCompiler**: `build/`
  - Executable: `build/static_memo_app`
  - Size report: `build/static_size_report.txt`

## More Information

See the documentation in `docs/`:
- `PACKAGING.md` - Detailed packaging instructions
- `BINARY_SIZE_REDUCTION.md` - Optimization strategies
