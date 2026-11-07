# Mini QoL v1.0.2

Fix the repeated `unable to find mixin or metatable (Vector2DMixin)` error from
Wayfinder's player-position lookup during exploration sampling.

- Expose native API return-value mixins directly in each embedded module's Lua
  environment, as required by the client's native lookup. This also covers the
  related vector, color, item and player-location mixins.
- Add a regression test that reproduces the original error, checks repeated
  player-position sampling and verifies unavailable positions and optional
  client mixins.

Upgrade by replacing the `MiniQoL` addon folder with the folder from
`MiniQoL-1.0.2.zip`, then reload the UI. Existing saved settings are preserved.
For a first installation, move only the standalone `Peddler`, `Gearwise`,
`Wayfinder` and `XPCounter` folders outside `AddOns`; keep all other addons.

The release includes the installable ZIP, complete source ZIP and SHA-256
checksums, with clean defaults and the existing license and attribution notices.

Validation: the original failure was reproduced before the fix and the new
regression passes afterward. Existing scope, settings, UI and NPC dialogue
checks pass; 58 Lua files compile and all selected source references resolve.
In-game verification remains pending.
