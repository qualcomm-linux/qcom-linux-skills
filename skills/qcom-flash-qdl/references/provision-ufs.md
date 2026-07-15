# Provision UFS by Device

> Not applicable for IQ-615-EVK (EMMC storage only).

UFS provisioning divides storage into LUNs. Run before the first flash, or
whenever the LUN layout changes. Safe to re-run on an already-provisioned device.

## Download provision file

```bash  QCS6490
wget https://artifacts.codelinaro.org/artifactory/codelinaro-le/Qualcomm_Linux/QCS6490/provision.zip
```

```bash  IQ-9075-EVK
wget https://artifacts.codelinaro.org/artifactory/codelinaro-le/Qualcomm_Linux/QCS9100/provision.zip
```

```bash  IQ-8275-EVK
wget https://artifacts.codelinaro.org/artifactory/codelinaro-le/Qualcomm_Linux/QCS8300/provision.zip
```

```bash  IQ-X7181-EVK / IQ-X5121-EVK
wget https://artifacts.codelinaro.org/artifactory/codelinaro-le/Qualcomm_Linux/X1E80100/provision_default.zip
```

## Extract and enter directory

```bash
unzip provision.zip -d provision
cd provision
```

## Run provisioning

```bash  QCS6490
qdl --storage ufs prog_firehose_ddr.elf provision_1_3.xml
```

```bash  IQ-9075-EVK
qdl --storage ufs prog_firehose_ddr.elf provision_1_2.xml
```

```bash  IQ-8275-EVK
qdl --storage ufs prog_firehose_ddr.elf provision_1_3.xml
```

```bash  IQ-X7181-EVK / IQ-X5121-EVK
qdl --storage ufs xbl_s_devprg_ns.melf provision.xml
```

The device reboots after provisioning. Return to the image directory and confirm
the board is back in EDL (`lsusb -d 05c6:9008`) before proceeding.
