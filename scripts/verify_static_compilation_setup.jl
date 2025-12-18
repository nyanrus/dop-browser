#!/usr/bin/env julia
# Quick test to verify StaticCompiler setup without full compilation

using StaticCompiler
using StaticTools
using Dates

println("=== StaticCompiler Setup Verification ===")
println("Julia version: $(VERSION)")
println("StaticCompiler version: $(pkgversion(StaticCompiler))")
println("StaticTools version: $(pkgversion(StaticTools))")
println()

# Test 1: Check if DOPBrowser can be loaded
println("Test 1: Loading DOPBrowser package...")
try
    using DOPBrowser
    println("✓ DOPBrowser loaded successfully")
catch e
    println("✗ Failed to load DOPBrowser: $e")
    exit(1)
end

# Test 2: Check if StaticMemoMain entry point exists
println("\nTest 2: Checking StaticMemoMain entry point...")
try
    # Load the StaticMemoMain file to define c_main
    include(joinpath(dirname(dirname(@__FILE__)), "src", "StaticMemoMain.jl"))
    println("✓ StaticMemoMain file loaded")
    
    # Check if c_main function exists
    if isdefined(Main, :c_main)
        println("✓ c_main function exists")
    else
        println("✗ c_main function not found")
        exit(1)
    end
catch e
    println("✗ StaticMemoMain check failed: $e")
    exit(1)
end

# Test 3: Verify Rust libraries are available
println("\nTest 3: Checking Rust library availability...")
project_dir = dirname(dirname(@__FILE__))
println("  Project directory: $project_dir")
println("  Rust libraries required:")

rust_libs = ["dop-parser", "dop-renderer", "dop-content-ir"]
all_libs_found = true

for lib in rust_libs
    lib_name = replace(lib, "-" => "_")
    if Sys.iswindows()
        filename = "$(lib_name).dll"
    elseif Sys.isapple()
        filename = "lib$(lib_name).dylib"
    else
        filename = "lib$(lib_name).so"
    end
    lib_path = joinpath(project_dir, "artifacts", lib, filename)
    if isfile(lib_path)
        size_mb = round(filesize(lib_path) / (1024^2), digits=2)
        println("    ✓ $lib: $size_mb MB")
    else
        println("    ✗ $lib: not found at $lib_path")
        println("      Run: julia deps/build.jl")
        all_libs_found = false
    end
end

if !all_libs_found
    println("\n⚠ Warning: Not all Rust libraries found.")
    println("           Static compilation may fail without them.")
end

# Test 4: Check clang availability (required for StaticCompiler)
println("\nTest 4: Checking for clang compiler...")
try
    result = read(`which clang`, String)
    clang_path = strip(result)
    if !isempty(clang_path)
        println("✓ clang found at: $clang_path")
        # Check version
        version_output = read(`clang --version`, String)
        version_line = split(version_output, '\n')[1]
        println("  $version_line")
    else
        println("⚠ clang not found in PATH")
    end
catch e
    println("⚠ clang not found or not executable")
    println("  StaticCompiler requires clang to be installed.")
    println("  Install with: sudo apt-get install clang (Linux)")
    println("               brew install llvm (macOS)")
end

println("\n=== Verification Summary ===")
println("✓ StaticCompiler is installed and configured")
println("✓ Entry point (c_main) is available")

if all_libs_found
    println("✓ All Rust libraries are available")
else
    println("⚠ Some Rust libraries are missing")
end

println("\nTo compile the static memo application, run:")
println("  julia --project=. scripts/static_compile_memo_app.jl")
println()
println("Note: StaticCompiler creates truly standalone executables")
println("      without the Julia runtime, but with some limitations:")
println("  - Requires C-compatible entry points (@ccallable)")
println("  - Limited standard library support")
println("  - No dynamic dispatch or runtime compilation")
println("  - Much smaller binary size (~5-20 MB vs ~350-400 MB)")
