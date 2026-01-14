Welcome to the sample project that demonstrates the integration of the
[Texas Instruments (TI) SDK](https://www.ti.com/tool/download/SIMPLELINK-LOWPOWER-F3-SDK)
with the [HubbleNetwork-SDK](https://github.com/HubbleNetwork/hubble-device-sdk). This
project showcases the development of a BLE (Bluetooth Low Energy)
application using FreeRTOS, leveraging the capabilities of both SDKs.

## Overview

This project is designed to:

+ Demonstrate the use of the TI SDK for BLE application development.
+ Showcase the integration of the HubbleNetwork SDK for BLE-specific operations.
+ Provide a starting point for developers working on BLE applications with TI devices.

The project targets the *CC23xx* family of devices and uses *FreeRTOS*
as the operating system. It is originally a copy of
[basic-ble](https://github.com/TexasInstruments/simplelink-ble5stack-examples/tree/main/examples/rtos/LP_EM_CC2340R5/ble5stack/basic_ble)
sample.

### Features

+ Integration with the HubbleNetwork-SDK for BLE-specific operations.
+ FreeRTOS-based task management.
+ Modular and extensible codebase.

### Requirements

To build and run this project, you will need:

* A TI CC23xx development board (e.g., **LP_EM_CC2340R5**).
* The [TI SDK](https://www.ti.com/tool/download/SIMPLELINK-LOWPOWER-F3-SDK) installed on your system.
* [TI toolchain](https://www.ti.com/tool/CCSTUDIO)

### Setup Instructions

1. **Install Dependencies**

Ensure that the TI SDK is installed on your
system. Set *SYSCONFIG_TOOL*, *SIMPLELINK_LOWPOWER_F3_SDK_INSTALL_DIR* and *TICLANG_ARMCOMPILER*
environment variables. e.g:

```bash
export TICLANG_ARMCOMPILER=/Applications/ti/ccs2040/ccs/tools/compiler/ti-cgt-armllvm_4.0.4.LTS/
export SIMPLELINK_LOWPOWER_F3_SDK_INSTALL_DIR=/Applications/ti/simplelink_lowpower_f3_sdk_9_14_00_41
export SYSCONFIG_TOOL=/Applications/ti/sysconfig_1.23.2/sysconfig_cli.sh
```

This application has only been tested with the versions shown above.

2. **Acquire a Device Key**

Acquire a device key from Hubble. This will be a base64 encoded string.

**NOTE!** This application only supports 128-bit keys, so when requesting a key from Hubble, use the ```AES-128-CTR``` variant for the ```"encryption"``` key.

If you wish to just test your device locally, you can exclude the ```KEY``` value when invoking ```make``` below and the key will default to ```1111111111111111111111==```. This will enable local testing but your device will not show up in the backend.

3. **Build the Project**

Build the project using the provided *Makefile* and passing in the key you generated:

```bash
make KEY=<YOUR_KEY>
```

4. **Flash the Firmware**

Flash the generated firmware (*hubble-simple.out/hex*) onto the target device using your preferred flashing tool.

### Usage

Once the firmware is flashed:

1. Power on the development board.
2. The device will start BLE advertising.

### Key Files

+ **src/hubble_ble_adv.c**: BLE advertising implementation.
+ **src/hubble_ble_ti.c**: This is a core file to integrate with HubbleNetwork SDK. It implements the required cryptograhic API.
+ **Makefile**: Build system for the project.
