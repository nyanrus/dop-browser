"""
    Environment

Content-- environment declarations for AOT compilation targets.

Environments define static build targets (breakpoints) that generate 
specialized binary files:
```
environment desktop(width: 769..);
environment mobile(width: 0..768);
environment tablet(width: 769..1024);
```

## Key Features
- AOT resolution of environment-specific layouts
- Zero runtime branching for layout
- Specialized `.bin` files per environment
"""
module Environment

export EnvironmentDecl, EnvironmentTable, BreakpointRange
export define_environment!, get_environment, resolve_environment
export ExternalVar, ExternalVarTable, define_external!, get_external

"""
    BreakpointRange

A range for breakpoint matching.
"""
struct BreakpointRange
    min_value::Float32
    max_value::Float32
    
    function BreakpointRange(min_val::Float32 = 0.0f0, 
                             max_val::Float32 = typemax(Float32))
        new(min_val, max_val)
    end
end

"""
    matches(range::BreakpointRange, value::Float32) -> Bool

Check if a value matches the breakpoint range.
"""
function matches(range::BreakpointRange, value::Float32)::Bool
    return value >= range.min_value && value <= range.max_value
end

"""
    EnvironmentDecl

An environment declaration with breakpoint constraints.

# Fields
- `name_id::UInt32` - Interned environment name
- `width_range::BreakpointRange` - Viewport width range
- `height_range::BreakpointRange` - Viewport height range
- `priority::Int32` - Resolution priority (higher = preferred)
"""
struct EnvironmentDecl
    name_id::UInt32
    width_range::BreakpointRange
    height_range::BreakpointRange
    priority::Int32
end

"""
    EnvironmentTable

Table of environment declarations.
"""
mutable struct EnvironmentTable
    environments::Vector{EnvironmentDecl}
    name_lookup::Dict{UInt32, UInt32}  # name_id -> env_id
    active_env::UInt32
    
    function EnvironmentTable()
        new(EnvironmentDecl[], Dict{UInt32, UInt32}(), UInt32(0))
    end
end

"""
    define_environment!(table::EnvironmentTable, name_id::UInt32;
                        width_min::Float32 = 0.0f0,
                        width_max::Float32 = typemax(Float32),
                        height_min::Float32 = 0.0f0,
                        height_max::Float32 = typemax(Float32),
                        priority::Int32 = Int32(0)) -> UInt32

Define a new environment.
"""
function define_environment!(table::EnvironmentTable, name_id::UInt32;
                             width_min::Float32 = 0.0f0,
                             width_max::Float32 = typemax(Float32),
                             height_min::Float32 = 0.0f0,
                             height_max::Float32 = typemax(Float32),
                             priority::Int32 = Int32(0))::UInt32
    env = EnvironmentDecl(
        name_id,
        BreakpointRange(width_min, width_max),
        BreakpointRange(height_min, height_max),
        priority
    )
    push!(table.environments, env)
    id = UInt32(length(table.environments))
    table.name_lookup[name_id] = id
    return id
end

"""
    get_environment(table::EnvironmentTable, env_id::UInt32) -> Union{EnvironmentDecl, Nothing}

Get an environment by ID.
"""
function get_environment(table::EnvironmentTable, env_id::UInt32)::Union{EnvironmentDecl, Nothing}
    if env_id == 0 || env_id > length(table.environments)
        return nothing
    end
    return table.environments[env_id]
end

"""
    resolve_environment(table::EnvironmentTable, 
                        width::Float32, height::Float32) -> UInt32

Resolve which environment matches the given viewport dimensions.
Returns the ID of the best matching environment, or 0 if none match.
"""
function resolve_environment(table::EnvironmentTable, 
                             width::Float32, height::Float32)::UInt32
    best_id = UInt32(0)
    best_priority = typemin(Int32)
    
    for (i, env) in enumerate(table.environments)
        if matches(env.width_range, width) && matches(env.height_range, height)
            if env.priority > best_priority
                best_priority = env.priority
                best_id = UInt32(i)
            end
        end
    end
    
    table.active_env = best_id
    return best_id
end

"""
    ExternalVar

An external variable injected at runtime (for theming, etc.).

# Fields
- `name_id::UInt32` - Interned variable name
- `var_type::Symbol` - Type (:color, :number, :string)
- `value::Any` - Current value
- `default_value::Any` - Default value
"""
mutable struct ExternalVar
    name_id::UInt32
    var_type::Symbol
    value::Any
    default_value::Any
end

"""
    ExternalVarTable

Table of external variables for runtime injection.
"""
mutable struct ExternalVarTable
    variables::Vector{ExternalVar}
    name_lookup::Dict{UInt32, UInt32}
    
    function ExternalVarTable()
        new(ExternalVar[], Dict{UInt32, UInt32}())
    end
end

"""
    define_external!(table::ExternalVarTable, name_id::UInt32,
                     var_type::Symbol, default_value) -> UInt32

Define an external variable.
"""
function define_external!(table::ExternalVarTable, name_id::UInt32,
                          var_type::Symbol, default_value)::UInt32
    var = ExternalVar(name_id, var_type, default_value, default_value)
    push!(table.variables, var)
    id = UInt32(length(table.variables))
    table.name_lookup[name_id] = id
    return id
end

"""
    get_external(table::ExternalVarTable, var_id::UInt32) -> Any

Get the current value of an external variable.
"""
function get_external(table::ExternalVarTable, var_id::UInt32)::Any
    if var_id == 0 || var_id > length(table.variables)
        return nothing
    end
    return table.variables[var_id].value
end

"""
    set_external!(table::ExternalVarTable, var_id::UInt32, value)

Set the value of an external variable (runtime injection).
"""
function set_external!(table::ExternalVarTable, var_id::UInt32, value)
    if var_id == 0 || var_id > length(table.variables)
        return
    end
    table.variables[var_id].value = value
end

end # module Environment
