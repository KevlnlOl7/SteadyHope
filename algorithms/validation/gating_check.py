# -*- coding: utf-8 -*-
"""gating_check.py — 馬達 gating 設計的 Python 實證驗證

目的：驗證「馬達只在病徵頻率（4–6 Hz 顫抖帶）作動」的 gating 設計，
比較兩種方案並輸出韌體可直接使用的參數與濾波器係數。

  V1 (freq 窗)   ：gate = (freqEstimate ∈ [4.0, 6.5]) ∧ envelope ∧ 持續性 hysteresis
  V2 (頻帶能量比)：gate = (4–6 Hz 帶 envelope / (4–6 Hz + 1–3 Hz 帶 envelope) ≥ ratio)
                   ∧ envelope ∧ 持續性 hysteresis（不依賴 freqEstimate）

主要結論（fs=100 Hz、合成訊號、seed=0，2026-07-09）：
  - V1 在「自主動作 → 顫抖恢復」情境失效：強自主動作把 WFLC omega 拖到
    3 Hz clamp 下限後卡死（pull-in range 限制），freqEstimate 永遠回不到頻帶內，
    gate 無法 re-engage（顫抖段 duty 43.6%）。此現象與實機靜置 freqEstimate=3.21 Hz
    （clamp 地板 + 低頻姿勢晃動）觀測一致。
  - V2 全情境通過：純自主誤觸發 0.00%、顫抖 duty 97.2%、onset 420 ms、
    自主→顫抖 re-engage 610 ms。建議韌體採用 V2。
  - 已知限制（V1/V2 皆然）：顫抖與大幅自主動作「同時」發生時不作動。
    對 rest tremor 而言臨床上可接受（rest tremor 於自主動作時自然衰減），
    且安全優先（避免干擾自主動作、守住 ETVM）；action/postural tremor
    屬 gating_classifier（三狀態分類）的後續工作。

本檔的 EHWFLC_KF 類別逐行對應 algorithms/matlab/eHWFLC_KF_step.m 的 fs=100 Hz
分支（同一組帶通係數、mu、clamp、Q/R），用於在無 MATLAB 環境下交叉驗證。
MATLAB 對應版本見 algorithms/matlab/gating_sim.m。

執行：python gating_check.py   （需 numpy、scipy）
注意：RMSE(合成) 與 ETVM(真實病患) 不可直接互比；本檔所有 duty/延遲數字
皆為合成訊號設計值，僅供參數設計，不可當實測成效引用。
"""
import numpy as np

FS = 100.0
DT = 1.0 / FS


class EHWFLC_KF:
    """逐行移植 eHWFLC_KF_step.m（fs=100 Hz 係數分支）。"""

    M = 3
    DIM = 6
    MU_W = 0.01
    MU_OMEGA = 0.005
    OMEGA_INIT = 2 * np.pi * 5
    OMEGA_MIN = 2 * np.pi * 3
    OMEGA_MAX = 2 * np.pi * 12
    Q_VAL = 1e-2
    R_VAL = 0.05
    BP_B = np.array([0.17508764367210086, 0.0, -0.3501752873442017, 0.0, 0.17508764367210086])
    BP_A = np.array([1.0, -2.299055356038497, 1.9674977599844512, -0.874805556449481, 0.21965398391369484])

    def __init__(self):
        self.phi_k = 0.0
        self.omega_k = self.OMEGA_INIT
        self.w_wflc = np.zeros(self.DIM)
        self.w_est = np.zeros(self.DIM)
        self.P_est = np.eye(self.DIM)
        self.z = np.zeros(4)  # bp_z1..bp_z4 (DF-II Transposed)

    def step(self, s):
        b, a, z = self.BP_B, self.BP_A, self.z
        residual = b[0] * s + z[0]
        z[0] = b[1] * s - a[1] * residual + z[1]
        z[1] = b[2] * s - a[2] * residual + z[2]
        z[2] = b[3] * s - a[3] * residual + z[3]
        z[3] = b[4] * s - a[4] * residual

        M, dim = self.M, self.DIM
        self.phi_k += self.omega_k * DT
        m_arr = np.arange(1, M + 1)
        x_k = np.concatenate([np.sin(m_arr * self.phi_k), np.cos(m_arr * self.phi_k)])

        e_wflc = residual - self.w_wflc @ x_k
        freq_grad = np.sum(m_arr * (self.w_wflc[:M] * np.cos(m_arr * self.phi_k)
                                    - self.w_wflc[M:] * np.sin(m_arr * self.phi_k)))
        self.omega_k += 2 * self.MU_OMEGA * e_wflc * freq_grad
        self.omega_k = min(max(self.omega_k, self.OMEGA_MIN), self.OMEGA_MAX)
        self.w_wflc += 2 * self.MU_W * e_wflc * x_k

        U = np.zeros((dim, dim))
        H = np.zeros(dim)
        for m in range(1, M + 1):
            th = m * self.omega_k * DT
            i0 = 2 * (m - 1)
            ct, st = np.cos(th), np.sin(th)
            U[i0, i0] = ct
            U[i0, i0 + 1] = st
            U[i0 + 1, i0] = -st
            U[i0 + 1, i0 + 1] = ct
            H[i0] = np.sin(m * self.phi_k)
            H[i0 + 1] = np.cos(m * self.phi_k)

        w_pred = U @ self.w_est
        P_pred = U @ self.P_est @ U.T + self.Q_VAL * np.eye(dim)
        S_k = self.R_VAL + H @ P_pred @ H
        K_k = (P_pred @ H) / S_k
        innov = residual - H @ w_pred
        self.w_est = w_pred + K_k * innov
        P_est = (np.eye(dim) - np.outer(K_k, H)) @ P_pred
        self.P_est = (P_est + P_est.T) * 0.5

        return H @ self.w_est, self.omega_k / (2 * np.pi)


class FreqGate:
    """V1：freqEstimate 頻率窗 ∧ envelope ∧ 持續性 hysteresis（被實證推翻，留作對照）。"""

    def __init__(self, f_lo=4.0, f_hi=6.5, amp_on=6.0, amp_off=3.0,
                 env_decay=0.94, n_on=20, n_off=15):
        self.f_lo, self.f_hi = f_lo, f_hi
        self.amp_on, self.amp_off = amp_on, amp_off
        self.env_decay = env_decay
        self.n_on, self.n_off = n_on, n_off
        self.env = 0.0
        self.enabled = False
        self.on_count = 0
        self.off_count = 0

    def update(self, tremor_est, freq_hz):
        a = abs(tremor_est)
        self.env = max(a, self.env * self.env_decay)
        in_band = self.f_lo <= freq_hz <= self.f_hi
        if self.enabled:
            if in_band and self.env >= self.amp_off:
                self.off_count = 0
            else:
                self.off_count += 1
                if self.off_count >= self.n_off:
                    self.enabled = False
                    self.on_count = 0
        else:
            if in_band and self.env >= self.amp_on:
                self.on_count += 1
                if self.on_count >= self.n_on:
                    self.enabled = True
                    self.off_count = 0
            else:
                self.on_count = 0
        return self.enabled


class BandGate:
    """V2（建議採用）：雙頻帶能量比 gating，不依賴 freqEstimate。

    對 raw gyro 各跑一個 2 階 Butterworth 帶通（4–6 Hz 顫抖帶、1–3 Hz 自主帶），
    leaky envelope 後取比值；比值 + 絕對門檻 + 持續性 hysteresis 三條件 AND。
    可完整移植為韌體 C（兩個 DF-II Transposed biquad + 幾個純量狀態）。
    """

    def __init__(self, amp_on=6.0, amp_off=3.0, ratio_on=0.55, ratio_off=0.45,
                 env_decay=0.94, n_on=20, n_off=15):
        from scipy.signal import butter
        self.bt, self.at = butter(2, [4 / (FS / 2), 6 / (FS / 2)], "bandpass")
        self.bv, self.av = butter(2, [1 / (FS / 2), 3 / (FS / 2)], "bandpass")
        self.zt = np.zeros(4)
        self.zv = np.zeros(4)
        self.amp_on, self.amp_off = amp_on, amp_off
        self.ratio_on, self.ratio_off = ratio_on, ratio_off
        self.env_decay = env_decay
        self.n_on, self.n_off = n_on, n_off
        self.env_t = 0.0
        self.env_v = 0.0
        self.enabled = False
        self.on_count = 0
        self.off_count = 0

    @staticmethod
    def _df2t(x, b, a, z):
        y = b[0] * x + z[0]
        z[0] = b[1] * x - a[1] * y + z[1]
        z[1] = b[2] * x - a[2] * y + z[2]
        z[2] = b[3] * x - a[3] * y + z[3]
        z[3] = b[4] * x - a[4] * y
        return y

    def update(self, raw_gyro):
        yt = self._df2t(raw_gyro, self.bt, self.at, self.zt)
        yv = self._df2t(raw_gyro, self.bv, self.av, self.zv)
        self.env_t = max(abs(yt), self.env_t * self.env_decay)
        self.env_v = max(abs(yv), self.env_v * self.env_decay)
        ratio = self.env_t / (self.env_t + self.env_v + 1e-9)
        if self.enabled:
            if self.env_t >= self.amp_off and ratio >= self.ratio_off:
                self.off_count = 0
            else:
                self.off_count += 1
                if self.off_count >= self.n_off:
                    self.enabled = False
                    self.on_count = 0
        else:
            if self.env_t >= self.amp_on and ratio >= self.ratio_on:
                self.on_count += 1
                if self.on_count >= self.n_on:
                    self.enabled = True
                    self.off_count = 0
            else:
                self.on_count = 0
        return self.enabled


# ---------------- 合成訊號 ----------------
RNG = np.random.default_rng(0)


def make_signal(T, segments):
    """segments: list of (t0, t1, kind)；kind ∈ rest/tremor/voluntary/both

    tremor    : 15·sin(5 Hz, ±0.3 Hz 飄移) + 4.5·sin(二次諧波)   [對齊 golden 設計]
    voluntary : 40·sin(2 Hz) + 6·sin(4 Hz 諧波失真, 對抗性) + reach/stop 瞬態
    背景      : BNO055 雜訊 std 0.2 deg/s + 0.5 Hz 姿勢性微晃 2 deg/s
    """
    n = int(T * FS)
    t = np.arange(n) * DT
    sig = RNG.normal(0, 0.2, n) + 2.0 * np.sin(2 * np.pi * 0.5 * t)
    tremor_mask = np.zeros(n, dtype=bool)
    vol_mask = np.zeros(n, dtype=bool)
    for t0, t1, kind in segments:
        m = (t >= t0) & (t < t1)
        if kind in ("tremor", "both"):
            drift = 0.3 * np.sin(2 * np.pi * 0.1 * t[m])
            phase = 2 * np.pi * np.cumsum(5.0 + drift) * DT
            sig[m] += 15.0 * np.sin(phase) + 4.5 * np.sin(2 * phase)
            tremor_mask |= m
        if kind in ("voluntary", "both"):
            sig[m] += 40.0 * np.sin(2 * np.pi * 2.0 * t[m]) + 6.0 * np.sin(2 * np.pi * 4.0 * t[m] + 0.7)
            vol_mask |= m
    for t0, t1, kind in segments:
        if kind in ("voluntary", "both"):
            for tb in np.arange(t0 + 0.5, t1, 2.0):
                m = (t >= tb) & (t < tb + 0.3)
                sig[m] += 60.0 * 0.5 * (1 - np.cos(2 * np.pi * (t[m] - tb) / 0.3))
    return t, sig, tremor_mask, vol_mask


def run(name, T, segments):
    t, sig, tremor_mask, vol_mask = make_signal(T, segments)
    est = EHWFLC_KF()
    g1, g2 = FreqGate(), BandGate()
    n = len(t)
    en1 = np.zeros(n, dtype=bool)
    en2 = np.zeros(n, dtype=bool)
    freq = np.zeros(n)
    trem = np.zeros(n)
    for i, s in enumerate(sig):
        te, fh = est.step(s)
        en1[i] = g1.update(te, fh)
        en2[i] = g2.update(s)
        freq[i] = fh
        trem[i] = te
    return dict(name=name, t=t, en1=en1, en2=en2, freq=freq, trem=trem,
                tremor_mask=tremor_mask, vol_mask=vol_mask)


def duty(en, mask):
    return 100 * en[mask].mean() if mask.any() else float("nan")


def first_true(x, i0):
    idx = np.where(x[i0:])[0]
    return idx[0] / FS if len(idx) else None


def fmt_delay(d):
    return f"{d*1000:.0f} ms" if d is not None else "從未發生"


def main():
    out = []

    A = run("A: 純自主動作 (2Hz+4Hz諧波+瞬態)", 20, [(0, 2, "rest"), (2, 20, "voluntary")])
    B = run("B: 靜置5s → 5Hz 顫抖 onset", 20, [(0, 5, "rest"), (5, 20, "tremor")])
    C = run("C: 顫抖2-7s → 自主7-10s → 顫抖10-16s", 18,
            [(0, 2, "rest"), (2, 7, "tremor"), (7, 10, "voluntary"), (10, 16, "tremor"), (16, 18, "rest")])
    D = run("D: 顫抖2-4s → 顫抖+自主 4-16s", 18,
            [(0, 2, "rest"), (2, 4, "tremor"), (4, 16, "both"), (16, 18, "rest")])

    for r in (A, B, C, D):
        tm, vm = r["tremor_mask"], r["vol_mask"]
        vol_only, rest = vm & ~tm, ~tm & ~vm
        out.append(f"=== {r['name']} ===")
        for tag, en in (("V1 freq窗 ", r["en1"]), ("V2 頻帶比", r["en2"])):
            seg = []
            if vol_only.any():
                seg.append(f"自主段 {duty(en, vol_only):5.2f}% (目標<2%)")
            if tm.any():
                seg.append(f"顫抖段 {duty(en, tm):5.2f}% (目標>90%)")
            if rest.any():
                seg.append(f"靜置段 {duty(en, rest):5.2f}%")
            out.append(f"  [{tag}] " + " | ".join(seg))
        en_old = np.abs(r["trem"]) > 5.0  # 現行韌體：|tremorEstimate|>MOTOR_THRESHOLD
        if vol_only.any():
            out.append(f"  [現行韌體無gating] 自主段誤觸發 {duty(en_old, vol_only):5.2f}%")

    out.append("--- 切換延遲 ---")
    out.append(f"B onset(t=5)      V1: {fmt_delay(first_true(B['en1'], 500))} | V2: {fmt_delay(first_true(B['en2'], 500))}")
    out.append(f"C onset(t=2)      V1: {fmt_delay(first_true(C['en1'], 200))} | V2: {fmt_delay(first_true(C['en2'], 200))}")
    out.append(f"C 釋放(t=7)       V1: {fmt_delay(first_true(~C['en1'], 700))} | V2: {fmt_delay(first_true(~C['en2'], 700))}")
    out.append(f"C 再啟動(t=10)    V1: {fmt_delay(first_true(C['en1'], 1000))} | V2: {fmt_delay(first_true(C['en2'], 1000))}")
    out.append(f"C 停止釋放(t=16)  V1: {fmt_delay(first_true(~C['en1'], 1600))} | V2: {fmt_delay(first_true(~C['en2'], 1600))}")

    i10_14 = (C["t"] >= 10.5) & (C["t"] <= 14.0)
    out.append("--- V1 失效證據（C: 自主動作後 freqEstimate 卡在 clamp 地板） ---")
    out.append(f"C t=10.5–14s freqEstimate: min={C['freq'][i10_14].min():.3f} max={C['freq'][i10_14].max():.3f} Hz"
               f"（clamp 下限 3.0；顫抖明明恢復卻回不到 4–6 帶內 → V1 gate 永久失效）")

    from scipy.signal import butter
    out.append("--- V2 韌體用 biquad 係數 (fs=100 Hz, 4 階 DF-II Transposed 各一組) ---")
    for name, lo, hi in (("TREMOR 4-6Hz  ", 4, 6), ("VOLUNTARY 1-3Hz", 1, 3)):
        b, a = butter(2, [lo / (FS / 2), hi / (FS / 2)], "bandpass")
        out.append(f"  {name} b = {{{', '.join(f'{v:.17g}' for v in b)}}}")
        out.append(f"  {'':>15} a = {{{', '.join(f'{v:.17g}' for v in a)}}}")

    print("\n".join(out))


if __name__ == "__main__":
    main()
