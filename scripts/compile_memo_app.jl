#!/usr/bin/env julia
# Compile the memo application into a standalone executable using PackageCompiler

using PackageCompiler
using Dates

# Configuration
const APP_NAME = "memo_app"
const PROJECT_DIR = dirname(dirname(@__FILE__))
const EXAMPLES_DIR = joinpath(PROJECT_DIR, "examples")
const OUTPUT_DIR = joinpath(PROJECT_DIR, "build")
const PRECOMPILE_FILE = joinpath(PROJECT_DIR, "scripts", "precompile_memo_app.jl")

println("=== Compiling Memo Application ===")
println("Project directory: $PROJECT_DIR")
println("Output directory: $OUTPUT_DIR")
println()

# Create output directory if it doesn't exist
mkpath(OUTPUT_DIR)

# Compile the application
println("Starting compilation with PackageCompiler...")
println("This may take several minutes...")
println()

try
    create_app(
        PROJECT_DIR,                    # Project to compile
        joinpath(OUTPUT_DIR, APP_NAME), # Output directory
        precompile_execution_file=PRECOMPILE_FILE,
        executables=["memo_app" => "julia_main"],
        force=true,                     # Overwrite existing build
        include_lazy_artifacts=true,    # Include artifacts
        filter_stdlibs=true,           # Reduce size by filtering standard libraries
        cpu_target="generic"           # Generic CPU target for portability
    )
    
    println()
    println("✓ Compilation successful!")
    println()
    
    # Report binary size
    executable_path = joinpath(OUTPUT_DIR, APP_NAME, "bin", "memo_app")
    if Sys.iswindows()
        executable_path *= ".exe"
    end
    
    if isfile(executable_path)
        size_bytes = filesize(executable_path)
        size_mb = round(size_bytes / (1024^2), digits=2)
        println("Binary size:")
        println("  Executable: $size_mb MB ($size_bytes bytes)")
        
        # Report total application size
        total_size = 0
        app_dir = joinpath(OUTPUT_DIR, APP_NAME)
        for (root, dirs, files) in walkdir(app_dir)
            for file in files
                total_size += filesize(joinpath(root, file))
            end
        end
        total_mb = round(total_size / (1024^2), digits=2)
        println("  Total application: $total_mb MB ($total_size bytes)")
        
        # Create a size report file
        report_file = joinpath(OUTPUT_DIR, "size_report.txt")
        open(report_file, "w") do io
            println(io, "Memo Application Size Report")
            println(io, "===========================")
            println(io, "Build date: $(Dates.now())")
            println(io, "Julia version: $(VERSION)")
            println(io, "")
            println(io, "Executable size: $size_mb MB ($size_bytes bytes)")
            println(io, "Total application size: $total_mb MB ($total_size bytes)")
            println(io, "")
            println(io, "Executable path: $executable_path")
        end
        println()
        println("Size report saved to: $report_file")
    else
        @warn "Executable not found at expected location: $executable_path"
    end
    
catch e
    println()
    println("✗ Compilation failed!")
    println("Error: $e")
    rethrow(e)
end

println()
println("=== Compilation Complete ===")
println("You can find the compiled application in: $(joinpath(OUTPUT_DIR, APP_NAME))")
println("Run it with: $(joinpath(OUTPUT_DIR, APP_NAME, "bin", "memo_app"))")
