# BIFF record opcodes and cell type constants

# Record types
const XL_BOF = 0x0809
const XL_EOF = 0x000A
const XL_CODEPAGE = 0x0042
const XL_BOUNDSHEET = 0x0085
const XL_SST = 0x00FC
const XL_CONTINUE = 0x003C
const XL_EXTSST = 0x00FF
const XL_FORMAT = 0x041E
const XL_XF = 0x00E0
const XL_FONT = 0x0031
const XL_DATEMODE = 0x0022

# Cell data records
const XL_NUMBER = 0x0203
const XL_LABEL = 0x0204
const XL_LABELSST = 0x00FD
const XL_RK = 0x027E
const XL_MULRK = 0x00BD
const XL_BLANK = 0x0201
const XL_MULBLANK = 0x00BE
const XL_BOOLERR = 0x0205
const XL_FORMULA = 0x0006
const XL_FORMULA_ALT1 = 0x0206
const XL_FORMULA_ALT2 = 0x0406
const XL_STRING = 0x0207   # string result of FORMULA
const XL_DIMENSIONS = 0x0200
const XL_ROW = 0x0208

# Cell types (matching xlrd convention)
const XL_CELL_EMPTY = 0
const XL_CELL_TEXT = 1
const XL_CELL_NUMBER = 2
const XL_CELL_DATE = 3
const XL_CELL_BOOLEAN = 4
const XL_CELL_ERROR = 5
const XL_CELL_BLANK = 6

# BOF subtypes
const BOF_WORKBOOK = 0x0005
const BOF_WORKSHEET = 0x0010
const BOF_CHART = 0x0020
const BOF_MACRO = 0x0040

# Excel error codes
const XL_ERRORS = Dict{UInt8,String}(
    0x00 => "#NULL!",
    0x07 => "#DIV/0!",
    0x0F => "#VALUE!",
    0x17 => "#REF!",
    0x1D => "#NAME?",
    0x24 => "#NUM!",
    0x2A => "#N/A",
)

# Built-in number format codes that represent dates
# Codes 14-22 are date/time, 45-47 are time
const BUILTIN_DATE_FORMATS = Set{Int}([
    14,
    15,
    16,
    17,
    18,
    19,
    20,
    21,
    22,   # date and date+time
    45,
    46,
    47,                              # time-only
    27,
    28,
    29,
    30,
    31,
    32,
    33,
    34,
    35,
    36, # CJK date formats
    50,
    51,
    52,
    53,
    54,
    55,
    56,
    57,
    58,     # more CJK
    71,
    72,
    73,
    74,
    75,
    76,
    77,
    78,
    79,
    80,
    81,  # Thai
])

# Built-in format strings (for reference, not all used directly)
const BUILTIN_FORMATS = Dict{Int,String}(
    0 => "General",
    1 => "0",
    2 => "0.00",
    3 => "#,##0",
    4 => "#,##0.00",
    5 => "\$#,##0_);(\$#,##0)",
    6 => "\$#,##0_);[Red](\$#,##0)",
    7 => "\$#,##0.00_);(\$#,##0.00)",
    8 => "\$#,##0.00_);[Red](\$#,##0.00)",
    9 => "0%",
    10 => "0.00%",
    11 => "0.00E+00",
    12 => "# ?/?",
    13 => "# ??/??",
    14 => "m/d/yy",
    15 => "d-mmm-yy",
    16 => "d-mmm",
    17 => "mmm-yy",
    18 => "h:mm AM/PM",
    19 => "h:mm:ss AM/PM",
    20 => "h:mm",
    21 => "h:mm:ss",
    22 => "m/d/yy h:mm",
    37 => "#,##0_);(#,##0)",
    38 => "#,##0_);[Red](#,##0)",
    39 => "#,##0.00_);(#,##0.00)",
    40 => "#,##0.00_);[Red](#,##0.00)",
    41 => "_(* #,##0_);_(* (#,##0);_(* \"-\"_);_(@_)",
    42 => "_(\$* #,##0_);_(\$* (#,##0);_(\$* \"-\"_);_(@_)",
    43 => "_(* #,##0.00_);_(* (#,##0.00);_(* \"-\"??_);_(@_)",
    44 => "_(\$* #,##0.00_);_(\$* (#,##0.00);_(\$* \"-\"??_);_(@_)",
    45 => "mm:ss",
    46 => "[h]:mm:ss",
    47 => "mm:ss.0",
    48 => "##0.0E+0",
    49 => "@",
)
