#!/usr/bin/env julia
# Compile the memo application into a standalone executable using JuliaC

using JuliaC
using Dates

# Configuration
const APP_NAME = "memo_app"
const PROJECT_DIR = dirname(dirname(@__FILE__))
const EXAMPLES_DIR = joinpath(PROJECT_DIR, "examples")
const OUTPUT_DIR = joinpath(PROJECT_DIR, "build")
const ENTRY_FILE = joinpath(PROJECT_DIR, "src", "MemoAppMain.jl")

println("=== Compiling Memo Application ===")
println("Project directory: $PROJECT_DIR")
println("Output directory: $OUTPUT_DIR")
println()

# Create output directory if it doesn't exist
mkpath(OUTPUT_DIR)

# Compile the application
println("Starting compilation with JuliaC...")
println("This may take several minutes...")
println()

try
    # Create image recipe
    img = ImageRecipe(
        output_type = "--output-exe",
        file = ENTRY_FILE,            # Entry file with @main function
        project = PROJECT_DIR,         # Project to use for dependencies
        trim_mode = "safe",           # Enable code trimming for smaller binaries
        verbose = true,               # Print detailed output
        cpu_target = "generic"        # Generic CPU target for portability
    )
    
    # Create link recipe
    link = LinkRecipe(
        image_recipe = img,
        outname = APP_NAME,           # Just the name, bundle will place it
        rpath = JuliaC.RPATH_BUNDLE   # Use bundle-relative rpath
    )
    
    # Create bundle recipe
    bundle = BundleRecipe(
        link_recipe = link,
        output_dir = OUTPUT_DIR,      # Bundle everything to build/
        privatize = false             # Don't privatize libjulia for now
    )
    
    # Compile, link, and bundle
    compile_products(img)
    link_products(link)
    bundle_products(bundle)
    
    println()
    println("✓ Compilation successful!")
    println()
    
    # Report binary size
    executable_path = joinpath(OUTPUT_DIR, "bin", APP_NAME)
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
        for (root, dirs, files) in walkdir(OUTPUT_DIR)
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
            try
                println(io, "JuliaC version: $(pkgversion(JuliaC))")
            catch
                println(io, "JuliaC version: (unable to determine)")
            end
            println(io, "")
            println(io, "Executable size: $size_mb MB ($size_bytes bytes)")
            println(io, "Total application size: $total_mb MB ($total_size bytes)")
            println(io, "")
            println(io, "Executable path: $executable_path")
            println(io, "")
            println(io, "Compilation options:")
            println(io, "  - Code trimming: safe")
            println(io, "  - CPU target: generic")
            println(io, "  - Bundled: yes")
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
println("You can find the compiled application in: $OUTPUT_DIR")
println("Run it with: $(joinpath(OUTPUT_DIR, "bin", APP_NAME))")
