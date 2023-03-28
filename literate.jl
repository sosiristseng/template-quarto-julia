using Distributed
using Literate
using PrettyTables

# For all processes
@everywhere begin
    ENV["GKSwstype"] = 100
    import Pkg
    Pkg.activate(@__DIR__)
end

config = Dict("mdstrings" => true)
folder = joinpath(@__DIR__, "docs")
nbs = [nb for nb in readdir(folder) if splitext(nb)[end] == ".jl"]

ts = pmap(nbs; on_error=ex->NaN) do nb
    @elapsed Literate.notebook(joinpath(folder, nb), folder; config)
end

pretty_table([nbs ts], header=["Notebook", "Elapsed (s)"])

any(isnan, ts) && error("Error(s) occured!")
