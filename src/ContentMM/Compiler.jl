"""
    Compiler

Content-- AOT compiler that generates specialized binary files.

## Compilation Pipeline
1. Parse Content-- source into AST
2. Resolve macros to primitives
3. Flatten all style inheritance
4. Generate environment-specific binaries

## Binary Format
The `.bin` files contain:
- Flattened node tree (SoA format)
- Pre-computed layout constraints
- Style data (already flattened)
- Event binding table
- External variable references
"""
module Compiler

using ..Primitives: NodeTable, NodeType, NODE_ROOT, NODE_STACK, create_node!
using ..Properties: PropertyTable, resize_properties!
using ..Styles: StyleTable, FlatStyle, flatten_styles!, StyleResolver, resolve_archetype!
using ..Macros: MacroTable
using ..Environment: EnvironmentTable, resolve_environment

export CompiledUnit, CompilerContext, CompileOptions
export compile!, compile_for_environment!, write_binary, read_binary

"""
    CompileOptions

Options for the Content-- compiler.
"""
struct CompileOptions
    optimize_level::Int          # 0 = debug, 1 = release, 2 = aggressive
    flatten_styles::Bool         # Pre-flatten all styles
    inline_macros::Bool          # Inline all macro expansions
    generate_sourcemap::Bool     # Generate source mappings
    target_environments::Vector{UInt32}  # Environment IDs to compile for
end

"""
    default_options() -> CompileOptions

Create default compiler options.
"""
function default_options()::CompileOptions
    return CompileOptions(1, true, true, false, UInt32[])
end

"""
    CompiledUnit

A compiled Content-- unit ready for runtime.

# Fields
- `nodes::NodeTable` - Compiled node tree
- `properties::PropertyTable` - Node properties
- `styles::Vector{FlatStyle}` - Flattened styles
- `environment_id::UInt32` - Target environment
- `version::UInt32` - Binary format version
- `checksum::UInt64` - Content checksum
"""
mutable struct CompiledUnit
    nodes::NodeTable
    properties::PropertyTable
    styles::Vector{FlatStyle}
    environment_id::UInt32
    version::UInt32
    checksum::UInt64
    
    function CompiledUnit()
        new(NodeTable(), PropertyTable(), FlatStyle[], UInt32(0), UInt32(1), UInt64(0))
    end
end

"""
    CompilerContext

Context for the Content-- compiler.
"""
mutable struct CompilerContext
    # Input
    style_table::StyleTable
    macro_table::MacroTable
    env_table::EnvironmentTable
    style_resolver::StyleResolver
    
    # Output
    units::Dict{UInt32, CompiledUnit}  # env_id -> compiled unit
    
    # State
    options::CompileOptions
    errors::Vector{String}
    warnings::Vector{String}
    
    function CompilerContext(options::CompileOptions = default_options())
        new(
            StyleTable(),
            MacroTable(),
            EnvironmentTable(),
            StyleResolver(),
            Dict{UInt32, CompiledUnit}(),
            options,
            String[],
            String[]
        )
    end
end

"""
    compile!(ctx::CompilerContext, source_nodes::NodeTable, 
             source_props::PropertyTable) -> Bool

Compile a Content-- AST to binary format.
"""
function compile!(ctx::CompilerContext, source_nodes::NodeTable,
                  source_props::PropertyTable)::Bool
    # Step 1: Flatten styles (AOT)
    if ctx.options.flatten_styles
        flatten_styles!(ctx.style_table)
    end
    
    # Step 2: Compile for each target environment
    if isempty(ctx.options.target_environments)
        # Compile for default (no specific environment)
        unit = compile_unit(ctx, source_nodes, source_props, UInt32(0))
        ctx.units[UInt32(0)] = unit
    else
        for env_id in ctx.options.target_environments
            unit = compile_unit(ctx, source_nodes, source_props, env_id)
            ctx.units[env_id] = unit
        end
    end
    
    return isempty(ctx.errors)
end

"""
    compile_unit(ctx::CompilerContext, source_nodes::NodeTable,
                 source_props::PropertyTable, env_id::UInt32) -> CompiledUnit

Compile for a specific environment.
"""
function compile_unit(ctx::CompilerContext, source_nodes::NodeTable,
                      source_props::PropertyTable, env_id::UInt32)::CompiledUnit
    unit = CompiledUnit()
    unit.environment_id = env_id
    
    n = length(source_nodes.node_types)
    resize_properties!(unit.properties, n)
    
    # Copy nodes (resolving environment-specific values)
    for i in 1:n
        node_type = source_nodes.node_types[i]
        parent = source_nodes.parents[i]
        style_id = source_nodes.style_ids[i]
        
        new_id = create_node!(unit.nodes, node_type, parent=parent, style_id=style_id)
        
        # Copy properties
        if i <= length(source_props.direction)
            unit.properties.direction[new_id] = source_props.direction[i]
            unit.properties.pack[new_id] = source_props.pack[i]
            unit.properties.align[new_id] = source_props.align[i]
            unit.properties.width[new_id] = source_props.width[i]
            unit.properties.height[new_id] = source_props.height[i]
            unit.properties.gap_row[new_id] = source_props.gap_row[i]
            unit.properties.gap_col[new_id] = source_props.gap_col[i]
            unit.properties.inset_top[new_id] = source_props.inset_top[i]
            unit.properties.inset_right[new_id] = source_props.inset_right[i]
            unit.properties.inset_bottom[new_id] = source_props.inset_bottom[i]
            unit.properties.inset_left[new_id] = source_props.inset_left[i]
            unit.properties.offset_top[new_id] = source_props.offset_top[i]
            unit.properties.offset_right[new_id] = source_props.offset_right[i]
            unit.properties.offset_bottom[new_id] = source_props.offset_bottom[i]
            unit.properties.offset_left[new_id] = source_props.offset_left[i]
            unit.properties.fill_r[new_id] = source_props.fill_r[i]
            unit.properties.fill_g[new_id] = source_props.fill_g[i]
            unit.properties.fill_b[new_id] = source_props.fill_b[i]
            unit.properties.fill_a[new_id] = source_props.fill_a[i]
        end
    end
    
    # Copy flattened styles
    for flat in ctx.style_table.flattened
        push!(unit.styles, flat)
    end
    
    # Compute checksum
    unit.checksum = compute_checksum(unit)
    
    return unit
end

"""
    compute_checksum(unit::CompiledUnit) -> UInt64

Compute a checksum for the compiled unit.
"""
function compute_checksum(unit::CompiledUnit)::UInt64
    n = length(unit.nodes.node_types)
    h = hash(n)
    h = hash(unit.environment_id, h)
    h = hash(length(unit.styles), h)
    return h
end

"""
    write_binary(io::IO, unit::CompiledUnit)

Write a compiled unit to binary format.
"""
function write_binary(io::IO, unit::CompiledUnit)
    # Magic number
    write(io, UInt32(0x434D4D42))  # "CMMB" - Content-- Binary
    
    # Version
    write(io, unit.version)
    
    # Environment ID
    write(io, unit.environment_id)
    
    # Checksum
    write(io, unit.checksum)
    
    # Node count
    n = UInt32(length(unit.nodes.node_types))
    write(io, n)
    
    # Node data (packed)
    for i in 1:n
        write(io, UInt8(unit.nodes.node_types[i]))
        write(io, unit.nodes.parents[i])
        write(io, unit.nodes.first_children[i])
        write(io, unit.nodes.next_siblings[i])
        write(io, unit.nodes.style_ids[i])
    end
    
    # Style count
    s = UInt32(length(unit.styles))
    write(io, s)
    
    # Style data
    for style in unit.styles
        write(io, UInt8(style.direction))
        write(io, UInt8(style.pack))
        write(io, UInt8(style.align))
        write(io, style.width)
        write(io, style.height)
        write(io, style.fill_r)
        write(io, style.fill_g)
        write(io, style.fill_b)
        write(io, style.fill_a)
    end
end

"""
    read_binary(io::IO) -> Union{CompiledUnit, Nothing}

Read a compiled unit from binary format.
"""
function read_binary(io::IO)::Union{CompiledUnit, Nothing}
    # Check magic number
    magic = read(io, UInt32)
    if magic != 0x434D4D42
        return nothing
    end
    
    unit = CompiledUnit()
    
    # Read header
    unit.version = read(io, UInt32)
    unit.environment_id = read(io, UInt32)
    unit.checksum = read(io, UInt64)
    
    # Read nodes
    n = read(io, UInt32)
    for _ in 1:n
        node_type = NodeType(read(io, UInt8))
        parent = read(io, UInt32)
        first_child = read(io, UInt32)
        next_sibling = read(io, UInt32)
        style_id = read(io, UInt32)
        
        create_node!(unit.nodes, node_type, parent=parent, style_id=style_id)
    end
    
    # Read styles
    s = read(io, UInt32)
    for _ in 1:s
        # Simplified read - in production would read all fields
        direction = read(io, UInt8)
        pack = read(io, UInt8)
        align = read(io, UInt8)
        width = read(io, Float32)
        height = read(io, Float32)
        fill_r = read(io, UInt8)
        fill_g = read(io, UInt8)
        fill_b = read(io, UInt8)
        fill_a = read(io, UInt8)
        
        # Create flat style (simplified)
        flat = FlatStyle(
            Direction(direction), Pack(pack), Align(align),
            0.0f0, 0.0f0,  # gap
            width, height,  # size
            0.0f0, 0.0f0,  # min size
            typemax(Float32), typemax(Float32),  # max size
            0.0f0, 0.0f0, 0.0f0, 0.0f0,  # inset
            0.0f0, 0.0f0, 0.0f0, 0.0f0,  # offset
            fill_r, fill_g, fill_b, fill_a,
            0.0f0,  # round
            UInt64(0)
        )
        push!(unit.styles, flat)
    end
    
    return unit
end

# Import Direction, Pack, Align for read_binary
using ..Properties: Direction, Pack, Align

end # module Compiler
