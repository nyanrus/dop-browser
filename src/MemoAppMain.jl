"""
Entry point for the compiled memo application.
This file provides the julia_main function required by PackageCompiler.
"""

# Load DOPBrowser and the memo app
using DOPBrowser

# Load the memo app example
include(joinpath(dirname(dirname(@__FILE__)), "examples", "memo_app.jl"))

"""
    julia_main()::Cint

Entry point for the compiled application.
Returns 0 on success, non-zero on failure.
"""
function julia_main()::Cint
    try
        main()
        return 0  # Success
    catch e
        @error "Application error" exception=(e, catch_backtrace())
        return 1  # Failure
    end
end
