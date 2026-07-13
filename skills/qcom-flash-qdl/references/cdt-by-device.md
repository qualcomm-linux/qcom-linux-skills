# CDT Configuration by Device

The Configuration Data Table (CDT) contains device-specific initialization
data required for platform bring-up. Select and flash the correct CDT before
flashing the main image.

---

## IQ-X7181-EVK / IQ-X5121-EVK

The CDT is a separate download and must be flashed before the main image.
Run these commands from a working directory outside the flash bundle:

```bash
curl -O https://artifacts.codelinaro.org/artifactory/codelinaro-le/Qualcomm_Linux/X1E80100/cdt/IQ-X.1.4-EVK-CDT.tar.gz
tar -xzf IQ-X.1.4-EVK-CDT.tar.gz
cd IQ-X.1.4-EVK-CDT

qdl --storage spinor xbl_s_devprg_ns.melf rawprogram0_BLANK_GPT.xml
qdl --storage spinor xbl_s_devprg_ns.melf rawprogram0_WIPE_PARTITIONS.xml
qdl xbl_s_devprg_ns.melf rawprogram0.xml patch0.xml
```

Return to the image directory after this completes.

---

## QCS6490 / IQ-9075-EVK / IQ-8275-EVK / IQ-615-EVK

Multiple CDT binaries ship inside the qcomflash bundle. Copy the correct one
over `cdt.bin` before running `qdl`:

```bash
cp <cdt-variant>.bin cdt.bin
```

CDT subtype lookup for QCS6490 kits:

| Subtype | Platform Description                    |
|---------|-----------------------------------------|
| 2       | Vision Kit (Moselle attach)             |
| 5       | RB3Gen2 Core Kit (HSP attach)           |
| 6       | RB3Gen2 Core Kit (Moselle attach)       |
| 7       | Vision Kit (HSP attach)                 |
| 13      | Industrial Mezz Kit                     |

### Verify after flashing

Check the UEFI serial log (via UART) for the Subtype field:

```
Platform Init [ 1966] BDS
Platform : IOT
Subtype : 2
Boot Device : UFS
Chip Name : QCS6490
```

The Subtype must match the table above for the kit in use.
