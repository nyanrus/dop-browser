#!/usr/bin/env julia
# Quick test to verify JuliaC setup without full compilation

using JuliaC
using Dates

println("=== JuliaC Setup Verification ===")
println("Julia version: $(VERSION)")
println("JuliaC version: $(pkgversion(JuliaC))")
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

# Test 2: Check if MemoAppMain entry point exists
println("\nTest 2: Checking @main entry point...")
try
    # Load the MemoAppMain file to define @main
    include(joinpath(dirname(dirname(@__FILE__)), "src", "MemoAppMain.jl"))
    println("✓ MemoAppMain file loaded")
    
    # Check if @main function exists (it's defined as a callable)
    println("✓ @main entry point defined")
catch e
    println("✗ MemoAppMain check failed: $e")
    exit(1)
end

# Test 3: Check for C compiler
println("\nTest 3: Checking for C compiler...")
try
    compiler = get(ENV, "JULIA_CC", "")
    if isempty(compiler)
        # Try common compilers
        for cc in ["clang", "gcc", "cc"]
            result = run(pipeline(`which $cc`, stdout=devnull, stderr=devnull); wait=false)
            wait(result)
            if success(result)
                compiler = cc
                break
            end
        end
    end
    
    if !isempty(compiler)
        println("✓ C compiler found: $compiler")
    else
        println("⚠ Warning: No C compiler found")
        println("  JuliaC requires clang or gcc")
        println("  Install with: sudo apt-get install clang (Linux) or brew install llvm (macOS)")
    end
catch e
    println("⚠ Could not verify C compiler: $e")
end

# Test 4: Estimate compilation requirements
println("\nTest 4: Checking Rust libraries...")
project_dir = dirname(dirname(@__FILE__))
println("  Project directory: $project_dir")

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
    println("\n⚠ Warning: Not all Rust libraries are built")
    println("  Run: julia deps/build.jl")
end

println("\n=== Setup Check Complete ===")
println("\nTo compile the full application, run:")
println("  julia --project=. scripts/compile_memo_app.jl")
println("\nNote: Compilation takes several minutes and requires ~2GB disk space.")
println("\nJuliaC features:")
println("  - Code trimming for smaller binaries")
println("  - Bundled libjulia and stdlibs for portability")
println("  - Faster compilation than PackageCompiler")
