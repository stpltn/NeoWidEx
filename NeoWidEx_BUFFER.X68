*-----------------------------------------------------------
* Title      : NeoWidEx
* Written by : Tom Stepleton
* Date       : XX November 2016
* Description:
*   Formatting and diagnostic tool for Widget drives,
*   inspired by the WidEx utility internal to Apple, and by
*   Patrick Schäfer's UsbWidEx hardware tool.
*   -- This file: Disk data buffer manipulation routines.
*      Equates from NeoWidEx_DEFS must be defined.
*      Macros from NeoWidEx_MACROS must be defined.
*      Resources from NeoWidEx_UI must be defined.
*      Resources from NeoWidEx_UI_FORMS must be defined.
*-----------------------------------------------------------


* NeoWidEx disk data buffer code ===========================

    ; BUFFER -- UI for manipulating the disk data buffer
    ; Args:
    ;   (none)
    ; Notes:
    ;   A "sub-UI" with its own menu and everything.
    ;   Probably destroys most registers; depends on what user chooses to do.
    ;   Will not trash beyond D0-D4/A0-A4.
BUFFER:
    MOVE.L  #sBufferMenu,zUiLoopMenu   ; Load UI loop arguments
    MOVE.L  #dBufferMenuHandlers,zUiLoopMenuHandlers
    BSR     UILOOP                   ; Execute the UI loop indefinitely
    BMI.S   BUFFER                   ; If a submenu exited, repeat the UI loop
    NEG.B   zUiLoopBreak             ; Otherwise, mark this submenu exiting...
    RTS                              ; ...and go back to main menu

    ; _RAWPRINT -- Display hex dump of data in the disk data buffer, with CRC
    ; Args:
    ;   (none)
    ; Notes:
    ;   Trashes A0.
_RAWPRINT:
    ; Print dump first
    mPrint  kCrtRow,kCrtCol,#kFirstCol,<$0D,'  --- DISK BUFFER CONTENTS ---'>
    mPrint  kCrtRow,kCrtCol,#kFirstCol,<$0D,'RAW TAG DATA'>
    LEA     zSectorTag,A0
    mDump.L kCrtRow,kCrtCol,#kFirstCol,A0,z_BufferTagLongs,endl
    mPrint  kCrtRow,kCrtCol,#kFirstCol,<$0D,'RAW SECTOR DATA'>
    LEA     zSectorData,A0
    mDump.L kCrtRow,kCrtCol,#kFirstCol,A0,z_BufferSectorLongs,endl
    ; Compute CRC of tag and data
    LEA     zSectorTag,A0            ; The CRC calculation starts here
    CLR.W   D2                       ; The CRC calculation should scan over...
    MOVE.B  z_BufferTagLongs,D2      ; ...this many longs of tag...
    ADD.B   z_BufferSectorLongs,D2   ; ...plus this many longs of sector data...
    LSL.W   #2,D2                    ; ...which is this many bytes
    BSR     _CRC                     ; Calculate CRC now
    MOVE.W  D0,-(A7)                 ; Copy CRC onto stack
    mPrint  kCrtRow,kCrtCol,#kFirstCol,<$0D,'TAG/SECTOR CRC16-'>,hx
    RTS                              ; Back to caller

    ; _CRC -- Compute 16-bit CRC of some data region
    ; Args:
    ;   D2: Word counting number of bytes of memory region to scan
    ;   A0: Points to start of memory region to fill
    ; Notes:
    ;   Trashes D0-D2/A0.
    ;   Computed CRC goes in D0.
_CRC:
    CLR.W   D0                       ; Initialise CRC with zeroes
    TST.W   D2                       ; What if the caller said: scan no bytes?
    BEQ.S   .rt                      ; No bytes left to scan? Return
    SUBQ.W  #1,D2                    ; Make D2 into a loop counter
.lo MOVE.B  (A0)+,D1                 ;   Copy next byte into A0
    LSL.W   #8,D1                    ;   Shift it left into word's MSByte
    EOR.W   D1,D0                    ;   XOR the result with the CRC
    MOVE.W  #7,D1                    ;   Repeat this next loop eight times
.li LSL.W   #1,D0                    ;     Left-shift the CRC one bit
    BCC.S   .db                      ;     If a bit fell off when we did that...
    EORI.W  #$1021,D0                ;     ...XOR this magic number with the CRC
.db DBRA    D1,.li                   ;     Repeat for the next bit
    DBRA    D2,.lo                   ;   Repeat outer loop for next byte
.rt RTS                              ; Back to caller

    ; _EDIT -- Edit tag and sector information
    ; Args:
    ;   (none)
    ; Notes:
    ;   Trashes D0-D4/A0-A4.
    ;   Cancelling _EDIT (by typing 'q' in a form) only prevents inputs from
    ;       the current form from being committed to memory. All previous form
    ;       inputs will have already been saved.
_EDIT:
    ; First, edit the tag
    mPrint  kCrtRow,kCrtCol,#kFirstCol,<$0D,'  --- EDIT BUFFER DATA ---'>
    mPrint  kCrtRow,kCrtCol,#kFirstCol,<$0D,'EDIT SECTOR TAG'>
    LEA     zSectorTag,A1            ; We will edit the sector tag
    MOVE.B  z_BufferTagLongs,D0      ; A sector tag has this many longwords
    MOVE.W  #$0,D1                   ; (For printing) Editing starts at byte 0
    BSR     _EDITMEM                 ; Edit the sector tag
    TST.B   zFormIntent              ; Did the user cancel?
    BEQ.S   .qt                      ; Yes: abort, with printed caveat
    mPrint  kCrtRow,kCrtCol,#kFirstCol,<$0D,'EDIT SECTOR DATA'>
    LEA     zSectorData,A1           ; We will edit sector data
    MOVE.B  z_BufferSectorLongs,D0   ; Sector data has this many longwords
    MOVE.W  #$0,D1                   ; (For printing) Editing starts at byte 0
    BSR     _EDITMEM                 ; Edit the sector data
    TST.B   zFormIntent              ; Did the user cancel?
    BEQ.S   .qt                      ; Yes: abort, with printed caveat
    RTS                              ; No, so back to caller
.qt mPrtMem kCrtRow,kCrtCol,#kFirstCol,export,#s_AbortEdit   ; Ack quit intent
    RTS                              ; Back to caller

    ; _EDITMEM -- Helper to _EDIT, mainly: edit a memory region
    ; Args:
    ;   D0: (byte) Size of the memory region to edit in longwords
    ;   D1: (word) For printing---bytes being edited will be said to start
    ;       from this position, in bytes
    ;   A1: Start of memory region to edit
    ; Notes:
    ;   Trashes D0-D4/A0-A4.
    ;   Behaviour is undefined if D0 is 0.
    ;   Prints nothing if the routine exits normally after editing the entire
    ;       region; prints nothing if user has stopped editing early by typing
    ;       'q'. Check zFormIntent to see which: if 0, early cancellation.
    ;   Cancelling _EDITMEM (by typing 'q' in a form) only prevents inputs from
    ;       the current form from being committed to memory. All previous form
    ;       inputs will have already been saved.
_EDITMEM:
    ; Prepare; how many longwords are there to edit?
    MOVE.L  A1,-(A7)                 ; Save memory region address on stack
    MOVE.L  A1,A2                    ; And copy to A2 to be FORM initial values
    CLR.W   D2                       ; Prepare for D2 to be a table offset
    MOVE.B  D0,D2                    ; Copy in longs left to edit
    CMPI.B  #4,D2                    ; Is it more than four?
    BLS.S   .ed                      ; Yes, skip past the next line
    MOVE.B  #4,D2                    ; No, limit longs to edit to four

    ; Edit this next batch of longwords
.ed MOVEM.W D0-D2,-(A7)              ; Save sizing info in registers to stack
    LSL.B   #2,D2                    ; Convert D2 from longwords to bytes
    ; This clumsy interlude to print which bytes we're editing
    ADD.W   D2,D1                    ; The number of the last byte we'll edit...
    SUBQ.W  #1,D1                    ; ...is D2+D1-1
    MOVE.W  D1,-(A7)                 ; Onto stack for printing
    SUB.W   D2,D1                    ; And now to restore the number of the...
    ADDQ.W  #1,D1                    ; ...first byte we'll edit
    MOVE.W  D1,-(A7)                 ; Onto stack for printing
    mPrint  kCrtRow,kCrtCol,#kFirstCol,<$0D,' BYTES '>,hx,<'-'>,hx
    ; Another clumsy interlude to customise form prompts, which trashes D0-D1
    MOVEA.L #(21+z_EditPrompts),A4   ; "Customisable area" of first prompt to A4
    MOVE.W  D1,D0                    ; HEXW2STR needs its argument to be in D0
    MOVE.W  #3,D1                    ; We'll repeat the following four times
.fp BSR     HEXW2STR                 ; Build string representation of D0
    mMemCpy A3,A4,#4                 ; Copy string representation to prompt
    ADDQ.W  #4,D0                    ; Update D0 for the next prompt
    ADDA.W  #10,A4                   ; Move to the next "customisable area"
    DBRA    D1,.fp                   ; Loop to update the next prompt
    ; Back to the editing
    SUBQ.B  #4,D2                    ; Make D2 a memory offset: subtract four
    LEA     s_LongsForms,A0          ; Form pointer array base to A0
    MOVEA.L 0(A0,D2.W),A0            ; Get form template address in A0, then...
    LEA     z_EditPrompts,A1         ; ...address of prompt pointer array...
    SUBA.L  A3,A3                    ; ...A2 already set, and no bounds in A3
    BSR     FORM                     ; Launch the form
    ; Back from form, restore registers, did user want to cancel?
    MOVEM.W (A7)+,D0-D2              ; Restore sizing info on stack to registers
    MOVE.L  (A7)+,A1                 ; Restore memory region address from stack
    TST.B   zFormIntent              ; Did the user cancel?
    BEQ     .rt                      ; Yes, jump ahead to quit

    ; Update sizing information and copy data
    SUB.B   D2,D0                    ; Update number of longwords left to edit
    LSL.B   #2,D2                    ; Compute the number of bytes just edited
    mMemCpy #zFieldValues,A1,D2      ; Copy that many bytes from form to memory
    ADD.W   D2,D1                    ; Update byte position for printing
    ADDA.W  D2,A1                    ; Point A1 just past region just edited
    TST.B   D0                       ; Did we run out of memory left to copy?
    BNE     _EDITMEM                 ; Nope, so go around again!

.rt RTS                              ; Back to caller

    ; _PATTERN -- Fill the data buffer with a user-specified pattern
    ; Args:
    ;   (none)
    ; Notes:
    ;   Trashes D0-D4/A0-A4.
_PATTERN:
    ; First we ask the user for the pattern length
    mPrint  kCrtRow,kCrtCol,#kFirstCol,<$0D,'  --- PATTERN FILL ---'>
    LEA     s_LongsToEditForm,A0     ; Prepare FORM args; address of template...
    LEA     s_LongsToEditPrompts,A1  ; ...address of prompt pointer array...
    LEA     z_LongsToEdit,A2         ; ...address of initial values array...
    LEA     d_LongsToEditBounds,A3   ; ...and you can't edit over 4 at a time
    BSR     FORM                     ; Launch the form
    ; Back from form, did user want to cancel?
    TST.B   zFormIntent              ; Did the user cancel?
    BEQ     .qt                      ; Yes, jump ahead to quit

    ; Copy user selection to the initial values array
    MOVE.L  zFieldValues,z_LongsToEdit   ; Did user select a length of 0?
    BEQ     .qt                      ; Yes, jump ahead to quit

    ; Next we ask the user for a fill pattern
    MOVE.L  z_LongsToEdit,D0         ; Prepare FORM args; which template?
    SUBQ.B  #1,D0                    ; First, form length to array index...
    LSL.B   #2,D0                    ; ...times four for longword offsets
    LEA     s_LongsForms,A0          ; Form pointer array base to A0
    MOVEA.L 0(A0,D0.W),A0            ; Finally, get template address, then...
    LEA     s_LongsPrompts,A1        ; ...address of prompt pointer array...
    LEA     z_PatternInitialVals,A2  ; ...address of initial values array...
    SUBA.L  A3,A3                    ; ...and pattern values have no bounds!
    mPrint  kCrtRow,kCrtCol,#kFirstCol,<$0D,'ENTER PATTERN'>
    BSR     FORM                     ; Launch the form
    ; Back from form, did user want to cancel?
    TST.B   zFormIntent              ; Did the user cancel?
    BEQ     .qt                      ; Yes, jump ahead to quit

    ; Copy form values to initial values, saving them for next time
    mMemCpy #zFieldValues,#z_PatternInitialVals,#$10

    ; Now fill the buffer with a nice unrolled loop
    LEA     zSectorTag,A0            ; A0 will iterate through the buffer
    MOVE.B  z_BufferTagLongs,D2      ; Number of longs to fill is tag size...
    ADD.B   z_BufferSectorLongs,D2   ; ...plus sector size
    MOVE.L  z_LongsToEdit,D1         ; Pattern size into D1

.lp LEA     z_PatternInitialVals,A1  ; Refresh pattern start into A1
    MOVE.B  D1,D0                    ; Refresh pattern size into D0

    MOVE.L  (A1)+,(A0)+              ; Copy first pattern long
    SUBQ.B  #1,D2                    ; Decrement long count
    BEQ.S   .rt                      ; All done? Jump to return
    SUBQ.B  #1,D0                    ; Decrement longs left in pattern
    BEQ.S   .lp                      ; Pattern over? Back up to restart it

    MOVE.L  (A1)+,(A0)+              ; Copy second pattern long
    SUBQ.B  #1,D2                    ; Decrement long count
    BEQ.S   .rt                      ; All done? Jump to return
    SUBQ.B  #1,D0                    ; Decrement longs left in pattern
    BEQ.S   .lp                      ; Pattern over? Back up to restart it

    MOVE.L  (A1)+,(A0)+              ; Copy third pattern long
    SUBQ.B  #1,D2                    ; Decrement long count
    BEQ.S   .rt                      ; All done? Jump to return
    SUBQ.B  #1,D0                    ; Decrement longs left in pattern
    BEQ.S   .lp                      ; Pattern over? Back up to restart it

    MOVE.L  (A1)+,(A0)+              ; Copy fourth pattern long
    SUBQ.B  #1,D2                    ; Decrement long count
    BEQ.S   .rt                      ; All done? Jump to return
    BRA.S   .lp                      ; And another round through the pattern

.rt mPrint  kCrtRow,kCrtCol,#kFirstCol,<$0D,'DONE.'>
    RTS                              ; Return to caller

.qt mPrint  kCrtRow,kCrtCol,#kFirstCol,<$0D,'...ABORTED...'>   ; Ack quit intent
    RTS                              ; Back to caller

    ; _RANDOM -- Fill the data buffer with pseudo-random data
    ; Args:
    ;   (none)
    ; Notes:
    ;   Trashes D0-D4/A0-A4.
_RANDOM:
    ; First we ask the user for a random seed
    mPrint  kCrtRow,kCrtCol,#kFirstCol,<$0D,'  --- RANDOM FILL ---'>
    LEA     s_RandomForm,A0          ; Prepare FORM args: address of template...
    LEA     s_RandomPrompts,A1       ; ...address of prompt pointer array...
    LEA     d_RandomInitialVals,A2   ; ...address of initial values array...
    LEA     d_RandomBounds,A3        ; ...address of value bounds array
    BSR     FORM                     ; Launch the form

    ; Back from form; did user want to cancel?
    TST.B   zFormIntent              ; Did the user cancel?
    BNE.S   .go                      ; No, go ahead with seeking
    mPrint  kCrtRow,kCrtCol,#kFirstCol,<$0D,'...ABORTED...'>   ; Yes, ack user
    RTS                              ; Back to caller

    ; Perform random fill and return to caller
.go MOVE.L  zFieldValues,D0          ; Copy random seed to D0
    NOT.W   D0                       ; Invert its bits
    LEA     zSectorTag,A0            ; Starting address for fill
    CLR.W   D2                       ; The amount of memory to fill...
    MOVE.B  z_BufferTagLongs,D2      ; ...should be tag size...
    ADD.B   z_BufferSectorLongs,D2   ; ...plus sector size...
    LSL.W   #2,D2                    ; ...as bytes
    BSR     _LFSRFILL                ; Call random filler
    mPrint  kCrtRow,kCrtCol,#kFirstCol,<$0D,'DONE.'>
    RTS                              ; Back to caller

    ; _LFSRFILL -- Fill a memory region with LFSR-generated random data
    ; Args:
    ;   D0: LFSR initial value; must not be $0000
    ;   D2: Word counting number of bytes to fill
    ;   A0: Points to start of memory region to fill
    ; Notes:
    ;   Trashes D0-D3/A0.
    ;   http://en.wikipedia.org/wiki/Linear-feedback_shift_register#Galois_LFSRs
_LFSRFILL:
    TST.W   D2                       ; What if caller didn't want any bytes?
.lo BEQ.S   .rt                      ;   No bytes left to fill? Return

    MOVE.W  #9,D3                    ;   We want to get 8 random bits
.li SUBQ.B  #1,D3                    ;     Decrement bits-left counter
    BEQ.S   .nb                      ;     No more bits? On to the next byte
    LSL.B   #1,D1                    ;     Make room in accum for the next bit
    BTST.L  #0,D0                    ;     Is LFSR LSBit on?
    BEQ.S   .no                      ;     No, skip ahead to end of loop
    ORI.B   #1,D1                    ;     Yes, set next accumulator bit on
    LSR.W   #1,D0                    ;     Shift LFSR one bit right
    EORI.W  #$B400,D0                ;     XOR it with the taps and set MSBit
    BRA.S   .li                      ;     Back to top of loop for next bit
.no LSR.W   #1,D0                    ;     Shift LFSR one bit right
    BRA.S   .li                      ;     Back to top of loop for next bit

.nb MOVE.B  D1,(A0)+                 ;   Copy new random byte to buffer
    SUBQ.W  #1,D2                    ;   Decrement bytes-left counter
    BRA.S   .lo                      ;   And back up to top of loop

.rt RTS                              ; Back to caller

    ; _RESIZE -- Change buffer sizing for these memory manipulation subroutines
    ; Args:
    ;   (none)
    ; Notes:
    ;   Trashes D0-D4/A0-A4.
_RESIZE:
    MOVE.B  z_BufferTagLongs,(3+z_ResizeInitialVals)     ; Current settings...
    MOVE.B  z_BufferSectorLongs,(7+z_ResizeInitialVals)  ; ...into initial vals
    LEA     s_ResizeForm,A0          ; Prepare FORM args: address of template...
    LEA     s_ResizePrompts,A1       ; ...address of prompt pointer array...
    LEA     z_ResizeInitialVals,A2   ; ...address of initial values array...
    SUBA.L  A3,A3                    ; ...and no upper bounds on sizing
    BSR     FORM                     ; Launch the form

    ; Back from form; did user want to cancel?
    TST.B   zFormIntent              ; Did the user cancel?
    BNE.S   .go                      ; No, go ahead with seeking
    mPrint  kCrtRow,kCrtCol,#kFirstCol,<$0D,'...ABORTED...'>   ; Yes, ack user
    RTS                              ; Back to caller

    ; Copy values from form to sizing settings
.go MOVE.L  zFieldValues,D0          ; Copy tag size to D0
    BEQ.S   .zr                      ; Abort if tag size is nonzero
    MOVE.L  (4+zFieldValues),D1      ; Copy sector size to D1
    BEQ.S   .zr                      ; Abort if sector size is nonzero
    MOVE.B  D0,z_BufferTagLongs      ; Put tag size in place
    MOVE.B  D1,z_BufferSectorLongs   ; Put sector size in place
    mPrint  kCrtRow,kCrtCol,#kFirstCol,<$0D,'DONE.'>
    RTS

.zr mPrint  kCrtRow,kCrtCol,#kFirstCol,<$0D,'SIZES MUST BE NONZERO.'>
    RTS


    PAGE
* NeoWidEx disk data buffer numerical data =================
    SECTION kSecData

    DS.W    0                        ; Force even alignment for what follows
dBufferMenuHandlers:                 ; Addresses of handlers for each of the...
    DC.L    (1+GOBACK)               ; ...menu items in sMainMenu
    DC.L    _RAWPRINT                ; 1+ means don't print a newline before...
    DC.L    _EDIT                    ; ...calling this handler; the LSBit...
    DC.L    _PATTERN                 ; ...will be cleared before the call
    DC.L    _RANDOM
    DC.L    _RESIZE
    DC.L    $00000000                ; Null terminator

d_RandomInitialVals:
    DC.L    $00001337                ; An elite default random seed
d_RandomBounds:
    DC.L    $0000FFFE                ; FFFF will become 0, a seed we can't use

d_LongsToEditBounds:
    DC.L    $00000004                ; Max is four at a time


    PAGE
* NeoWidEx disk data buffer scratch data allocation ========
    SECTION kSecScratch

z_BufferTagLongs:
    DC.B    $5                       ; Default tag size: 5 longwords
z_BufferSectorLongs:
    DC.B    $80                      ; Default sector size: 128 longwords

    DS.W    0
z_EditPrompts:                       ; Form prompts for editing. NOTE: the...
    DC.L    .p1,.p2,.p3,.p4          ; ..."xxxx" portions will be replaced...
.p1 DC.B    'FROM xxxx',0            ; ...by offsets from start of tag or...
.p2 DC.B    'FROM xxxx',0            ; ...sector; but the substitution works...
.p3 DC.B    'FROM xxxx',0            ; ...by memory position, not by finding...
.p4 DC.B    'FROM xxxx',0            ; ...the x's themselves

    DS.W    0
z_LongsToEdit:
    DC.L    $00000004                ; Number of longwords to edit/fill

    DS.W    0
z_PatternInitialVals:                ; We will remember the user's previous...
    DC.L    $55555555                ; ...fill patterns
    DC.L    $AAAAAAAA
    DC.L    $55555555
    DC.L    $AAAAAAAA

    DS.W    0
z_ResizeInitialVals:                 ; We will remember the user's previous...
    DC.L    $00000000                ; tag and sector data buffer sizes
    DC.L    $00000000


    PAGE
* NeoWidEx Reset_Servo strings ==============================
    SECTION kSecStrings

s_RandomForm:                        ; User form for specifying random seed
    DC.B    $0D,'RANDOM SEED-ab__',0

    DS.W    0
s_RandomPrompts:                     ; Form prompts for random seed
    DC.L    .p1
.p1 DC.B    'SEED',0

s_LongsToEditForm:                   ; User form for specifying pattern size
    DC.B    $0D,'PATTERN LENGTH IN LONGWORDS? aa',0

    DS.W    0
s_LongsToEditPrompts:                ; Form prompts for pattern size
    DC.L    .p1
.p1 DC.B    'LENGTH',0

    DS.W    0
s_LongsForms:                        ; Forms for different numbers of longwords
    DC.L    .f1,.f2,.f3,.f4
.f1 DC.B    $0D,'   ad______',0
.f2 DC.B    $0D,'   ad______-bd______',0
.f3 DC.B    $0D,'   ad______-bd______-cd______',0
.f4 DC.B    $0D,'   ad______-bd______-cd______-dd______',0

    DS.W    0
s_LongsPrompts:                      ; Form prompts for entering longwords
    DC.L    .p1,.p2,.p3,.p4
.p1 DC.B    'LONGWORD 1',0
.p2 DC.B    'LONGWORD 2',0
.p3 DC.B    'LONGWORD 3',0
.p4 DC.B    'LONGWORD 4',0

s_AbortEdit:
    DC.B    $0D,'...ABORTED -- BUT ANY EDITS UP TO NOW ARE SAVED...',0

s_ResizeForm:                        ; User form for buffer sizing
    DC.B    $0D,'  -- CHANGE BUFFER SIZING --'
    DC.B    $0D,'NOTE--SIZING ONLY AFFECTS THESE BUFFER MANIPULATION COMMANDS.'
    DC.B    $0D,'   LONGWORDS IN SECTOR TAG-aa   IN SECTOR DATA-ba',0

    DS.W    0
s_ResizePrompts:                     ; Form prompts for buffer sizing
    DC.L    .p1,.p2
.p1 DC.B    'TAG LONGWORDS',0
.p2 DC.B    'DATA LONGWORDS',0


sBufferMenu:
    DC.B    'DATA BUFFER',0          ; Menu title
    DC.B    'GO BACK...    1',0
    DC.B    'SHOW CONTENTS 2',0
    DC.B    'EDIT CONTENTS 3',0
    DC.B    'PATTERN FILL  4',0
    DC.B    'RANDOM FILL   5',0
    DC.B    'RESIZE BUFFER 6',0
    DC.B    0                        ; End of menu
    DC.B    $01                      ; Divider after item 1
    DC.B    $05                      ; Divider after item 5
    DC.B    0                        ; No more dividers


** (Back to the code section) **
    SECTION kSecCode



*~Font name~Courier New~
*~Font size~10~
*~Tab type~1~
*~Tab size~4~