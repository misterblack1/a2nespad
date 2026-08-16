; Apple II two-controller NES/SNES detect and read test
; Loads at $0800 (BRUN)
; ACME syntax (!cpu 6502, * = $0800
;
; ---------------------------------------------------------------------------
;  APPLE 16-pin DIP GAME PORT socket
;  Available on Apple II, II+, IIe, IIGS
;
;         +-------------+
;     9  o|             |o  8         9  Pushbutton 3 (IIGS only)   8  Ground
;    10  o|             |o  7        10  Game Controller 1 (pdl)    7  Game Controller 2
;    11  o|             |o  6        11  Game Controller 3          6  Game Controller 0
;    12  o|             |o  5        12  Annunciator 3              5  /C040 Strobe
;    13  o|             |o  4        13  Annunciator 2              4  Pushbutton 2
;    14  o|             |o  3        14  Annunciator 1              3  Pushbutton 1
;    15  o|             |o  2        15  Annunciator 0              2  Pushbutton 0
;    16  o|    notch    |o  1        16  No Connection              1  +5V Power
;         +------v------+
;
;  Two controllers, both share the LATCH and CLOCK lines and each
;  drives its own DATA line.
;  This program drives AN0/AN1 and reads two inputs:
;    both LATCH -> pin 15 Annunciator 0 (AN0)  $C058 off / $C059 on
;    both CLOCK -> pin 14 Annunciator 1 (AN1)  $C05A off / $C05B on
;    pad 1 DATA0 -> pin 4 Pushbutton 2 (PB2)  $C063 bit7 (D3) active LOW
;    pad 2 DATA0 -> pin 9 (IIgs) or cassette input  $C060 bit7 (D0) via op-amp
;    +5V -> pin 1, GND -> pin 8
;
;  PB0 ($C061) and PB1 ($C062) double as the IIe Open/Closed Apple keys, so a
;  controller wired to those lines fights the keyboard and could damage the shift register.
;
;  PB2 ($C063) is unused and free to use for controller 1. 
;  PB3 ($C060) is unused and available on the IIgs for controller 2. On the II/II+/IIe it is
;  used for the cassette input, where an op-amp feeds the the input via a 12k resistor. Connect
;  the controller data line after the resistor, as the shift register can easily override the output
;  from the op-amp which is going through that resistor. This is the left side of R20 on the
;  Apple IIe. See schematics for more info on the Apple II/II+. 
;
;  Both shift registers latch and clock in parallel. On every clock we sample
;  both data lines, so one latch/clock sweep reads both pads at once.
;
; NES shift order (MSB first): A B Select Start Up Down Left Right
; SNES shifts 16: B Y Sel Start U D L R A X L R, then a 4-bit signature, then a tail.
; Some clone controllers act differently, so don't rely on the auto detection in games.
;
;  DATA LINE POLARITY:
;  The one thing that makes the SNES look "missing", both pads are 4021 shift registers
;  whose parallel inputs sit at a 10k pull-up and are shorted to ground by a button.
;
;    NES  : 8 button bits, then the 4021 serial input (grounded) shifts in 0s
;           -> bits 8..16 read LOW.
;    SNES : 12 button bits, then 4 unused parallel inputs left at their pull-ups
;           -> bits 12..15 read HIGH, then the grounded serial input -> bit 16
;           LOW. Third-party pads hold the tail HIGH instead.
;

!cpu 6502

* = $0800

; ---- Apple II monitor ROM ----
COUT   = $FDED
HOME   = $FC58
VTAB   = $FC22          ; set text base line from CV
CH     = $0024          ; cursor column
CV     = $0025          ; cursor row
KBD    = $C000
STROBE = $C010

; ---- game-port soft switches ----
AN0OFF = $C058
AN0ON  = $C059
AN1OFF = $C05A
AN1ON  = $C05B
PB2    = $C063          ; pad 1 DATA line (D3)
CASSIN = $C060          ; pad 2 DATA line (D0)

strptr = $06            ; $06/$07 string pointer
bufptr = $08            ; $08/$09 raw-bit buffer pointer (D3 dest + classify ptr)
bufptr2 = $F0           ; $F0/$F1 second raw-bit buffer pointer (D0 dest)
ptype  = $EB            ; D3 pad: 0=NONE 1=NES 2=SNES 3=IDLE/UNKNOWN
ptype2 = $EF            ; D0 pad: same encoding
psidx  = $EC            ; pstr index (reloaded each char)
tmp    = $ED
tmp2   = $EE

padbits  = $06FC        ; D3 decoded NES buttons (pressed=1, MSB-first)
padbits2 = $06FD        ; D0 decoded NES buttons
raw1     = $0300        ; D3 raw 17 bits, read #1
raw2     = $0320        ; D3 raw 17 bits, read #2 (consistency check)
rawc     = $0340        ; D0 raw 17 bits, read #1
rawc2    = $0360        ; D0 raw 17 bits, read #2 (consistency check)

; =====================================================================
start:
        lda   AN0OFF        ; power-on annunciator state is undefined: park the
        lda   AN1ON         ; lines where a real console idles, LATCH low CLOCK high
        jsr   HOME
        jsr   setrow0       ; NOTE: clobbers A/Y (VTAB), must run BEFORE the
        lda   #<hdr         ; string pointer is loaded, not after
        ldy   #>hdr
        jsr   pstr          ; header on row 0
        lda   #0
        sta   ptype         ; both ports start NONE -> first detect classifies both
        sta   ptype2

mloop:
        jsr   detect        ; refresh raw buffers, classify UNLOCKED ports
        jsr   read_nes      ; live 8-button read of BOTH pads -> padbits, padbits2
        jsr   show
        lda   KBD
        cmp   #$9B          ; ESC ?
        bne   mloop
        bit   STROBE
        jmp   $03D0         ; exit

; =====================================================================
; read_nes : latch, then 8 clocks. Each clock samples BOTH DATA lines and
;   shifts them (inverted -> pressed=1) into padbits (D3) and padbits2 (D0).
read_nes:
        lda   AN0ON         ; AN0 high -> LATCH (parallel-load both pads). CLOCK
        lda   AN0OFF        ; AN0 low is already high, so the pulse sits in it
        lda   #0
        sta   padbits
        sta   padbits2
        ldx   #8
rn_bit: lda   AN1OFF        ; CLOCK low -> the console's sample point
        lda   PB2           ; pad 1 DATA (0 = pressed)
        eor   #$80          ; invert -> bit7: 1 = pressed
        asl                 ; pressed -> carry
        rol   padbits       ; shift in MSB-first (A->$80 ... Right->$01)
        lda   CASSIN        ; pad 2 DATA (0 = pressed)
        eor   #$80
        asl
        rol   padbits2
        lda   AN1ON         ; CLOCK high -> rising edge shifts to the next button,
        dex                 ; and leaves the line idling high when the loop ends
        bne   rn_bit
        rts

; =====================================================================
; detect : refresh raw buffers for both ports (17 bits, twice each), then for
;   each port that is NOT already locked to NES/SNES, require the two reads to
;   match and classify. Locked ports keep their prior type (so releasing all
;   buttons does not drop a known NES pad back to IDLE).
detect:
        lda   #<raw1        ; read #1: raw1 <- D3, rawc <- D0
        sta   bufptr
        lda   #>raw1
        sta   bufptr+1
        lda   #<rawc
        sta   bufptr2
        lda   #>rawc
        sta   bufptr2+1
        jsr   read17
        lda   #<raw2        ; read #2: raw2 <- D3, rawc2 <- D0
        sta   bufptr
        lda   #>raw2
        sta   bufptr+1
        lda   #<rawc2
        sta   bufptr2
        lda   #>rawc2
        sta   bufptr2+1
        jsr   read17

        ; --- port D3 ---
        lda   ptype
        cmp   #1            ; already locked NES?
        beq   d0port
        cmp   #2            ; already locked SNES?
        beq   d0port
        ldx   #17          ; consistency: real static shift register reads twice alike
d3cmp:  lda   raw1-1,x
        cmp   raw2-1,x
        bne   d3none
        dex
        bne   d3cmp
        lda   #<raw1
        sta   bufptr
        lda   #>raw1
        sta   bufptr+1
        jsr   classify
        sta   ptype
        jmp   d0port
d3none: lda   #0
        sta   ptype

        ; --- port D0 ---
d0port:
        lda   ptype2
        cmp   #1
        beq   ddone
        cmp   #2
        beq   ddone
        ldx   #17
d0cmp:  lda   rawc-1,x
        cmp   rawc2-1,x
        bne   d0none
        dex
        bne   d0cmp
        lda   #<rawc
        sta   bufptr
        lda   #>rawc
        sta   bufptr+1
        jsr   classify
        sta   ptype2
        jmp   ddone
d0none: lda   #0
        sta   ptype2
ddone:  rts

; =====================================================================
; classify : bufptr -> 17 raw bytes (0/1). Returns A = type
;   0 NONE / 1 NES / 2 SNES / 3 IDLE.
classify:
        ; --- SNES?  raw bits 12,13,14,15 all == 1 (the 4 unused 4021 parallel
        ; inputs float at their pull-ups. The console inverts them, which is why
        ; the docs call this signature "0000") ---
        ldy   #12
        lda   (bufptr),y
        iny
        and   (bufptr),y
        iny
        and   (bufptr),y
        iny
        and   (bufptr),y
        beq   cl_nes         ; a 0 in the nibble -> not SNES
        ldy   #16
        lda   (bufptr),y
        beq   cl_snes        ; tail LOW -> official pad, grounded serial input
        ; Tail HIGH. Either a third-party pad (they hold the tail high) or a
        ; floating input with nothing plugged in. A pressed button (a 0 in the
        ; 12 button bits) is what tells those two apart.
        ldy   #0
        ldx   #12
cl_s12: lda   (bufptr),y
        beq   cl_snes
        iny
        dex
        bne   cl_s12
        lda   #3             ; all 17 bits high -> can't tell yet
        rts
cl_snes:
        lda   #2
        rts
cl_nes:
        ; NES?  bits 8..16 all == 0 (real HW: shift-register output past the
        ; 8 valid bits reads LOW
        ldy   #8
        ldx   #9
cl_tl:  lda   (bufptr),y
        bne   cl_none        ; a 1 in the tail -> not the NES fingerprint
        iny
        dex
        bne   cl_tl
        ; tail all-0 -> idle NES pad OR open port. ANY 1 among the first 8 bits
        ; proves a live 4021 -> NES. All-0 first-8 stays ambiguous -> IDLE.
        ldy   #0
        ldx   #8
cl_fb:  lda   (bufptr),y
        bne   cl_nesok
        iny
        dex
        bne   cl_fb
        lda   #3             ; IDLE/UNKNOWN: release all buttons to disambiguate
        rts
cl_nesok:
        lda   #1
        rts
cl_none:
        lda   #0
        rts

; =====================================================================
; read17 : latch, then 17x (sample both DATA lines -> bufptr / bufptr2, clock).
;   Raw PB2 bit7 -> (bufptr),y , raw CASSIN bit7 -> (bufptr2),y (NOT inverted).
read17:
        lda   AN0ON          ; LATCH high (CLOCK is already idling high)
        lda   AN0OFF         ; LATCH low
        ldy   #0
r17:    lda   AN1OFF         ; CLOCK low -> sample point
        lda   PB2            ; pad 1 DATA (D3)
        asl                  ; bit7 -> carry
        lda   #0
        rol                  ; A = raw bit (0/1)
        sta   (bufptr),y
        lda   CASSIN         ; pad 2 DATA (D0)
        asl                  ; bit7 -> carry
        lda   #0
        rol                  ; A = raw bit (0/1)
        sta   (bufptr2),y
        lda   AN1ON          ; CLOCK high -> rising edge shifts to the next bit
        iny
        cpy   #17
        bne   r17
        rts

; =====================================================================
; show : per port a type line, raw-17 line, an ORDER legend for that pad type,
; and the decoded button line.
show:
        ; ---- PAD 1 / D3 ----
        lda   #3
        jsr   setrow
        lda   #<s_pad1
        ldy   #>s_pad1
        jsr   pstr           ; "PAD1 D3(PB2): "
        lda   ptype
        jsr   ptname         ; padded type name

        lda   #4
        jsr   setrow
        lda   #<s_raw
        ldy   #>s_raw
        jsr   pstr           ; "  RAW: "
        lda   #<raw1
        ldy   #>raw1
        jsr   praw

        lda   #5
        jsr   setrow
        lda   ptype
        jsr   pord           ; ORDER legend for this pad type

        lda   #6
        jsr   setrow
        lda   #<s_btn
        ldy   #>s_btn
        jsr   pstr           ; "  BTN: "
        lda   padbits
        jsr   pbtn

        ; ---- PAD 2 / D0 ----
        lda   #9
        jsr   setrow
        lda   #<s_pad2
        ldy   #>s_pad2
        jsr   pstr           ; "PAD2 D0(CAS): "
        lda   ptype2
        jsr   ptname

        lda   #10
        jsr   setrow
        lda   #<s_raw
        ldy   #>s_raw
        jsr   pstr
        lda   #<rawc
        ldy   #>rawc
        jsr   praw

        lda   #11
        jsr   setrow
        lda   ptype2
        jsr   pord

        lda   #12
        jsr   setrow
        lda   #<s_btn
        ldy   #>s_btn
        jsr   pstr
        lda   padbits2
        jmp   pbtn           ; tail-call

; ptname : A = type index (0..3) -> print padded type name.
ptname:
        asl
        tax
        lda   tnames,x
        ldy   tnames+1,x
        jmp   pstr           ; tail-call: pstr rts returns to show

; pord : A = type index -> print the button order this pad actually shifts.
;   The first 8 bits are A B on a NES pad but B Y on a SNES pad.
pord:   cmp   #2
        beq   po_snes
        lda   #<s_ord
        ldy   #>s_ord
        jmp   pstr
po_snes:
        lda   #<s_ords
        ldy   #>s_ords
        jmp   pstr

; praw : A=lo Y=hi -> 17 raw bytes, print each as '0'/'1'.
praw:   sta   bufptr
        sty   bufptr+1
        ldy   #0
pr1:    lda   (bufptr),y
        clc
        adc   #'0'           ; 0/1 -> '0'/'1'
        ora   #$80
        sty   tmp            ; COUT clobbers Y
        jsr   COUT
        ldy   tmp
        iny
        cpy   #17
        bne   pr1
        rts

; pbtn : A = 8-button bitmap (bit7=A ... bit0=RT), pressed=1. 4-char fields.
pbtn:   sta   tmp2
        lda   #8
        sta   tmp
pb1:    asl   tmp2           ; bit7 first (A), pressed=1 -> carry
        lda   #'X'
        bcs   pbp
        lda   #'.'
pbp:    ora   #$80
        jsr   COUT
        lda   #$A0           ; ' '
        jsr   COUT
        jsr   COUT
        jsr   COUT
        dec   tmp
        bne   pb1
        rts

; =====================================================================
; helpers
setrow0:
        lda   #0
setrow:                       ; A = row -> cursor to (row,0)
        sta   CV
        jsr   VTAB
        lda   #0
        sta   CH
        rts

; print string : print $00-terminated ASCII string, A=lo Y=hi. ORs $80 for COUT,
; reloads its index each char (COUT clobbers Y).
pstr:   sta   strptr
        sty   strptr+1
        lda   #0
        sta   psidx
ps1:    ldy   psidx
        lda   (strptr),y
        beq   ps2
        ora   #$80
        jsr   COUT
        inc   psidx
        bne   ps1
ps2:    rts

; =====================================================================
; strings
hdr:    !text "NES/SNES 2-PAD TEST   ESC=QUIT", 0
s_ord:  !text "ORDER: A   B   SEL STA UP  DN  LF  RT", 0
s_ords: !text "ORDER: B   Y   SEL STA UP  DN  LF  RT", 0
s_pad1: !text "PAD1 D3(PB2): ", 0
s_pad2: !text "PAD2 D0(CAS): ", 0
s_raw:  !text "  RAW: ", 0
s_btn:  !text "  BTN: ", 0
t_none: !text "NONE - NO SHIFT REGISTER", 0
t_nes:  !text "NES PAD                 ", 0
t_snes: !text "SNES PAD                ", 0
t_idle: !text "IDLE - PRESS OR RELEASE ", 0
tnames: !word t_none, t_nes, t_snes, t_idle
