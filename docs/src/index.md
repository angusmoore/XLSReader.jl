# XLSReader.jl

Pure-Julia reader for XLS (Excel 97–2003, BIFF8) files.

!!! warning
    This is a quick vibe-coded port of Python's [xlrd](https://xlrd.readthedocs.io/).
    Use at your own risk.

## Quick start

Read a sheet directly into a `DataFrame`:

```julia
using XLSReader
df = readxlsheet("report.xls", "Sheet1")
```

Skip header rows with the `skip` keyword:

```julia
df = readxlsheet("report.xls", 1; skip = 2)
```

## Lower-level access

```julia
using XLSReader

wb = readxls("report.xls")

# List sheet names
[s.name for s in wb.sheets]

# Access by name or 1-based index
sheet = wb["Summary"]   # or wb[1]

# Read a cell (1-based row, column)
cell = sheet[2, 3]
cell.value   # String, Float64, Date, DateTime, Bool, or nothing
cell.type    # 0=empty, 1=text, 2=number, 3=date, 4=boolean, 5=error, 6=blank

# Iterate all cells
for row in 1:sheet.nrows, col in 1:sheet.ncols
    c = sheet[row, col]
    println(c.value)
end
```

## Format support

| Format | Support |
|--------|---------|
| BIFF8 (Excel 97–2003, `.xls`) | Full |
| BIFF5 (Excel 95) | Partial (simple files) |
| BIFF2/3/4 | Not supported |
| XLSX (Excel 2007+) | Not supported |
