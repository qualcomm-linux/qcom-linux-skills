# Remoteproc subsystems and thermal zones by SoC

Background for the `qcom-device-diagnostic` skill: which co-processors
(remoteproc instances) and thermal zones a healthy board exposes, so an
operator can tell an expected-missing subsystem from a crashed one.

## Remoteproc instances

Qualcomm SoCs boot several co-processors, each surfaced under
`/sys/class/remoteproc/remoteprocN` with a `name` and a `state`. On a healthy
board every populated instance should read `running`.

| Subsystem | `name` substring | Typical role |
|---|---|---|
| ADSP | `adsp` / `lpass` | Audio, low-power sensors |
| CDSP | `cdsp` | Compute / NPU offload |
| Modem (MPSS) | `mpss` / `modem` | Cellular modem firmware |
| WPSS / WLAN | `wpss` | Wi-Fi/BT co-processor |

Not every SoC populates every instance — a board with no modem simply has no
`mpss` remoteproc, which is expected and not a fault.

## Board / SoC quick reference

The remoteproc set depends on the SoC, not the board, so identify the SoC
first (`qcom-device-info` prints it):

| Board | SoC | Co-processors expected running |
|---|---|---|
| RB3 Gen 2 (`qcs6490-rb3gen2`) | QCS8550 | adsp, cdsp, mpss, wpss |
| IQ-9075-EVK | QCS9075 | adsp, cdsp |
| IQ-8275-EVK | QCS8275 | adsp, cdsp |

If an instance in the "expected running" column reads anything other than
`running`, treat it as a `WARN` and correlate with the dmesg section — a
firmware authentication or load failure prints a `remoteproc ... request_firmware
failed` or `... crash` line at boot.

## Thermal zones

Thermal zones appear under `/sys/class/thermal/thermal_zoneN` with a `type`
(e.g. `cpu-0-0`, `gpu`, `pm8550-*`) and a `temp` in millidegrees Celsius.
Each zone advertises trip points (`trip_point_N_temp`, also millidegrees):
a `passive`/`hot` trip that triggers throttling and a `critical` trip that
triggers an emergency shutdown.

The skill compares each zone's current temperature against its critical trip
and flags a zone at or above it. A board that is merely throttling (above the
passive trip but below critical) is running hot but functional; a board at or
above the critical trip is about to shut down and is a hard failure.
