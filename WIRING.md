# Wiring an NES or SNES controller to the Apple II game port

The controller plug into the motherboard's 16-pin game port and the 6502 clocks
it directly. Works on the Apple II/II+/IIe/IIgs. 

You can use an external 9-pin analog joystick at the same time.

### WARNING:
- The Shift-Lowercase mod on the Apple II/II+ uses PB2 (pin 4 on the DIP-16) so DO NOT connect up a NES/SNES controller if your machine has this mod. (Your controller might be damaged.)
- On the Apple IIe, shorting jumper X6 on the motherboard enables the shift-lowercase mod. The same warning applies.
- Add a 10K resistor inline with PB2 (pin 4) if you want to ensure any Shift-Mod won't potentially damage to your controller.

## Why this works

An NES or SNES controller is a 4021 parallel-in serial-out shift register in a
plastic shell. It needs three signals and power:

- **LATCH**, a pulse that loads the button states into the register
- **CLOCK**, one edge per button to shift the next bit out
- **DATA**, the serial output, one button per clock

The Apple II game port has two annunciator outputs the CPU can toggle from
software and four digital inputs it can read. This is what the controller needs and 
talks to the machine with nothing in between.

## The game port socket

16-pin DIP on the motherboard of the II, II+, IIe, and IIgs. Looking down at
the socket with the notch at the bottom:

```
         +-------------+
     9  o|             |o  8         9  Pushbutton 3 (IIgs only)   8  Ground
    10  o|             |o  7        10  Game Controller 1          7  Game Controller 2
    11  o|             |o  6        11  Game Controller 3          6  Game Controller 0
    12  o|             |o  5        12  Annunciator 3              5  /C040 Strobe
    13  o|             |o  4        13  Annunciator 2              4  Pushbutton 2
    14  o|             |o  3        14  Annunciator 1              3  Pushbutton 1
    15  o|             |o  2        15  Annunciator 0              2  Pushbutton 0
    16  o|    notch    |o  1        16  No Connection              1  +5V Power
         +------v------+
```

## Connections

Two controllers share LATCH and CLOCK. Each gets its own DATA line, so one
latch-and-clock sweep reads both pads at once.

| Signal | Apple pin | Soft switch | Notes |
| --- | --- | --- | --- |
| LATCH, both pads | 15, Annunciator 0 | `$C059` on, `$C058` off | output |
| CLOCK, both pads | 14, Annunciator 1 | `$C05B` on, `$C05A` off | output |
| DATA, pad 1 | 4, Pushbutton 2 | `$C063` bit 7 | input, active low |
| DATA, pad 2 | 9, Pushbutton 3 | `$C060` bit 7 | input, active low |
| +5V | 1 | | |
| Ground | 8 | | |

### Do not use PB0 or PB1, notes on PB3

Pushbutton 0 (`$C061`) and Pushbutton 1 (`$C062`) double as the Open Apple and
Closed Apple keys on some machines. Using these inputs could damage the shift
register depending on conditions. That is why PB2 and PB3 are used.

Pad 2 uses PB3 also known as the cassette input. On the II/II+/IIe Apple used
PB3 input for the cassette. The audio signal is shaped via an Op-Amp and fed
into PB3 input via a 12k resistor. Pin 9 on the joystick connector is not
connected on these machines so to use a second controller, you need to add a
jumper wire from the Data 0 on the controller to the side of the 12k resistor
that facing the PB3 input. 


## Timing

`snes-reading.png` in this repo is the scope capture the timing came from.

- CLOCK idles **high**
- LATCH idles **low** and pulses high for 12us, and that pulse sits inside
  clock-high
- 6us after latch falls, CLOCK drops for the first of 16 pulses, 12us period,
  50 percent duty
- The pad shifts on the clock's **rising** edge, the console samples on the
  **falling** edge

So the read loop is `{clock low, sample, clock high}` and it leaves the clock
high between reads. The code here follows that shape. The Apple II is slower
than a real console and the 4021 has no minimum clock rate, so the pad does
not care that the 6502 takes longer between edges.

Reading the controllers work on a IIgs in 2.8mhz FAST mode. The controllers
have not been tested on any other accelerated Apple II machines.

## Polarity

The buttons sit at a 10k pull-up and short to ground when pressed. **On the
wire, low means pressed.**

Every NES and SNES document instead quotes what the console's register shows,
and the console inverts. So "1 = pressed" and "signature = 0000" in the
documentation are the opposite of what you sample here. Translated to raw wire
levels:

- **NES**: 8 button bits, then the 4021's grounded serial input shifts in
  zeros, so bits 8 through 16 read low.
- **SNES**: 12 button bits, then 4 unused parallel inputs sit at their
  pull-ups, so bits 12 through 15 read high, then the grounded serial input
  makes bit 16 low. Third-party pads hold that tail high instead.

## Button order

NES shifts 8 bits, most significant first:

```
A  B  Select  Start  Up  Down  Left  Right
```

SNES shifts 16:

```
B  Y  Select  Start  Up  Down  Left  Right  A  X  L  R  then 4 signature bits
```

Clone controllers often shift more bits, but the order is the same so they will
work.

## Is this safe for the Apple?

The code only drives the motherboard's annunciator outputs and reads the
Pushbutton 2 and cassette inputs. This was all an intended use of the DIP-16 joystick
port, so it hardless. 
