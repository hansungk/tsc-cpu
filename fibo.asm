    JAL FIB                     ; #a7, $2 = a8
    ADI $1, $0, -1              ; #b2, $1 = 5 - 1 = 4
    BGZ	$1, FIBRECUR            ; #b3, $1 = 4 > 0
    SWD $2, $3, 0               ; #b8, mem[3+0] <= a8
    SWD $0, $3, 1               ; #b9, mem[3+1] <= 5
    ADI $3, $3, 2               ; #ba, $3 = 3 + 2 = 5
    ADI $0, $0, -2              ; #bb, $0 = 5 - 2 = 3
    JAL FIB                     ; #bc, $2 = bd
    ADI $1, $0, -1              ; #b2, $1 = 3 - 1 = 2
    BGZ	$1, FIBRECUR            ; #b3, $1 = 2 > 0
    SWD $2, $3, 0               ; #b8, mem[5+0] <= bd
    SWD $0, $3, 1               ; #b9, mem[5+1] <= 3
    ADI $3, $3, 2               ; #ba, $3 = 5 + 2 = 7
    ADI $0, $0, -2              ; #bb, $0 = 3 - 2 = 1
    JAL FIB                     ; #bc, $2 = bd
    ADI $1, $0, -1              ; #b2, $1 = 1 - 1 = 0
    BGZ $1, FIBRECUR            ; #b3, $1 = 0 !> 0
    LHI $0, 0                   ; #b4, $0 = 0
    ORI $0, $0, 1               ; #b5, $0 = 1
    JPR $2                      ; #b6, goto bd
    LWD $1, $3, -1              ; #bd, $1 <= mem[7-1] = 3
    SWD $0, $3, -1              ; #be, mem[7-1] <= 1
    ADI $0, $1, -1              ; #bf, $0 = 3 - 1 = 2
    JAL FIB                     ; #c0, $2 = c1              <= num_inst = 0091
    ADI $1, $0, -1              ; #b2, $1 = 2 - 1 = 1
    BGZ $1, FIBRECUR            ; #b3, $1 = 1 > 0
    SWD $2, $3, 0               ; #b8, mem[7+0] <= c1
    SWD $0, $3, 1               ; #b9, mem[7+1] <= 2
    ADI $3, $3, 2               ; #ba, $3 = 7 + 2 = 9
    ADI $0, $0, -2              ; #bb, $0 = 2 - 2 = 0
    JAL FIB                     ; #bc, $2 = bd
    ADI $1, $0, -1              ; #b2, $1 = 0 - 1 = -1
    BGZ $1, FIBRECUR            ; #b3, $1 = -1 !> 0
    LHI $0, 0                   ; #b4, $0 = 0
    ORI $0, $0, 1               ; #b5, $0 = 1
    JPR $2                      ; #b6, goto bd
    LWD $1, $3, -1              ; #bd, $1 <= mem[9-1] = 2
    SWD $0, $3, -1              ; #be, mem[9-1] = 1
    ADI $0, $1, -1              ; #bf, $0 = 2 - 1 = 1
    JAL FIB                     ; #c0, $2 = c1
    ADI $1, $0, -1              ; #b2, $1 = 1 - 1 = 0
    BGZ $1, FIBRECUR            ; #b3, $1 = 0 !> 0
    LHI $0, 0                   ; #b4, $0 = 0
    ORI $0, $0, 1               ; #b5, $0 = 1
    JPR $2                      ; #b6, goto c1
    LWD $1, $3, -1              ; #c1, $1 <= mem[9-1] = 1
    LWD $2, $3, -2              ; #c2, $2 <= mem[9-2] = c1
    ADD $0, $0, $1              ; #c3, $0 = 1 + 1 = 2
    ADI $3, $3, -2              ; #c4, $3 = 9 - 2 = 7
    JPR $2                      ; #c5, goto c1
    LWD $1, $3, -1              ; #c1, $1 <= mem[7-1] = 3
    LWD $2, $3, -2              ; #c2, $2 <= mem[7-2] = bd
    ADD $0, $0, $1              ; #c3, $0 = 2 + 3 = 5
    ADI $3, $3, -2              ; #c4, $3 = 7 - 2 = 5
    JPR $2                      ; #c5, goto bd
    LWD $1, $3, -1              ; #bd, $1 <= mem[5-1] = 5
    SWD $0, $3, -1              ; #be, mem[5-1] <= 5
    ADI $0, $1, -1              ; #bf, $0 = 5 - 1 = 4
    JAL FIB                     ; #c0, $2 = c1
    ADI $1, $0, -1              ; #b2, $1 = 4 - 1 = 3
    BGZ $1, FIBRECUR            ; #b3, $1 = 3 > 0
    SWD $2, $3, 0               ; #b8, mem[5+0] <= c1
    SWD $0, $3, 1               ; #b9, mem[5+1] <= 4
    ADI $3, $3, 2               ; #ba, $3 = 5 + 2 = 7
    ADI $0, $0, -2              ; #bb, $0 = 4 - 2 = 2
    JAL FIB                     ; #bc, $2 = bd
    ADI $1, $0, -1              ; #b2, $1 = 2 - 1 = 1
    BGZ $1, FIBRECUR            ; #b3, $1 = 1 > 0
    SWD $2, $3, 0               ; #b8, mem[7+0] <= bd
    SWD $0, $3, 1               ; #b9, mem[7+1] <= 2
    ADI $3, $3, 2               ; #ba, $3 = 7 + 2 = 9
    ADI $0, $0, -2              ; #bb, $0 = 2 - 2 = 0
    JAL FIB                     ; #bc, $2 = bd
    ADI $1, $0, -1              ; #b2, $1 = 0 - 1 = -1
    BGZ $1, FIBRECUR            ; #b3, $1 = -1 !> 0
    LHI $0, 0                   ; #b4, $0 = 0
    ORI $0, $0, 1               ; #b5, $0 = 1
    JPR $2                      ; #b6, goto bd
    LWD $1, $3, -1              ; #bd, $1 <= mem[9-1] = 2
    SWD $0, $3, -1              ; #be, mem[9-1] <= $0 = 1
    ADI $0, $1, -1              ; #bf, $0 = 2 - 1 = 1
    JAL FIB                     ; #c0, $2 = c1
    ADI $1, $0, -1              ; #b2, $1 = 1 - 1 = 0
    BGZ $1, FIBRECUR            ; #b3, $1 = 0 !> 0
    LHI $0, 0                   ; #b4, $0 = 0
    ORI $0, $0, 1               ; #b5, $0 = 1
    JPR $2                      ; #b6, goto c1
    LWD $1, $3, -1              ; #c1, $1 <= mem[9-1] = 1
    LWD $2, $3, -2              ; #c2, $2 <= mem[9-2] = bd
    ADD $0, $0, $1              ; #c3, $0 = 1 + 1 = 2
    ADI $3, $3, -2              ; #c4, $3 = 9 - 2 = 7
    JPR $2                      ; #c5, goto bd
    LWD $1, $3, -1              ; #bd, $1 <= mem[7-1] = 4
    SWD $0, $3, -1              ; #be, mem[7-1] <= 2
    ADI $0, $1, -1              ; #bf, $0 = 4 - 1 = 3
    JAL FIB                     ; #c0, $2 = c1                    <= num_inst = 00DA
