// Copied from ft8_lib (https://github.com/kgoba/ft8_lib, MIT license) for FT2.
// ft8_lib stays unmodified. Keep this copy in sync with it when ft8_lib is updated.

#ifndef _INCLUDE_FT2_CONSTANTS_H_
#define _INCLUDE_FT2_CONSTANTS_H_

// FT2: same channel structure as FT4 (4-GFSK, 4 Costas blocks, 105 symbols, same LDPC,
// same XOR scrambling and Gray map) at double the baud rate. ~41.67 Hz tone spacing,
// ~167 Hz bandwidth, 3.75 s T/R cycle. Reuses every FT4_* symbol constant of ft8_lib.
// The waterfall is tagged FTX_PROTOCOL_FT4, so ft8_lib decodes FT2 candidates unchanged.
#define FT2_SYMBOL_PERIOD (0.024f) ///< FT2 symbol duration (NSPS 288 @ 12 kHz)
#define FT2_SLOT_TIME     (3.75f)  ///< FT2 slot period

#endif // _INCLUDE_FT2_CONSTANTS_H_
