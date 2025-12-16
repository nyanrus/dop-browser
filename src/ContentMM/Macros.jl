"""
    Macros

Content-- macro system for reusable components.

Macros are expanded into Primitives at AOT compile time:
```
macro VStack(...) => Stack(Direction: Down, ...);
macro HStack(...) => Stack(Direction: Right, ...);
macro Button(label) => Stack(...) { Paragraph { Span(Text: label) } };
```

## Key Features
- Zero runtime cost (expanded at compile time)
- Type-safe semantic constraints
- Composable component system
"""
module Macros

using ..Primitives: NodeType, NODE_STACK, NODE_RECT, NODE_PARAGRAPH, NODE_SPAN
using ..Properties: Direction, DIRECTION_DOWN, DIRECTION_RIGHT, Pack, Align

export MacroDefinition, MacroTable, MacroExpansion
export define_macro!, expand_macro, get_macro

"""
    MacroParameter

A parameter in a macro definition.
"""
struct MacroParameter
    name::Symbol
    param_type::Symbol  # :node, :style, :value, :vararg
    default_value::Any
end

"""
    MacroDefinition

A macro definition that expands to primitives.

# Fields
- `name_id::UInt32` - Interned macro name
- `parameters::Vector{MacroParameter}` - Macro parameters
- `expansion_template::Dict{Symbol, Any}` - Template for expansion
- `output_type::NodeType` - The primitive type produced
"""
struct MacroDefinition
    name_id::UInt32
    parameters::Vector{MacroParameter}
    expansion_template::Dict{Symbol, Any}
    output_type::NodeType
end

"""
    MacroExpansion

Result of expanding a macro.
"""
struct MacroExpansion
    node_type::NodeType
    properties::Dict{Symbol, Any}
    children_templates::Vector{Dict{Symbol, Any}}
end

"""
    MacroTable

Table of macro definitions.
"""
mutable struct MacroTable
    definitions::Vector{MacroDefinition}
    name_lookup::Dict{UInt32, UInt32}  # name_id -> macro_id
    
    function MacroTable()
        new(MacroDefinition[], Dict{UInt32, UInt32}())
    end
end

"""
    define_macro!(table::MacroTable, name_id::UInt32, 
                  parameters::Vector{MacroParameter},
                  output_type::NodeType,
                  template::Dict{Symbol, Any}) -> UInt32

Define a new macro.
"""
function define_macro!(table::MacroTable, name_id::UInt32,
                       parameters::Vector{MacroParameter},
                       output_type::NodeType,
                       template::Dict{Symbol, Any})::UInt32
    defn = MacroDefinition(name_id, parameters, template, output_type)
    push!(table.definitions, defn)
    id = UInt32(length(table.definitions))
    table.name_lookup[name_id] = id
    return id
end

"""
    get_macro(table::MacroTable, macro_id::UInt32) -> Union{MacroDefinition, Nothing}

Get a macro definition by ID.
"""
function get_macro(table::MacroTable, macro_id::UInt32)::Union{MacroDefinition, Nothing}
    if macro_id == 0 || macro_id > length(table.definitions)
        return nothing
    end
    return table.definitions[macro_id]
end

"""
    expand_macro(table::MacroTable, macro_id::UInt32, 
                 args::Dict{Symbol, Any}) -> MacroExpansion

Expand a macro with given arguments.
"""
function expand_macro(table::MacroTable, macro_id::UInt32,
                      args::Dict{Symbol, Any})::MacroExpansion
    defn = get_macro(table, macro_id)
    if defn === nothing
        return MacroExpansion(NODE_STACK, Dict{Symbol, Any}(), Dict{Symbol, Any}[])
    end
    
    # Build properties from template
    props = Dict{Symbol, Any}()
    for (key, value) in defn.expansion_template
        if key == :children
            continue
        end
        
        # Substitute parameters
        if value isa Symbol && haskey(args, value)
            props[key] = args[value]
        else
            props[key] = value
        end
    end
    
    # Handle children templates
    children = Dict{Symbol, Any}[]
    if haskey(defn.expansion_template, :children)
        for child_template in defn.expansion_template[:children]
            child = Dict{Symbol, Any}()
            for (key, value) in child_template
                if value isa Symbol && haskey(args, value)
                    child[key] = args[value]
                else
                    child[key] = value
                end
            end
            push!(children, child)
        end
    end
    
    return MacroExpansion(defn.output_type, props, children)
end

# Built-in macro definitions

"""
    create_builtin_macros!(table::MacroTable, intern_func::Function)

Create built-in Content-- macros.
"""
function create_builtin_macros!(table::MacroTable, intern_func::Function)
    # VStack macro - vertical Stack
    vstack_id = intern_func("VStack")
    define_macro!(table, vstack_id,
        MacroParameter[
            MacroParameter(:children, :vararg, nothing)
        ],
        NODE_STACK,
        Dict{Symbol, Any}(
            :direction => DIRECTION_DOWN
        )
    )
    
    # HStack macro - horizontal Stack
    hstack_id = intern_func("HStack")
    define_macro!(table, hstack_id,
        MacroParameter[
            MacroParameter(:children, :vararg, nothing)
        ],
        NODE_STACK,
        Dict{Symbol, Any}(
            :direction => DIRECTION_RIGHT
        )
    )
    
    # Center macro - centered Stack
    center_id = intern_func("Center")
    define_macro!(table, center_id,
        MacroParameter[
            MacroParameter(:child, :node, nothing)
        ],
        NODE_STACK,
        Dict{Symbol, Any}(
            :pack => Pack.PACK_CENTER,
            :align => Align.ALIGN_CENTER
        )
    )
end

end # module Macros
