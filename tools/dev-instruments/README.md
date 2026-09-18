# Dev instruments — never shipped

These are diagnostic tools that were removed from `mod/` before a release
(Dragón's rule: nothing development-related ships). They are kept here so they
can be dropped back in when a problem needs them.

- **`HookConfig.lua`** (2026-09-17): hook groups for bisecting a crash. Each
  hook-registration site in Indicator/Interaction/Personality/Trust/Combat
  checked `hooks_enabled("<group>")` before calling `RegisterHook`; a group set
  to `false` never registered, which is the only way to "remove" a hook in this
  UE4SS build. It turned the world-change crash hunt into a straight line (see
  CLAUDE.md, pass 330–333). To reuse it, copy the file into `Scripts/` and add
  the gate back at the registration sites you want to split.
- **Profiler, [WON-OVER-SPY], [LEASH-SPY], [PLAYER-SPY]**: removed for 1.1.4.
  All are in git history at the v1.1.3 commit (`bd8e0ca`): `Scripts/Profiler.lua`,
  the spy blocks in `Personality.lua`, `Trust.lua` and `PlayerRef.lua`, and
  `tools/perf/analyze-profile.js` for reading profiler output.
