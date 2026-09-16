# -*- coding: utf-8 -*-
"""V2 tremor gate 的 Python 逐筆參考實作。

係數、float/double邊界與狀態機對齊 handoff/src/gating/tremor_gate.c。
用途是產生STM32固定向量的golden trace與離線門檻分析，不取代韌體C版本。
"""

from __future__ import annotations

from dataclasses import dataclass
import math

import numpy as np


TREMOR_B = (
    0.0036216815149286408,
    0.0,
    -0.0072433630298572816,
    0.0,
    0.0036216815149286408,
)
TREMOR_A = (
    1.0,
    -3.6427871266953296,
    5.1461877540722814,
    -3.3324758952732241,
    0.83718165125602273,
)
VOLUNTARY_B = (
    0.0036216815149286382,
    0.0,
    -0.0072433630298572764,
    0.0,
    0.0036216815149286382,
)
VOLUNTARY_A = (
    1.0,
    -3.8000503652844575,
    5.4393397877934069,
    -3.4763426471814802,
    0.83718165125602251,
)


@dataclass(frozen=True)
class GateConfig:
    amp_on: float = 6.0
    amp_off: float = 3.0
    ratio_on: float = 0.55
    ratio_off: float = 0.45
    envelope_decay: float = 0.94
    samples_on: int = 20
    samples_off: int = 15


class TremorGateReference:
    """和C版相同的單一gating instance。"""

    def __init__(self, config: GateConfig | None = None) -> None:
        self.config = config or GateConfig()
        self.reset()

    def reset(self) -> None:
        self.tremor_filter_state = [0.0] * 4
        self.voluntary_filter_state = [0.0] * 4
        self.tremor_envelope = np.float32(0.0)
        self.voluntary_envelope = np.float32(0.0)
        self.tremor_ratio = np.float32(0.0)
        self.on_count = 0
        self.off_count = 0
        self.enabled = 0

    @staticmethod
    def _df2t_step(
        value: float,
        numerator: tuple[float, ...],
        denominator: tuple[float, ...],
        state: list[float],
    ) -> float:
        output = numerator[0] * value + state[0]
        state[0] = numerator[1] * value - denominator[1] * output + state[1]
        state[1] = numerator[2] * value - denominator[2] * output + state[2]
        state[2] = numerator[3] * value - denominator[3] * output + state[3]
        state[3] = numerator[4] * value - denominator[4] * output
        return output

    def update(self, raw_gyro_dps: float) -> int:
        if not math.isfinite(raw_gyro_dps):
            self.enabled = 0
            self.on_count = 0
            self.off_count = 0
            return 0

        tremor_sample = np.float32(abs(self._df2t_step(
            float(raw_gyro_dps), TREMOR_B, TREMOR_A,
            self.tremor_filter_state,
        )))
        voluntary_sample = np.float32(abs(self._df2t_step(
            float(raw_gyro_dps), VOLUNTARY_B, VOLUNTARY_A,
            self.voluntary_filter_state,
        )))

        decay = np.float32(self.config.envelope_decay)
        decayed_tremor = np.float32(self.tremor_envelope * decay)
        decayed_voluntary = np.float32(self.voluntary_envelope * decay)
        self.tremor_envelope = np.float32(max(tremor_sample, decayed_tremor))
        self.voluntary_envelope = np.float32(max(
            voluntary_sample, decayed_voluntary
        ))
        denominator = np.float32(
            self.tremor_envelope + self.voluntary_envelope + np.float32(1.0e-9)
        )
        self.tremor_ratio = np.float32(self.tremor_envelope / denominator)

        if self.enabled:
            hold = (
                self.tremor_envelope >= np.float32(self.config.amp_off)
                and self.tremor_ratio >= np.float32(self.config.ratio_off)
            )
            if hold:
                self.off_count = 0
            elif self.off_count < self.config.samples_off:
                self.off_count += 1
                if self.off_count >= self.config.samples_off:
                    self.enabled = 0
                    self.on_count = 0
        else:
            trigger = (
                self.tremor_envelope >= np.float32(self.config.amp_on)
                and self.tremor_ratio >= np.float32(self.config.ratio_on)
            )
            if trigger:
                if self.on_count < self.config.samples_on:
                    self.on_count += 1
                if self.on_count >= self.config.samples_on:
                    self.enabled = 1
                    self.off_count = 0
            else:
                self.on_count = 0

        return self.enabled

    def snapshot(self) -> dict[str, float | int]:
        return {
            "tremor_envelope": float(self.tremor_envelope),
            "voluntary_envelope": float(self.voluntary_envelope),
            "tremor_ratio": float(self.tremor_ratio),
            "on_count": self.on_count,
            "off_count": self.off_count,
            "enabled": self.enabled,
        }
