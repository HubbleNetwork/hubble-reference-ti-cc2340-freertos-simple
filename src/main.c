/*
 * Copyright (c) 2025 Hubble Network, Inc.
 * SPDX-License-Identifier: Apache-2.0
 */

#include <FreeRTOS.h>
#include <stdint.h>
#include <task.h>

#include <ti/drivers/Power.h>
#include <ti/devices/DeviceFamily.h>

#include "ti_ble_config.h"
#include "ti/ble/stack_util/icall/app/icall.h"
#include "ti/ble/stack_util/health_toolkit/assert.h"

#ifndef USE_DEFAULT_USER_CFG
#include "ti/ble/app_util/config/ble_user_config.h"
// BLE user defined configuration
icall_userCfg_t user0Cfg = BLE_USER_CFG;
#endif // USE_DEFAULT_U

#include "ti/ble/app_util/framework/bleapputil_api.h"

#include "b64.h"
#include <hubble/hubble.h>

BLEAppUtil_GeneralParams_t appMainParams = {
	.taskPriority = 1,
	.taskStackSize = 2048,
	.profileRole = (BLEAppUtil_Profile_Roles_e)(HOST_CONFIG),
	.addressMode = DEFAULT_ADDRESS_MODE,
	.deviceNameAtt = attDeviceName,
	.pDeviceRandomAddress = pRandomAddress,
};

/* Macro helpers to turn a macro value into a string literal */
#define STR_HELPER(x) #x
#define STR(x) STR_HELPER(x)

static uint8_t master_key[CONFIG_HUBBLE_KEY_SIZE];

bStatus_t hubble_ble_adv_start(void);

static BLEAppUtil_PeriCentParams_t appMainPeriCentParams;

static int decode_master_key(void)
{
	size_t keylen = b64_decoded_size(STR(HUBBLE_KEY));
	if (keylen != sizeof(master_key)) {
		return -1;
	}
	int ret = b64_decode(STR(HUBBLE_KEY), master_key, sizeof(master_key));
	if (ret != 0) {
		return ret;
	}
	return ret;
}

void criticalErrorHandler(int32 errorCode, void *pInfo)
{
	(void)errorCode;
	(void)pInfo;
}

void App_StackInitDoneHandler(gapDeviceInitDoneEvent_t *deviceInitDoneData)
{
	int err;
	bStatus_t status;

	(void)deviceInitDoneData;

	err = decode_master_key();
	if (err != 0) {
		return;
	}

	err = hubble_init((uint64_t)HUBBLE_TIME_S * 1000, master_key);
	if (err != 0) {
		return;
	}

	status = hubble_ble_adv_start();
	if (status != SUCCESS) {
		/* TODO: Call Error Handler */
	}
}

/* Memory monitoring function for runtime analysis */
void monitor_memory_usage(void)
{
	size_t heap_free = xPortGetFreeHeapSize();
	size_t heap_min = xPortGetMinimumEverFreeHeapSize();

	/* TODO: Log or store these values for analysis
	 * If heap_min < 2048 bytes, heap size needs to be increased
	 * This function should be called periodically during testing
	 * to validate heap size is adequate under all conditions
	 */

	/* TODO: Monitor task stacks
	 * UBaseType_t ble_stack_wm = uxTaskGetStackHighWaterMark(ble_task_handle);
	 * UBaseType_t adv_stack_wm = uxTaskGetStackHighWaterMark(adv_task_handle);
	 * Watermark < 256 words (1 KB) indicates potential overflow risk
	 */
}

int main()
{
	Board_init();

	/* Update User Configuration of the stack */
	user0Cfg.appServiceInfo->timerTickPeriod = ICall_getTickPeriod();
	user0Cfg.appServiceInfo->timerMaxMillisecond = ICall_getMaxMSecs();

	BLEAppUtil_init(&criticalErrorHandler, &App_StackInitDoneHandler,
			&appMainParams, &appMainPeriCentParams);

	/* Start the FreeRTOS scheduler */
	vTaskStartScheduler();

	return 0;
}
