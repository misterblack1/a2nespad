; nespad.asm: BASIC callable stub
;
; This is the source assembly for NESPAINT DATA statements
;
; Reads NES/SNES controller 1 on the game port, wired exactly like
; PADTEST:
;   LATCH  -> AN0  ($C059 on / $C058 off)
;   CLOCK  -> AN1  ($C05B on / $C05A off)
;   DATA   -> PB2  ($C063 bit7, active LOW)
;
; Result: 8 flag bytes at FLAGS $03C0, one per button, 1 = pressed:
;   $03C0 A   $03C1 B   $03C2 Select  $03C3 Start
;   $03C4 Up  $03C5 Down $03C6 Left   $03C7 Right
; Applesoft basic has no BITWISE operations, so decided to use 8 variables

!cpu 6502

* = $0300

AN0OFF = $C058
AN0ON  = $C059
AN1OFF = $C05A
AN1ON  = $C05B
PB2    = $C063
FLAGS  = $03C0          ; 8 result bytes, must sit clear of this code

read:
        lda   AN0ON     ; LATCH high load the shift register
        lda   AN0OFF    ; LATCH low
        ldx   #0
rd_bit:
        lda   AN1OFF    ; CLOCK low output from shift register
        lda   PB2       ; DATA line bit7 = 1 when NOT pressed
        eor   #$80      ; invert bit7 = 1 when pressed
        asl
        lda   #0
        rol             ; A = 0 or 1
        sta   FLAGS,x   ; store this button's flag
        lda   AN1ON     ; CLOCK high, rising edge shifts to the next button
        inx
        cpx   #8
        bne   rd_bit
        rts             ; back to Applesoft
