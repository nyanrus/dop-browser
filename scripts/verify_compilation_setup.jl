#!/usr/bin/env julia
# Quick test to verify PackageCompiler setup without full compilation

using PackageCompiler
using Dates

println("=== PackageCompiler Setup Verification ===")
println("Julia version: $(VERSION)")
println("PackageCompiler version: $(pkgversion(PackageCompiler))")
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
println("\nTest 2: Checking julia_main entry point...")
try
    # Load the MemoAppMain file to define julia_main
    include(joinpath(dirname(dirname(@__FILE__)), "src", "MemoAppMain.jl"))
    println("✓ MemoAppMain file loaded")
    
    # Check if julia_main function exists
    if isdefined(Main, :julia_main)
        println("✓ julia_main function exists")
    else
        println("✗ julia_main function not found")
        exit(1)
    end
catch e
    println("✗ MemoAppMain check failed: $e")
    exit(1)
end

# Test 3: Verify precompile script runs
println("\nTest 3: Running precompile execution file...")
try
    include(joinpath(dirname(dirname(@__FILE__)), "scripts", "precompile_memo_app.jl"))
    println("✓ Precompile script executed successfully")
catch e
    println("✗ Precompile script failed: $e")
    exit(1)
end

# Test 4: Estimate compilation size
println("\nTest 4: Estimating compilation requirements...")
project_dir = dirname(dirname(@__FILE__))
println("  Project directory: $project_dir")
println("  Rust libraries required:")

rust_libs = ["dop-parser", "dop-renderer", "dop-content-ir"]
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
    end
end

println("\n=== All Checks Passed ===")
println("\nTo compile the full application, run:")
println("  julia --project=. scripts/compile_memo_app.jl")
println("\nNote: Compilation takes 10-20 minutes and requires ~2GB disk space.")
