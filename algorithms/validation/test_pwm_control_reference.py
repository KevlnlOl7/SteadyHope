# -*- coding: utf-8 -*-

import unittest

from pwm_control_reference import PwmCommandMapper, PwmConfig


class PwmControlReferenceTest(unittest.TestCase):
    def test_disabled_or_invalid_input_stops_immediately(self):
        mapper = PwmCommandMapper()
        mapper.update(10.0, enabled=True)
        self.assertGreater(mapper.duty_percent, 0.0)
        self.assertEqual(mapper.update(10.0, enabled=False)["duty_percent"], 0.0)
        self.assertEqual(mapper.update(float("nan"), enabled=True)["direction"], 0)

    def test_deadband_and_saturation(self):
        config = PwmConfig(max_duty_step_per_tick=100.0)
        mapper = PwmCommandMapper(config)
        self.assertEqual(mapper.update(0.5, enabled=True)["duty_percent"], 0.0)
        self.assertEqual(mapper.update(100.0, enabled=True)["duty_percent"], 30.0)

    def test_direction_is_opposite_tremor_estimate(self):
        mapper = PwmCommandMapper(PwmConfig(max_duty_step_per_tick=100.0))
        self.assertEqual(mapper.update(5.0, enabled=True)["direction"], -1)

    def test_reversal_passes_through_zero(self):
        mapper = PwmCommandMapper(PwmConfig(max_duty_step_per_tick=100.0))
        mapper.update(5.0, enabled=True)
        reversing = mapper.update(-5.0, enabled=True)
        self.assertEqual(reversing["duty_percent"], 0.0)
        self.assertEqual(reversing["direction"], 0)
        switched = mapper.update(-5.0, enabled=True)
        self.assertEqual(switched["direction"], 1)


if __name__ == "__main__":
    unittest.main()
