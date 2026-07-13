using PyCall

xlrd = PyCall.pyimport("xlrd")
baseline = xlrd.open_workbook(joinpath(@__DIR__, "testdata", "forecast-date-by-event-date.xls"))
sheet = baseline.sheet_by_name("GDP - 1 quarter change")
comp = readxls(joinpath(@__DIR__, "testdata", "forecast-date-by-event-date.xls"))
sheet_comp = comp["GDP - 1 quarter change"]

for row in 1:sheet.nrows-1 # Skip over dates b/c complex
    for col in 0:sheet.ncols-1
        base_value = sheet.cell_value(row, col)
        comp_value = sheet_comp[row+1, col+1].value
        @test (isnothing(comp_value) && base_value == "") || (base_value == comp_value)
    end
end

