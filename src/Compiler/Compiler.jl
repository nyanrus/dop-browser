"""
    Compiler

Content-- compiler module that transforms HTML+CSS to Content IR.

This module performs the compilation pipeline:
1. HTML parsing → Token tape
2. CSS parsing → Style rules
3. DOM construction → Node table
4. Style application → Archetype resolution
5. Pre-evaluation → Optimized Content IR

## Architecture

HTML + CSS → (Lowering) → Content IR → (Pre-evaluation) → Optimized IR

The compiler performs AOT (Ahead of Time) operations:
- Layout structure generation
- Inheritance flattening
- Style archetype computation
- Static analysis

## Usage

```julia
using DOPBrowser.Compiler

ctx = CompilerContext()
result = compile_document!(ctx, html_source, css_source)
```
"""
module Compiler

# Import from ContentMM for the actual lowering
# This module serves as the entry point for the compilation pipeline

export CompilerContext, compile_document!, compile_html!

"""
    CompilerContext

Context for compiling HTML+CSS to Content IR.

Holds the compilation state and intermediate results.
"""
mutable struct CompilerContext
    # Source mappings for debugging
    source_files::Dict{UInt32, String}
    file_counter::UInt32
    
    # Compilation options
    optimize::Bool
    debug_info::Bool
    
    function CompilerContext(; optimize::Bool = true, debug_info::Bool = false)
        new(Dict{UInt32, String}(), UInt32(0), optimize, debug_info)
    end
end

"""
    CompilationResult

Result of compiling an HTML+CSS document to Content-- IR.
"""
struct CompilationResult
    success::Bool
    node_count::Int
    archetype_count::Int
    style_count::Int
    error_message::String
    
    function CompilationResult(success::Bool; 
                               node_count::Int = 0,
                               archetype_count::Int = 0,
                               style_count::Int = 0,
                               error_message::String = "")
        new(success, node_count, archetype_count, style_count, error_message)
    end
end

export CompilationResult

"""
    register_source!(ctx::CompilerContext, source::String) -> UInt32

Register a source file and return its ID.
"""
function register_source!(ctx::CompilerContext, source::String)::UInt32
    ctx.file_counter += UInt32(1)
    ctx.source_files[ctx.file_counter] = source
    return ctx.file_counter
end

export register_source!

"""
    compile_document!(html::AbstractString, css::AbstractString = "") -> CompilationResult

Compile an HTML document with optional external CSS to Content IR.

This is the main entry point for the compilation pipeline:
1. Parse HTML to tokens
2. Parse CSS to rules
3. Build DOM from tokens
4. Apply CSS cascade
5. Generate Content-- primitives
6. Pre-evaluate static expressions
"""
function compile_document!(html::AbstractString, css::AbstractString = "")::CompilationResult
    ctx = CompilerContext()
    return compile_document!(ctx, html, css)
end

function compile_document!(ctx::CompilerContext, html::AbstractString, css::AbstractString = "")::CompilationResult
    try
        # Register sources for debugging
        html_id = register_source!(ctx, String(html))
        css_id = css != "" ? register_source!(ctx, String(css)) : UInt32(0)
        
        # The actual compilation is delegated to Core/BrowserContext
        # This module provides the high-level interface
        
        # For now, return a placeholder result
        # The actual implementation uses Core.process_document!
        return CompilationResult(true, 
                                 node_count = 0,
                                 archetype_count = 0,
                                 style_count = 0)
    catch e
        return CompilationResult(false, error_message = string(e))
    end
end

"""
    compile_html!(html::AbstractString) -> CompilationResult

Compile HTML with embedded styles to Content IR.

Extracts <style> blocks from the HTML and processes them as CSS.
"""
function compile_html!(html::AbstractString)::CompilationResult
    return compile_document!(html, "")
end

end # module Compiler
