# Nexus Mods release

Recommended metadata:

- Title: **Detroit Become Human Intel Arc Stability Fix**
- Version: **1.0.0**
- Category: **Bug Fixes**
- Installation: **Manual only**

## Short description

Removes Detroit's unsupported-GPU prompt on the supported Steam build, protects
the stable 100% internal-scale rendering path, validates the existing Intel
Vulkan cache without rebuilding or prefetching it, and provides conservative
chapter-only/manual presentation recovery. Optional Steam integration makes the
normal Play button run the optimized path through a locally compiled, reversible
wrapper.

## Required disclosure

The exact Steam executable hash is mandatory. This upload contains no game
executable, shader cache, proprietary asset, DLL or injector. It is not a Vortex
package.

The optional wrapper executable is generated locally during installation and is
not shipped in the archive.

The prompt and graphics-path results are validated on Intel Arc 140V. An earlier
asset-I/O automatic-reset heuristic was removed after false positives. The final
automatic guard responds only to top-level completed chapter progression and
excludes checkpoints and in-game hangs. The manual hotkey remains available. It
does not promise to eliminate every normal scene-loading hitch or long-session
performance decline.

The project includes AI-assisted code and documentation. Do not enter it in an
event whose rules prohibit generative-AI-assisted submissions.
