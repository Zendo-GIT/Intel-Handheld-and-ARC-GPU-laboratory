# Technical details

## Symptom

Water surfaces on the affected Intel Arc configuration contained large flashing
polygonal, square and triangular regions that exposed the terrain below. The
shape of the corruption suggested a geometry-generation failure rather than a
texture-only problem.

## Eliminated causes

The following tests did not change the artifact:

- XeSS disabled or changed;
- water quality changes;
- OptiScaler removed from the test path;
- fakenvapi removed from the test path;
- water material LOD, dither, opacity and flat-material variants;
- DirectX 12 and Intel shader-cache resets.

Alt-Tab explained the separately observed stutter and was not the source of the
water corruption.

## Shader evidence

The game shader archive contains both `Win64_SM60` and `Win64_SM65` variants,
including water pool and water volume shaders. The SM65 water path includes mesh
shaders, whereas the SM60 path uses vertex shaders.

The tested water mesh shader already writes zero to `SV_CullPrimitive`, so a
primitive-culling override could not explain or correct the missing regions.

## Engine capability path

JWE3 stores the D3D12 mesh shader tier and derives an internal capability flag.
The mesh shader tier is compared to the tier-one enum value, followed by:

```asm
; JWE3.exe 1.4.2.0, file offset 0x1CB666D
0F 9D C0                setge al
88 87 D9 1C 00 00       mov byte ptr [rdi + 0x1CD9], al
```

The capability byte is subsequently read when the renderer chooses and creates
mesh-shader resources and draw paths.

Release 1.0.0 changes only the three-byte `setge` instruction:

```asm
31 C0                   xor eax, eax
90                      nop
88 87 D9 1C 00 00       mov byte ptr [rdi + 0x1CD9], al
```

The engine therefore observes mesh shaders as unavailable and falls back to its
existing VS/SM60 path. It does not replace a shader or inject new rendering code.

## Integrity values

```text
Original SHA-256:
04FA75D84683DE73AAFF7C0D5C28D8FDC5B4E900E5968022995CF84039F0A79F

Patched SHA-256:
3A172D9261075017974897A2F4EB89F16232B5E5D711B2EA77A524394BD7FAA8
```

The original and patched files have identical size and differ at exactly three
byte positions.

## Result

The water corruption disappeared on the reference Arc 140V system after the
fallback was installed. This validates the workaround on that exact game,
driver and hardware combination; it does not prove every Intel Arc model or
driver is affected in the same way.
