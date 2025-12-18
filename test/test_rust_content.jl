# Test RustContent wrapper
using Libdl

lib_name = if Sys.iswindows()
    "dop_content.dll"
elseif Sys.isapple()
    "libdop_content.dylib"
else
    "libdop_content.so"
end

lib_path = joinpath(@__DIR__, "..", "rust", "dop-content", "target", "release", lib_name)

if !isfile(lib_path)
    error("Library not found at: $lib_path")
end

println("Found library at: $lib_path")
println("Testing RustContent wrapper...")

# Load library
lib = dlopen(lib_path)

# Test basic calls
content_builder_new = dlsym(lib, :content_builder_new)
content_builder_begin_stack = dlsym(lib, :content_builder_begin_stack)
content_builder_span = dlsym(lib, :content_builder_span)
content_builder_node_count = dlsym(lib, :content_builder_node_count)
content_builder_free = dlsym(lib, :content_builder_free)

# Create builder
handle = ccall(content_builder_new, Ptr{Cvoid}, ())
println("Created builder handle: $handle")

# Add a stack
ccall(content_builder_begin_stack, Cvoid, (Ptr{Cvoid},), handle)
println("Added stack")

# Add a span
text = "Hello from Rust!"
ccall(content_builder_span, Cvoid, (Ptr{Cvoid}, Cstring), handle, text)
println("Added span: $text")

# Get node count
count = ccall(content_builder_node_count, Csize_t, (Ptr{Cvoid},), handle)
println("Node count: $count")

# Clean up
ccall(content_builder_free, Cvoid, (Ptr{Cvoid},), handle)
println("Freed builder")

dlclose(lib)

println("\nRustContent FFI test passed! ✓")
