# Packaging the Memo Application with PackageCompiler

This guide explains how to create a standalone executable of the memo application using PackageCompiler.

## Prerequisites

1. **Julia 1.10+**: The minimum required Julia version
2. **Rust toolchain**: Required to build the native libraries
3. **Built Rust libraries**: All three Rust crates must be built before compilation

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

Once the Rust libraries are built, you can compile the memo application:

```bash
julia --project=. scripts/compile_memo_app.jl
```

This will:
1. Create a `build/` directory in the project root
2. Compile the DOPBrowser package and all dependencies
3. Create a standalone executable at `build/memo_app/bin/memo_app`
4. Generate a size report at `build/size_report.txt`

The compilation process may take **10-20 minutes** depending on your system.

## Running the Compiled Application

After compilation, you can run the standalone executable:

```bash
# Run in interactive mode (default)
./build/memo_app/bin/memo_app

# Run in simple demo mode
./build/memo_app/bin/memo_app --simple

# Run in headless mode (no window)
HEADLESS=1 ./build/memo_app/bin/memo_app
```

The compiled application includes:
- All Julia code and dependencies
- The Julia runtime
- All required Rust libraries
- Font files and other resources

## Binary Size

The compiled application typically includes:

| Component | Size (approximate) |
|-----------|-------------------|
| Executable | 10-20 MB |
| Julia runtime | 100-150 MB |
| Dependencies | 50-100 MB |
| **Total** | **160-270 MB** |

A detailed size report is generated at `build/size_report.txt` after compilation.

## Size Reduction Techniques

PackageCompiler provides several options to reduce binary size:

### 1. Filter Standard Libraries

The compilation script already uses `filter_stdlibs=true`, which excludes unused standard library modules.

### 2. CPU Target

By default, the script uses `cpu_target="generic"` for maximum portability. For a specific CPU, you can modify the compilation script to use:

```julia
cpu_target="native"  # Optimize for current CPU
```

### 3. Minimal Precompilation

To reduce compilation time and potentially size, you can modify or remove the precompile execution file. Edit `scripts/precompile_memo_app.jl` to include only the most common code paths.

### 4. Strip Debug Symbols

After compilation, you can strip debug symbols from the executable:

```bash
strip build/memo_app/bin/memo_app
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

1. Package the entire `build/memo_app/` directory
2. Or create an archive:

```bash
cd build
tar czf memo_app.tar.gz memo_app/
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
