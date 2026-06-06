using Documenter, DataFrames, XLSReader

makedocs(;
    sitename = "XLSReader.jl",
    modules = [XLSReader],
    pages = [
        "Home" => "index.md",
        "API Reference" => "api.md",
    ],
    format = Documenter.HTML(;
        prettyurls = get(ENV, "CI", nothing) == "true",
        canonical = "https://angusmoore.github.io/XLSReader.jl",
    ),
)

deploydocs(;
    repo = "github.com/angusmoore/XLSReader.jl",
    devbranch = "main",
)
