# Entering EDL mode, per board

Emergency Download (EDL) mode is the SoC's ROM-level recovery/flash mode.
A board in EDL enumerates on USB as VID:PID `05c6:9008` (check with
`lsusb -d 05c6:9008`). How to get there differs per board; when a board is
not listed here, follow the "flash images" section of its Quick Start Guide
on <https://docs.qualcomm.com> (Dragonwing boards:
<https://dragonwingdocs.qualcomm.com>).

## RB3 Gen 2 (rb3gen2-core-kit / qcs6490-rb3gen2-core-kit)

From meta-qcom `docs/flashing.md` and the RB3 Gen 2 Quick Start Guide:

1. Set `DIP_SW_0` positions `1` and `2` to `ON` — this enables serial
   output on the debug port (115200 baud).
2. Press and hold the `F_DL` button **before** connecting the power cable;
   keep holding until the power is on.
3. Connect the USB-C cable to the host and check `lsusb -d 05c6:9008`.

## Common patterns on other boards

- **Force-DL button/switch**: most development boards (RB1, IDP, EVK
  variants) have an `F_DL`/`EDL` button or DIP switch that must be held or
  set while power is applied — the exact label and location is in the
  board's Quick Start Guide.
- **From a running system**: if the board still boots, a reboot into EDL
  can often be triggered from software (e.g. `reboot edl` on images that
  support it). Only rely on this when the button method is inaccessible.
- **Board farms / automation**: lab setups usually drive EDL and power via
  a control channel (relay board, automation console). Keep such site
  specifics in a local wrapper; this skill only assumes the board is
  already reachable in EDL.

## Verifying and leaving EDL

- Verify: `lsusb -d 05c6:9008` shows the device; with several boards, get
  each serial via `lsusb -v -d 05c6:9008 | grep iSerial`.
- Leave: after flashing, release any DL switch/button and power-cycle the
  board so it boots normally from the freshly flashed storage.
