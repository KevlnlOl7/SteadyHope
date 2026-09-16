# -*- coding: utf-8 -*-

import unittest

from validate_stm32_motor_main import (
    DEFAULT_MAIN,
    DEFAULT_SHADOW_MAIN,
    EXPECTED_MODULE_NAMES,
    EXPECTED_PRIMARY_HEADERS,
    load_manifest,
    validate_manifest,
    validate_motor_main,
    validate_motor_main_source,
    validate_shadow_main,
    validate_shadow_blob,
    EXPECTED_SHADOW_GIT_BLOB_SHA1,
)


GOOD_MAIN = r'''
#include "main.h"
#include "suppression_control.h"
#include "motor_command_mapper.h"
#include "quadrature_encoder.h"
#include "motor_position_guard.h"
#include "tb6612_driver.h"
#include "stm32_tb6612_hal.h"

typedef struct { unsigned char motor_enabled; } Packet;
static unsigned int imu_sample_generation;
static unsigned int last_controlled_sample_generation;
static unsigned int software_tick_count;
static unsigned int control_tick_count;
static unsigned int pending_ticks;
static unsigned int scheduler_overrun_count;
static unsigned char fresh_sample_available;
static unsigned char motor_output_active_debug;
static unsigned char scheduler_overrun_this_tick;
static unsigned char tick_flag;
static unsigned char motor_runtime_fault_latched;
static unsigned char motor_runtime_armed;
static unsigned char motor_bench_config_approved;
static struct {
    unsigned char initialized;
    unsigned char invalid_transition_latched;
    unsigned char overflow_latched;
} quadrature_encoder;
static struct {
    unsigned char zeroed;
    unsigned char fault_latched;
} motor_position_guard;
static int tb6612_hal;

static void Send_Tremor_Data(void)
{
    Packet sample = {0};
    sample.motor_enabled = motor_output_active_debug;
}

static void ControlPipeline_100HzFreshSample(double raw_gyro_dps)
{
    int candidate = 0;
    unsigned int irq_primask;
    unsigned char candidate_active = 1U;
    unsigned char position_allowed = 1U;
    unsigned char final_recheck_ok;

    SuppressionControl_Update(0, raw_gyro_dps, 1U, 0U, 0U, 0U, 0);
    MotorCommandMapper_Update(0, 0.0, 0U, 0U, 0U, 0);
    TB6612Driver_Update(0, 0, 0.0, 0U, 0);
    MotorPositionGuard_Update(0, 0, 1U, 0, 0U, 0);
    if ((candidate_active == 1U) && (position_allowed == 1U)) {
        irq_primask = __get_PRIMASK();
        __disable_irq();
        final_recheck_ok =
            ((fresh_sample_available == 1U) &&
             (scheduler_overrun_this_tick == 0U) &&
             (tick_flag == 0U) &&
             (software_tick_count == control_tick_count) &&
             (motor_runtime_fault_latched == 0U) &&
             (motor_runtime_armed == 1U) &&
             (motor_bench_config_approved == 1U) &&
             (quadrature_encoder.initialized == 1U) &&
             (quadrature_encoder.invalid_transition_latched == 0U) &&
             (quadrature_encoder.overflow_latched == 0U) &&
             (motor_position_guard.zeroed == 1U) &&
             (motor_position_guard.fault_latched == 0U)) ? 1U : 0U;
        if (final_recheck_ok == 1U) {
            STM32_TB6612_HAL_Apply(&tb6612_hal, &candidate);
        }
        __set_PRIMASK(irq_primask);
    }
}

static void ControlPipeline_RejectStaleSample(void)
{
    STM32_TB6612_HAL_ForceSafe(0);
}

int main(void)
{
    pending_ticks = software_tick_count - control_tick_count;
    scheduler_overrun_this_tick = (pending_ticks == 1U) ? 0U : 1U;
    if (scheduler_overrun_this_tick != 0U) {
        scheduler_overrun_count++;
        ControlPipeline_RejectStaleSample();
    } else {
        if (Read_IMU_RealData() == HAL_OK) {
            imu_sample_generation++;
        }
        fresh_sample_available = (unsigned char)(
            imu_sample_generation != last_controlled_sample_generation);
        if (fresh_sample_available != 0U) {
            ControlPipeline_100HzFreshSample(0.0);
            last_controlled_sample_generation = imu_sample_generation;
        } else {
            ControlPipeline_RejectStaleSample();
        }
    }
    Send_Tremor_Data();
    return 0;
}
'''


class Stm32MotorMainContractTest(unittest.TestCase):
    @staticmethod
    def issue_codes(source):
        return {issue.code for issue in validate_motor_main_source(source)}

    def test_minimal_good_contract_passes(self):
        self.assertEqual(validate_motor_main_source(GOOD_MAIN), [])

    def test_absolute_include_is_rejected(self):
        source = GOOD_MAIN.replace(
            '#include "main.h"',
            '#include "C:/Users/person/workspace/main.h"',
        )
        self.assertIn("absolute-include", self.issue_codes(source))

    def test_legacy_frequency_authority_is_rejected(self):
        source = GOOD_MAIN.replace(
            "Send_Tremor_Data();",
            "if (freqEstimate > 4.0) { tremor_active = 1U; }\n"
            "    Send_Tremor_Data();",
        )
        self.assertIn("legacy-estimator-authority", self.issue_codes(source))

    def test_direct_estimator_or_legacy_control_paths_are_rejected(self):
        forbidden = [
            "FakeApp_Process",
            "Read_IMU_TestData",
            "Bandpass_TremorGate_Update",
            "Tremor_Detector_Update",
            "Motor_Control",
            "Motor_UpdateWithDeadtime",
            "Actuator_StateMachine_Reset",
            "Actuator_StateMachine_Update",
        ]
        for token in forbidden:
            with self.subTest(token=token):
                source = GOOD_MAIN.replace(
                    "Send_Tremor_Data();", f"{token}();\n    Send_Tremor_Data();"
                )
                self.assertIn("legacy-main-path", self.issue_codes(source))

    def test_direct_generated_estimator_include_is_rejected(self):
        source = GOOD_MAIN.replace(
            '#include "main.h"',
            '#include "main.h"\n#include "eHWFLC_KF_step.h"',
        )
        self.assertIn("authority-bypass-header", self.issue_codes(source))

    def test_gate_as_uart_motor_status_is_rejected(self):
        source = GOOD_MAIN.replace(
            "sample.motor_enabled = motor_output_active_debug;",
            "sample.motor_enabled = gate_enabled_debug;",
        )
        self.assertIn("uart-motor-semantics", self.issue_codes(source))

    def test_missing_authoritative_header_is_rejected(self):
        source = GOOD_MAIN.replace('#include "tb6612_driver.h"\n', "")
        self.assertIn("primary-header-count", self.issue_codes(source))

    def test_stale_sample_reuse_is_rejected(self):
        source = GOOD_MAIN.replace(
            "imu_sample_generation != last_controlled_sample_generation",
            "imu_sample_generation > 0U",
        )
        self.assertIn("fresh-generation-comparison", self.issue_codes(source))

    def test_nonfresh_path_must_force_safe(self):
        source = GOOD_MAIN.replace(
            "STM32_TB6612_HAL_ForceSafe(0);", "Send_Tremor_Data();"
        )
        self.assertIn("stale-wrapper-unsafe", self.issue_codes(source))

    def test_scheduler_overrun_must_reject_sample(self):
        source = GOOD_MAIN.replace(
            "scheduler_overrun_count++;\n"
            "        ControlPipeline_RejectStaleSample();",
            "scheduler_overrun_count++;",
            1,
        )
        self.assertIn("scheduler-overrun-failsafe", self.issue_codes(source))

    def test_active_apply_must_restore_saved_primask(self):
        source = GOOD_MAIN.replace(
            "        __set_PRIMASK(irq_primask);\n", "", 1
        )
        self.assertIn("active-critical-section", self.issue_codes(source))

    def test_active_apply_must_recheck_encoder_latch(self):
        source = GOOD_MAIN.replace(
            "             (quadrature_encoder.overflow_latched == 0U) &&\n",
            "",
            1,
        )
        self.assertIn("active-final-recheck", self.issue_codes(source))

    def test_manifest_is_the_reviewed_exact_module_set(self):
        manifest = load_manifest()
        self.assertEqual(
            {module["name"] for module in manifest["modules"]},
            EXPECTED_MODULE_NAMES,
        )
        self.assertEqual(
            set(manifest["main_primary_headers"]), EXPECTED_PRIMARY_HEADERS
        )
        self.assertEqual(validate_manifest(), [])

    def test_repository_canonical_main_passes(self):
        self.assertTrue(DEFAULT_MAIN.is_file(), DEFAULT_MAIN)
        self.assertEqual(validate_motor_main(DEFAULT_MAIN), [])

    def test_0822_shadow_reference_stays_sealed_and_motor_off(self):
        self.assertTrue(DEFAULT_SHADOW_MAIN.is_file(), DEFAULT_SHADOW_MAIN)
        self.assertEqual(validate_shadow_main(DEFAULT_SHADOW_MAIN), [])

    def test_0822_shadow_seal_rejects_edits(self):
        changed = DEFAULT_SHADOW_MAIN.read_bytes() + b"\n"
        codes = {
            issue.code
            for issue in validate_shadow_blob(
                changed, EXPECTED_SHADOW_GIT_BLOB_SHA1
            )
        }
        self.assertIn("shadow-seal-mismatch", codes)


if __name__ == "__main__":
    unittest.main()
