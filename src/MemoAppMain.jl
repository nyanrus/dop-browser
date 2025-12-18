"""
Entry point for the compiled memo application.
This file provides the @main function required by JuliaC.
"""

# Load DOPBrowser and the memo app
using DOPBrowser

# Load the memo app example
include(joinpath(dirname(dirname(@__FILE__)), "examples", "memo_app.jl"))

"""
    @main(args::Vector{String})

Entry point for the compiled application.
Returns 0 on success, non-zero on failure.
"""
function (@main)(args::Vector{String})
    try
        main()
        return 0  # Success
    catch e
        @error "Application error" exception=(e, catch_backtrace())
        return 1  # Failure
    end
end
