using Test
using DataFrames
using XLSReader

const TESTDATA = joinpath(@__DIR__, "testdata", "f11hist-1969-2009.xls")
const FORECAST_TESTDATA = joinpath(@__DIR__, "testdata", "forecast-date-by-event-date.xls")

@testset "readxlsheet" begin
    df = readxlsheet(TESTDATA, "Data"; skip = 10)

    @test df isa DataFrame
    # Sheet has 531 rows; header is row 11, so 531 - 11 = 520 data rows
    @test nrow(df) == 520
    @test names(df)[2] == "FXRJY"
    @test names(df)[3] == "FXRUSD"

    # First data row corresponds to sheet row 12
    @test df[1, "FXRJY"] ≈ 2.7216392e8 rtol = 1e-6
    @test df[1, "FXRUSD"] ≈ 1.1138 rtol = 1e-6

    # Index-based access returns the same result
    df_by_index = readxlsheet(TESTDATA, 1; skip = 10)
    @test df_by_index isa DataFrame
    @test nrow(df_by_index) == nrow(df)

    @test_throws ErrorException readxlsheet(TESTDATA, 99)
    @test_throws ErrorException readxlsheet(TESTDATA, "NoSuchSheet")
end

@testset "readxlsheet forecast-date-by-event-date.xls" begin
    # Notes sheet: 23 rows (row 1 = header "Data Collection"), 3 cols
    df_notes = readxlsheet(FORECAST_TESTDATA, "Notes")
    @test df_notes isa DataFrame
    @test nrow(df_notes) == 22
    @test ncol(df_notes) == 3
    @test names(df_notes)[1] == "Data Collection"

    # GDP sheet: 159 rows (row 1 = header), 141 cols
    df_gdp = readxlsheet(FORECAST_TESTDATA, "GDP - 1 quarter change")
    @test df_gdp isa DataFrame
    @test nrow(df_gdp) == 158
    @test ncol(df_gdp) == 141

    # Index-based access for GDP sheet (sheet 2)
    df_by_index = readxlsheet(FORECAST_TESTDATA, 2)
    @test df_by_index isa DataFrame
    @test nrow(df_by_index) == nrow(df_gdp)
    @test ncol(df_by_index) == ncol(df_gdp)
end
