# -*- coding: utf-8 -*-

import unittest

try:
    from .validate_cubeide_motor_integration import (
        CM7_MAIN,
        CM7_BMFLC_DIR,
        CANONICAL_BMFLC_DIR,
        CANONICAL_EHWFLC_DIR,
        ABSOLUTE_USER_PATH_PATTERN,
        REPO_ROOT,
        _directory_identity_check,
        validate_cm7_safety_source,
        validate_repository,
    )
except ImportError:  # Direct discovery with algorithms/validation on sys.path.
    from validate_cubeide_motor_integration import (
        CM7_MAIN,
        CM7_BMFLC_DIR,
        CANONICAL_BMFLC_DIR,
        CANONICAL_EHWFLC_DIR,
        ABSOLUTE_USER_PATH_PATTERN,
        REPO_ROOT,
        _directory_identity_check,
        validate_cm7_safety_source,
        validate_repository,
    )


class CubeIdeMotorIntegrationContractTest(unittest.TestCase):
    def test_repository_baseline_passes(self):
        checks = validate_repository(REPO_ROOT)
        failures = [
            f"{check.code}: {check.detail}" for check in checks if not check.passed
        ]
        self.assertEqual(failures, [])

    def test_runtime_arm_tamper_fails_critical_contract(self):
        source = (REPO_ROOT / CM7_MAIN).read_text(encoding="utf-8")
        original = "volatile uint8_t motor_runtime_armed = 0U;"
        tampered = "volatile uint8_t motor_runtime_armed = 1U;"
        self.assertIn(original, source)

        check = validate_cm7_safety_source(
            source.replace(original, tampered, 1)
        )
        self.assertFalse(check.passed)
        self.assertEqual(check.code, "cm7-motor-safety-lock")
        self.assertIn("must never be assigned one", check.detail)

    def test_hal_integer_ccr_lock_tamper_fails_critical_contract(self):
        source = (REPO_ROOT / CM7_MAIN).read_text(encoding="utf-8")
        original = "#define MOTOR_MAX_ACTIVE_CCR            0U"
        tampered = "#define MOTOR_MAX_ACTIVE_CCR            1U"
        self.assertIn(original, source)

        check = validate_cm7_safety_source(
            source.replace(original, tampered, 1)
        )
        self.assertFalse(check.passed)
        self.assertEqual(check.code, "cm7-motor-safety-lock")
        self.assertIn("MOTOR_MAX_ACTIVE_CCR must be defined once as zero", check.detail)

    def test_absolute_user_path_fails_metadata_contract(self):
        self.assertIsNotNone(
            ABSOLUTE_USER_PATH_PATTERN.search(
                "C:/Users/someone/CubeIDE/workspace"
            )
        )
        self.assertIsNotNone(
            ABSOLUTE_USER_PATH_PATTERN.search("/home/someone/cubeide/workspace")
        )
        self.assertIsNone(
            ABSOLUTE_USER_PATH_PATTERN.search(
                "../../../../algorithms/handoff/src/control"
            )
        )

    def test_estimator_directory_drift_fails_contract(self):
        check = _directory_identity_check(
            REPO_ROOT,
            "estimator-mirror",
            CM7_BMFLC_DIR,
            CANONICAL_BMFLC_DIR,
        )
        self.assertTrue(check.passed)

        check = _directory_identity_check(
            REPO_ROOT,
            "estimator-mirror",
            CM7_BMFLC_DIR,
            CANONICAL_EHWFLC_DIR,
        )
        self.assertFalse(check.passed)
        self.assertTrue(
            "missing:" in check.detail or "unexpected:" in check.detail
        )


if __name__ == "__main__":
    unittest.main()
