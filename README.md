# XLSReader.jl

[![](https://img.shields.io/badge/docs-latest-blue.svg)](https://angusmoore.github.io/XLSReader.jl/dev/)
![Lifecycle](https://img.shields.io/badge/lifecycle-experimental-orange.svg)
![CI](https://github.com/angusmoore/XLSReader.jl/workflows/CI/badge.svg)
[![codecov](https://codecov.io/gh/angusmoore/XLSReader.jl/branch/main/graph/badge.svg?token=UQIWOX2GBL)](https://codecov.io/gh/angusmoore/XLSReader.jl)

Pure Julia copy of Python xlrd library for reading XLS (Excel 97-2003) files.

> [!WARNING]
> This is a quick vibe-coded copy of Python xlrd. Use at your own risk.

# Quick start: reading a sheet into a DataFrame
```julia
using XLSReader
sheet = readxlsheet(joinpath(pkgdir(XLSReader), "test", "testdata", "f11hist-1969-2009.xls"), "Data")
```

# Lower level reading
```julia
using XLSReader

wb = readxls("myfile.xls")

# List sheets
[s.name for s in wb.sheets]

# Read a cell (1-based row, column)
cell = wb.sheets[1][1, 1]
cell.value   # String, Float64, Date, DateTime, Bool, or nothing
cell.type    # XL_CELL_TEXT, XL_CELL_NUMBER, XL_CELL_DATE, etc.

# Iterate all cells
for row in 1:wb.sheets[1].nrows
    for col in 1:wb.sheets[1].ncols
        c = wb.sheets[1][row, col]
        # ...
    end
end
```
