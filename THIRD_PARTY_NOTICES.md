# Third-party notices

| Component | Origin | Notice |
|---|---|---|
| `bin/aiswarm` (v2 board implementation, `cmd_*` functions, context/report protocol, tmux session handling) | The `hive` v2 control plane bundled with this configuration as `bin/hive` (header: "License: public domain / CC0. Adapt freely.") | The header notice is carried forward unchanged at the top of the script. The v3 dispatch prelude added to it is covered by `LICENSE` (MIT). |
| `runtime/mock-provider` | Adapted from the `mock` provider case of the same script | Public domain / CC0 as above. |
| snacks.nvim | folke/snacks.nvim, revision pinned in the repository's `lazy-lock.json` | Apache-2.0; not vendored, loaded as a dependency. |

The MIT statement for the Neovim client reproduces the notice previously stated in `doc/hive.txt` ("Plugin license: MIT"). No other third-party code is vendored.
