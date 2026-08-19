# Game projects

Each directory is a self-contained, game-specific fix with its own compatibility notes, technical explanation, release builder, and end-user package contents.

| Project | Mechanism | Use boundary |
|---|---|---|
| [Jurassic World Evolution 3](jurassic-world-evolution-3/README.md) | Verified executable byte patch selecting an existing shader fallback | Supported executable hash only |
| [Kena: Bridge of Spirits](kena-bridge-of-spirits/README.md) | Data-only Unreal Engine PAK | Native DX12 water rendering issue |
| [INAZUMA ELEVEN: Victory Road](inazuma-eleven-victory-road/README.md) | Verified executable byte patch plus reversible firewall isolation | Offline only; uninstall before EAC or online play |
| [The Isle: Evrima](the-isle-evrima/README.md) | Transactional per-user Unreal Engine configuration profile | Steam build 24664737; normal EAC launch; remaining shader stalls documented |

The mechanisms are intentionally not shared blindly between games. A successful fix is promoted only after the affected path has been isolated and verified on real hardware.
