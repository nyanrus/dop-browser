# build.jl - Build script for Rust FFI libraries
#
# This script provides unified build functionality for both dop-parser and dop-renderer
# Rust libraries. It can be run directly as a standalone script.
#
# Usage:
#   julia deps/build.jl          # Build all crates in release mode
#   julia deps/build.jl debug    # Build all crates in debug mode

const RUST_CRATES = ["dop-parser", "dop-renderer"]

"""
    get_artifact_dir(name::String) -> String

Get the artifact directory for a given Rust crate.
"""
function get_artifact_dir(name::String)
    artifacts_dir = joinpath(@__DIR__, "..", "artifacts")
    mkpath(artifacts_dir)
    return joinpath(artifacts_dir, name)
end

"""
    get_lib_name(name::String) -> String

Get the platform-specific library filename.
"""
function get_lib_name(name::String)
    # Convert crate name to library name (dop-parser -> libdop_parser.so)
    lib_name = replace(name, "-" => "_")
    if Sys.iswindows()
        return "$(lib_name).dll"
    elseif Sys.isapple()
        return "lib$(lib_name).dylib"
    else
        return "lib$(lib_name).so"
    end
end

"""
    build_rust_crate(name::String; release::Bool=true) -> String

Build a Rust crate and return the path to the built library.
"""
function build_rust_crate(name::String; release::Bool=true)
    rust_dir = joinpath(@__DIR__, "..", "rust", name)
    
    if !isdir(rust_dir)
        error("Rust crate directory not found: $rust_dir")
    end
    
    # Determine target directory based on build mode
    target_dir = release ? "release" : "debug"
    
    @info "Building Rust crate: $name" release=release
    
    # Run cargo build with error handling
    cd(rust_dir) do
        cmd = release ? `cargo build --release` : `cargo build`
        result = run(cmd; wait=true)
        if !success(result)
            error("Failed to build Rust crate: $name. Run 'cargo build' in $rust_dir for details.")
        end
    end
    
    # Return path to built library
    lib_path = joinpath(rust_dir, "target", target_dir, get_lib_name(name))
    
    if !isfile(lib_path)
        error("Built library not found: $lib_path")
    end
    
    return lib_path
end

"""
    install_library(name::String, lib_path::String)

Install a built library to the artifacts directory.
"""
function install_library(name::String, lib_path::String)
    artifact_dir = get_artifact_dir(name)
    mkpath(artifact_dir)
    
    lib_name = get_lib_name(name)
    dest_path = joinpath(artifact_dir, lib_name)
    
    @info "Installing library" from=lib_path to=dest_path
    cp(lib_path, dest_path; force=true)
    
    return dest_path
end

"""
    build_all(; release::Bool=true)

Build all Rust crates and install them to the artifacts directory.
"""
function build_all(; release::Bool=true)
    for crate in RUST_CRATES
        lib_path = build_rust_crate(crate; release=release)
        install_library(crate, lib_path)
    end
    @info "All Rust crates built successfully"
end

"""
    get_library_path(name::String) -> Union{String, Nothing}

Get the path to an installed library, or nothing if not installed.
"""
function get_library_path(name::String)
    # First check artifacts directory
    artifact_dir = get_artifact_dir(name)
    lib_name = get_lib_name(name)
    artifact_path = joinpath(artifact_dir, lib_name)
    
    if isfile(artifact_path)
        return artifact_path
    end
    
    # Then check the Rust target directory (for development)
    rust_dir = joinpath(@__DIR__, "..", "rust", name)
    for profile in ["release", "debug"]
        lib_path = joinpath(rust_dir, "target", profile, lib_name)
        if isfile(lib_path)
            return lib_path
        end
    end
    
    return nothing
end

"""
    ensure_built(name::String; release::Bool=true) -> String

Ensure a library is built and return the path to it.
"""
function ensure_built(name::String; release::Bool=true)
    lib_path = get_library_path(name)
    
    if isnothing(lib_path)
        lib_path = build_rust_crate(name; release=release)
        install_library(name, lib_path)
        lib_path = get_library_path(name)
    end
    
    if isnothing(lib_path)
        error("Failed to build or locate library: $name")
    end
    
    return lib_path
end

# If run as a script, build all crates
if abspath(PROGRAM_FILE) == @__FILE__
    release = !("debug" in ARGS)
    build_all(; release=release)
end
