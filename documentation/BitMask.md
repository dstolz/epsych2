# epsych.BitMask

`epsych.BitMask` is a MATLAB `uint32` enumeration that assigns *named flags* (e.g., `Hit`, `Reward`, `ResponseWindow`) to *bit indices*.

In the current file, the defined bit indices run from `1` to `31`, plus a special `Undefined (0)` value.

A bitmask is a single integer where each bit position means “this flag was set.” For example, a mask might mean “Hit + Reward + ResponseWindow”.

## Quick start

### Create a mask from flags

```matlab
% Build a mask from bit positions (recommended)
mask = epsych.BitMask.Bits2Mask(uint32([epsych.BitMask.Hit epsych.BitMask.Reward]));

% mask is a uint32 integer suitable for saving into trial data
```

### Decode masks back into named fields

```matlab
responseCodes = uint32([0 2^0 2^5]);  % example integer masks
M = epsych.BitMask.decode(responseCodes);

% M is a struct of logical arrays, one field per defined flag
% Example: M.Hit(i) tells you whether responseCodes(i) had the Hit bit set
```

### Launch the bitmask builder GUI

```matlab
% Interactive helper to toggle flags and copy an integer mask
fig = epsych.BitMask.GUI();

% Or pre-load an existing mask
fig = bitmask_gui(InitialMask=uint32(2626));
```

## Enumeration values (bit indices)

Each enumeration value is a *bit index* (1-based), not a power-of-two value.

Example: if `Hit` is defined as `(1)`, it refers to bit position 1, and its numeric contribution to a mask is $2^{1-1} = 1$.

To list all names and indices:

```matlab
epsych.BitMask.list();
```

Or to programmatically retrieve them:

```matlab
[names, values] = epsych.BitMask.list();   % names: cellstr, values: uint32 bit indices
```

## Common workflows

### 1) From a set of flags → integer mask

Use `Bits2Mask` and pass a vector of bit positions (often easiest by passing the enum values):

```matlab
flags = [epsych.BitMask.Hit epsych.BitMask.Reward epsych.BitMask.ResponseWindow];
mask = epsych.BitMask.Bits2Mask(uint32(flags));
```

Notes:
- `Bits2Mask` accepts either a binary vector (0/1) *or* a vector of bit positions.
- Bit positions must be in the range `1..32` (although `epsych.BitMask` itself currently defines names only up to bit `31`).

### 2) From integer mask(s) → active flags

Use `Mask2Bits`:

```matlab
mask = uint32([0 1 3 14]);
[bits, activeFlags] = epsych.BitMask.Mask2Bits(mask);

% bits is [numel(mask) x nbits] with the least-significant bit in column 1
% activeFlags is a cell array: one epsych.BitMask array per element in mask
```

Notes:
- `Mask2Bits` accepts `mask` arrays of any shape; `bits` is always returned as `[numel(mask) x nbits]`.
- When you request the second output, `activeFlags` is reshaped to the same size as `mask`.

If you only need a limited number of bits:

```matlab
bits = epsych.BitMask.Mask2Bits(mask, 10);   % only return bits 1..10
```

### 3) From integer mask(s) → a struct of named logical arrays

Use `decode`:

```matlab
responseCodes = uint32([0 1 3 14]);
[M, N] = epsych.BitMask.decode(responseCodes);

% M.<FlagName> is a logical vector
% N.<FlagName> is the count of set bits across all responseCodes
```

This is often the most convenient representation for analysis.

## API reference

### Display / listing

- `disp(obj)`
  - Prints a two-column table: bit index and name for each enum in `obj`.

- `[names, values] = epsych.BitMask.list()`
  - Returns all enumeration names and their bit indices.
  - If called with no outputs, prints the list.

### GUI

- `f = epsych.BitMask.GUI()`
  - Launches the interactive bitmask builder (calls `bitmask_gui`).

### Group helpers

These return subsets of the enumeration (as `epsych.BitMask` arrays):

- `getResponses()`
- `getContingencies()`
- `getResponsePeriod()`
- `getTrialTypes()`
- `getChoices()`
- `getOptions()`
- `getDefined()` (all defined flags except `Undefined`)
- `getAll()` (includes `Undefined`)

### Validation

- `tf = isValidValue(val)`
  - Returns `true` if `val` exactly matches one of the enum values (bit indices).

### Conversions

- `[bits, BM] = Mask2Bits(mask, nbits)`
  - Input: `mask` is an integer vector of non-negative values (the current implementation validates `mask` as a 1-by-N row vector).
  - Output:
    - `bits`: a logical array of size `[numel(mask), nbits]`, where column 1 is bit 1 (LSB).
    - `BM` (optional): a cell array containing the active `epsych.BitMask` flags for each element.

- `mask = Bits2Mask(bits, dim)`
  - If `bits` is a 0/1 vector, it is treated as a binary representation with the LSB at index 1.
  - If `bits` is a vector of positive integers, it is treated as bit positions.
  - If `bits` is a matrix, `dim` selects whether rows (`dim=1`) or columns (`dim=2`) represent independent masks.

### Decoding

- `[M, N] = decode(responseCodes)`
  - Builds a struct `M` with one field per defined flag (excluding `Undefined`).
  - Each field is a logical array indicating which codes have that bit set.
  - If requested, `N` is a struct of counts (sum of `true` in each field).

## Gotchas / notes

- **Enum values are bit indices.** The enumeration stores positions (e.g., `Hit = 1`), not powers of two.
- **`Undefined (0)` is not a bit position.** It is a sentinel value; `getDefined()` excludes it.
- **Bit order in vectors:** `Mask2Bits` and `Bits2Mask` use “LSB in column 1”. A binary vector `[0 1 1 1 0]` corresponds to bits 2–4 being set.
- **Enum name typo:** the enum includes `OPtion_H` (capital `P`). This is a real enum member name, so the decoded struct field will also be `M.OPtion_H`.

## Related files

- `helpers/bitmask_gui.m` — interactive UI to build/copy masks using `epsych.BitMask`.

## Changelog

- 2026-03-17: Updated docs to match the current `Mask2Bits` shape behavior and the corrected group helper ranges.
