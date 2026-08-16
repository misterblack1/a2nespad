# Using NES and SNES controllers on the Apple II

The controller plug into the motherboard's 16-pin game port and the 6502 clocks
it directly. Works on the Apple II/II+/IIe/IIgs. 

You can use an external 9-pin analog joystick at the same time.

This allows two NES/SNES controllers at once, on any Apple II, II+, IIe, or IIgs.

`WIRING.md` has the pinout, the timing, and the one polarity gotcha that makes
an SNES pad look like it is not there.

## What is here

| File | What it is |
| --- | --- |
| `nespad_dos33.dsk` | bootable DOS 3.3 disk, ready for a floppy or an emulator, carries `PADTEST` and `NESPAINT` ready to run |
| `padtest.asm` | two-controller detect and read test, 6502 source |
| `padtest.bin` | assembled, the `PADTEST` file on the disk |
| `nespad.asm` | the 32-byte reader that Applesoft calls, 6502 source |
| `nespad.bin` | assembled, and the source of the `DATA` bytes below |
| `nespaint.bas` | NES Paint, a lo-res paint program driven by the pad, the readable listing |
| `snes-reading.png` | scope capture of a real console reading a pad |


## Running it

Boot the DOS 3.3 `nespad_dos33.dsk` disk. The greeting names the two programs.

```
BRUN PADTEST
```

Shows both ports live. Per port you get a detect line naming the pad type, the
raw 17-bit pattern coming off the wire, an order legend for that pad type, and
a decoded 8-button state line. Press buttons and watch it move. ESC quits.

This is the program to run first, because it answers "is the wiring right"
before anything else can go wrong.

```
RUN NESPAINT
```

NES Paint. Move the cursor with the d-pad, A paints, B erases, Select cycles
the color, Start clears the screen. Lo-res, 40x40, one controller.

## How the paint program reads the pad

Applesoft cannot bit-bang a shift register at any useful speed. The pad itself
would not mind, as a 4021 has no minimum clock rate, but seventeen interpreted
PEEK and POKE statements is a waste of time.

So the reader is 32 bytes of machine code at `$0300`, in page 3 where DOS
leaves room. `nespaint.bas` POKEs it there from `DATA` statements, calls it
with `CALL 768`, and then reads eight flag bytes back out of `$03C0` through
`$03C7`, one per button, 1 meaning pressed:

| Address | Button | | Address | Button |
| --- | --- | --- | --- | --- |
| `$03C0` (960) | A | | `$03C4` (964) | Up |
| `$03C1` (961) | B | | `$03C5` (965) | Down |
| `$03C2` (962) | Select | | `$03C6` (966) | Left |
| `$03C3` (963) | Start | | `$03C7` (967) | Right |

That is the whole interface. Any Applesoft program can use it by POKEing the
same 32 bytes and calling them. `nespad.asm` is the readable source for those
bytes.

## Building

Requires ACME 0.97.1 (the visrealm fork). Assemble from this directory:

```
acme -f apple -o padtest.bin padtest.asm
acme -f apple -o nespad.bin nespad.asm
```

`-f apple` emits the DOS 3.3 binary header, load address and length, both
little-endian, so nothing needs post-processing. The "Using oversized
addressing mode" warnings are benign, ACME is picking a 3-byte absolute where a
2-byte zero page form would fit. Any other warning is real.

Prebuilt binaries are already here, so ACME is only needed if you change
something.


## Notes

- Both pads are latched and clocked together and sampled on the same edge, so
  reading two controllers costs one sweep, not two.
- The reader does not debounce and does not need to. The pad is sampled once
  per frame of the caller's own loop, and the paint program tracks the previous
  state of Select and Start itself so a held button does not repeat.


## Status

Tested on an Apple II+, Apple IIe and Apple IIgs. 

## License

Public domain, under the Unlicense. See `LICENSE`. Do whatever you want with
it, no attribution required.
