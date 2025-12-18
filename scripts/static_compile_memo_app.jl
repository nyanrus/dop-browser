#!/usr/bin/env julia
# Compile the memo application into a standalone executable using StaticCompiler
# This creates a truly standalone binary without the Julia runtime.

using StaticCompiler
using StaticTools
using Dates

# Configuration
const APP_NAME = "static_memo_app"
const PROJECT_DIR = dirname(dirname(@__FILE__))
const OUTPUT_DIR = joinpath(PROJECT_DIR, "build")
const ENTRY_POINT = joinpath(PROJECT_DIR, "src", "StaticMemoMain.jl")

println("=== Static Compilation of Memo Application ===")
println("Project directory: $PROJECT_DIR")
println("Output directory: $OUTPUT_DIR")
println("Entry point: $ENTRY_POINT")
println()

# Create output directory if it doesn't exist
mkpath(OUTPUT_DIR)

# Note about static compilation
println("NOTE: StaticCompiler creates a truly standalone executable without")
println("      the Julia runtime. This results in much smaller binaries but")
println("      with some limitations on Julia features that can be used.")
println()

# Compile the application
println("Starting static compilation with StaticCompiler...")
println("This may take several minutes...")
println()

try
    # Load the entry point file
    include(ENTRY_POINT)
    
    # Compile to standalone executable
    # Note: StaticCompiler requires specific function signatures and limitations
    output_path = joinpath(OUTPUT_DIR, APP_NAME)
    
    println("Compiling c_main function to executable...")
    
    # Compile using StaticCompiler
    # The compile_executable function takes:
    # - The function to compile (c_main in this case)
    # - The output path for the executable
    # - Optional compiler flags for optimization
    
    compile_executable(
        c_main,           # Function marked with @ccallable
        output_path,      # Output executable path
        ()                # Function arguments (none for c_main)
    )
    
    println()
    println("✓ Static compilation successful!")
    println()
    
    # Report binary size
    executable_path = output_path
    if Sys.iswindows()
        executable_path *= ".exe"
    end
    
    if isfile(executable_path)
        size_bytes = filesize(executable_path)
        size_mb = round(size_bytes / (1024^2), digits=2)
        println("Binary size:")
        println("  Executable: $size_mb MB ($size_bytes bytes)")
        
        # Create a size report file
        report_file = joinpath(OUTPUT_DIR, "static_size_report.txt")
        open(report_file, "w") do io
            println(io, "Static Memo Application Size Report")
            println(io, "===================================")
            println(io, "Build date: $(Dates.now())")
            println(io, "Julia version: $(VERSION)")
            println(io, "StaticCompiler version: $(pkgversion(StaticCompiler))")
            println(io, "")
            println(io, "Executable size: $size_mb MB ($size_bytes bytes)")
            println(io, "")
            println(io, "Executable path: $executable_path")
            println(io, "")
            println(io, "Note: This is a standalone executable compiled without")
            println(io, "      the Julia runtime, resulting in a much smaller")
            println(io, "      binary compared to PackageCompiler.")
        end
        println()
        println("Size report saved to: $report_file")
    else
        @warn "Executable not found at expected location: $executable_path"
    end
    
catch e
    println()
    println("✗ Static compilation failed!")
    println("Error: $e")
    println()
    println("Note: StaticCompiler has limitations and may not work with all")
    println("      Julia features. The application may need simplification to")
    println("      be compatible with static compilation.")
    println()
    println("Common issues:")
    println("  - Dynamic dispatch and runtime type inference")
    println("  - Certain standard library functions")
    println("  - Complex FFI calls")
    println("  - String operations that allocate")
    println()
    rethrow(e)
end

println()
println("=== Static Compilation Complete ===")
println("You can find the compiled executable at: $(joinpath(OUTPUT_DIR, APP_NAME))")
println("Run it with: $(joinpath(OUTPUT_DIR, APP_NAME))")
println()
println("Comparison with PackageCompiler:")
println("  - PackageCompiler: ~350-400 MB (includes full Julia runtime)")
println("  - StaticCompiler: ~5-20 MB (standalone, no runtime)")
