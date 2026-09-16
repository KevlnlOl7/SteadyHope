# -*- coding: utf-8 -*-
"""tremorEstimate到PWM／方向命令的安全參考映射。

這是演算法端行為規格，不含STM32 HAL。gain、上限、極性都必須由非人體負載實測校正。
"""

from __future__ import annotations

from dataclasses import dataclass
import math


@dataclass(frozen=True)
class PwmConfig:
    deadband_dps: float = 1.0
    gain_percent_per_dps: float = 5.0
    max_duty_percent: float = 30.0
    max_duty_step_per_tick: float = 5.0
    direction_polarity: int = 1


class PwmCommandMapper:
    """100 Hz逐筆更新的P-only PWM request產生器。"""

    def __init__(self, config: PwmConfig | None = None) -> None:
        self.config = config or PwmConfig()
        self.duty_percent = 0.0
        self.direction = 0

    def stop(self) -> dict[str, float | int]:
        self.duty_percent = 0.0
        self.direction = 0
        return self.snapshot()

    def snapshot(self) -> dict[str, float | int]:
        return {
            "duty_percent": self.duty_percent,
            "direction": self.direction,
        }

    @staticmethod
    def _move_toward(current: float, target: float, step: float) -> float:
        if current < target:
            return min(target, current + step)
        return max(target, current - step)

    def update(
        self,
        tremor_estimate_dps: float,
        *,
        enabled: bool,
        sensor_valid: bool = True,
        driver_fault: bool = False,
    ) -> dict[str, float | int]:
        if (
            not enabled or not sensor_valid or driver_fault
            or not math.isfinite(tremor_estimate_dps)
        ):
            return self.stop()

        # 抑震命令和估測震顫反相；direction_polarity吸收實機接線極性。
        signed_command = (
            -float(tremor_estimate_dps) * self.config.direction_polarity
        )
        magnitude = max(abs(signed_command) - self.config.deadband_dps, 0.0)
        target_duty = min(
            self.config.max_duty_percent,
            self.config.gain_percent_per_dps * magnitude,
        )
        desired_direction = (
            0 if target_duty == 0.0 else (1 if signed_command > 0.0 else -1)
        )
        step = self.config.max_duty_step_per_tick

        # 反轉前先把duty降到0；下一個100 Hz tick才允許換方向。
        if (
            self.direction != 0 and desired_direction != 0
            and desired_direction != self.direction
        ):
            self.duty_percent = self._move_toward(
                self.duty_percent, 0.0, step
            )
            if self.duty_percent == 0.0:
                self.direction = 0
            return self.snapshot()

        if desired_direction == 0:
            self.duty_percent = self._move_toward(
                self.duty_percent, 0.0, step
            )
            if self.duty_percent == 0.0:
                self.direction = 0
            return self.snapshot()

        if self.direction == 0:
            self.direction = desired_direction
        self.duty_percent = self._move_toward(
            self.duty_percent, target_duty, step
        )
        return self.snapshot()
