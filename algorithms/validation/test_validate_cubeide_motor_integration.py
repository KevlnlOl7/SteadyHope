# -*- coding: utf-8 -*-

import unittest

try:
    from .validate_cubeide_motor_integration import (
        CM7_MAIN,
        CM7_MOTOR_CONFIG,
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
        CM7_MOTOR_CONFIG,
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

    def test_runtime_arm_disable_fails_powered_bench_contract(self):
        source = (REPO_ROOT / CM7_MAIN).read_text(encoding="utf-8")
        config = (REPO_ROOT / CM7_MOTOR_CONFIG).read_text(encoding="utf-8")
        original = "#define MOTOR_DEFAULT_RUNTIME_ARMED                 1U"
        tampered = "#define MOTOR_DEFAULT_RUNTIME_ARMED                 0U"
        self.assertIn(original, config)

        check = validate_cm7_safety_source(
            source, config.replace(original, tampered, 1)
        )
        self.assertFalse(check.passed)
        self.assertEqual(check.code, "cm7-powered-bench-config")
        self.assertIn(
            "MOTOR_DEFAULT_RUNTIME_ARMED must be defined once as 1",
            check.detail,
        )

    def test_zero_hal_ccr_fails_powered_bench_contract(self):
        source = (REPO_ROOT / CM7_MAIN).read_text(encoding="utf-8")
        config = (REPO_ROOT / CM7_MOTOR_CONFIG).read_text(encoding="utf-8")
        original = "#define MOTOR_MAX_ACTIVE_CCR                        3200U"
        tampered = "#define MOTOR_MAX_ACTIVE_CCR                        0U"
        self.assertIn(original, config)

        check = validate_cm7_safety_source(
            source, config.replace(original, tampered, 1)
        )
        self.assertFalse(check.passed)
        self.assertEqual(check.code, "cm7-powered-bench-config")
        self.assertIn("MOTOR_MAX_ACTIVE_CCR must be defined once as 3200", check.detail)

    def test_final_permission_position_veto_regression_fails_contract(self):
        source = (REPO_ROOT / CM7_MAIN).read_text(encoding="utf-8")
        config = (REPO_ROOT / CM7_MOTOR_CONFIG).read_text(encoding="utf-8")
        original = """((MOTOR_POWERED_BENCH_MODE == 1U) ||
        ((calibration_required == 0U) &&"""
        tampered = """((MOTOR_POWERED_BENCH_MODE == 0U) ||
        ((calibration_required == 0U) &&"""
        self.assertIn(original, source)

        check = validate_cm7_safety_source(
            source.replace(original, tampered, 1), config
        )
        self.assertFalse(check.passed)
        self.assertIn("missing final_permission powered position bypass", check.detail)

    def test_final_recheck_encoder_veto_regression_fails_contract(self):
        source = (REPO_ROOT / CM7_MAIN).read_text(encoding="utf-8")
        config = (REPO_ROOT / CM7_MOTOR_CONFIG).read_text(encoding="utf-8")
        original = """((MOTOR_POWERED_BENCH_MODE == 1U) ||
          ((quadrature_encoder.initialized == 1U) &&"""
        tampered = """((MOTOR_POWERED_BENCH_MODE == 0U) ||
          ((quadrature_encoder.initialized == 1U) &&"""
        self.assertIn(original, source)

        check = validate_cm7_safety_source(
            source.replace(original, tampered, 1), config
        )
        self.assertFalse(check.passed)
        self.assertIn(
            "missing final_recheck powered encoder/position bypass", check.detail
        )

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
