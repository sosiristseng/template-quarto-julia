using Tables
using MarkdownTables
using SHA
using IJulia
using JSON
ENV["GKSwstype"] = "100"

# Strip SVG output from a Jupyter notebook
function strip_svg(nbpath)
    oldfilesize = filesize(nbpath)
    nb = open(JSON.parse, nbpath, "r")
    for cell in nb["cells"]
        !haskey(cell, "outputs") && continue
        for output in cell["outputs"]
            !haskey(output, "data") && continue
            datadict = output["data"]
            if haskey(datadict, "image/png") || haskey(datadict, "image/jpeg")
                delete!(datadict, "text/html")
                delete!(datadict, "image/svg+xml")
            end
        end
    end
    rm(nbpath; force=true)
    write(nbpath, JSON.json(nb, 1))
    @info "Stripped SVG in $(nbpath). The original size is $(oldfilesize). The new size is $(filesize(nbpath))."
    return nbpath
end

# Remove cached notebook and sha files if there is no corresponding notebook
function clean_cache(cachedir)
    for (root, _, files) in walkdir(cachedir)
        for file in files
            fn, ext = splitext(file)
            if ext == ".sha"
                target = joinpath(joinpath(splitpath(root)[2:end]), fn)
                nb = target * ".ipynb"
                if !isfile(nb)
                    cachepath = joinpath(root, fn)
                    @info "Notebook $(nb) not found. Removing SHA and notebook in $(cachepath)."
                    rm(cachepath * ".sha"; force=true)
                    rm(cachepath * ".ipynb"; force=true)
                end
            end
        end
    end
end

# List notebooks without caches in a file tree
function list_notebooks(basedir, cachedir)
    list = String[]
    for (root, _, files) in walkdir(basedir)
        for file in files
            name, ext = splitext(file)
            if ext == ".ipynb"
                nb = joinpath(root, file)
                shaval = read(nb, String) |> sha256 |> bytes2hex
                @info "$(nb) SHA256 = $(shaval)"
                shafilename = joinpath(cachedir, root, name * ".sha")
                if isfile(shafilename) && read(shafilename, String) == shaval
                    @info "$(nb) cache hits and will not be executed."
                else
                    @info "$(nb) cache misses. Writing hash to $(shafilename)."
                    mkpath(dirname(shafilename))
                    write(shafilename, shaval)
                    push!(list, nb)
                end
            end
        end
    end
    return list
end

function main(;
    basedir=get(ENV, "DOCDIR", "docs"),
    cachedir=get(ENV, "NBCACHE", ".cache"),
    rmsvg=true)

    mkpath(cachedir)
    clean_cache(cachedir)
    nblist = list_notebooks(basedir, cachedir)

    if !isempty(nblist)
        IJulia.installkernel("Julia", "--project=@.")
        # nbconvert command options
        ntasks = parse(Int, get(ENV, "NBCONVERT_JOBS", "1"))
        kernelname = "--ExecutePreprocessor.kernel_name=julia-1.$(VERSION.minor)"
        execute = ifelse(get(ENV, "ALLOWERRORS", "false") == "true", "--execute --allow-errors", "--execute")
        timeout = "--ExecutePreprocessor.timeout=" * get(ENV, "TIMEOUT", "-1")
        # Run the nbconvert commands in parallel
        ts_ipynb = asyncmap(nblist; ntasks) do nb
            @elapsed begin
                nbout = joinpath(abspath(pwd()), cachedir, nb)
                cmd = `jupyter nbconvert --to notebook $(execute) $(timeout) $(kernelname) --output $(nbout) $(nb)`
                run(cmd)
                rmsvg && strip_svg(nbout)
            end
        end
        # Print execution result
        Tables.table([nblist ts_ipynb]; header=["Notebook", "Elapsed (s)"]) |> markdown_table(String) |> print
    end
end

# Run code
main()
