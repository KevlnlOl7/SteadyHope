/*
 * Academic License - for use in teaching, academic research, and meeting
 * course requirements at degree granting institutions only.  Not for
 * government, commercial, or other organizational use.
 * File: BMFLC_step.c
 *
 * MATLAB Coder version            : 25.2
 * C/C++ source code generated on  : 01-Jul-2026 14:37:38
 */

/* Include Files */
#include "BMFLC_step.h"
#include "BMFLC_step_data.h"
#include "BMFLC_step_initialize.h"
#include <math.h>
#include <string.h>

/* Variable Definitions */
static double w_k[38];

static double k_count;

static double bp_z1;

static double bp_z2;

static double bp_z3;

static double bp_z4;

static double bp_b[5];

static double bp_a[5];

static double dt;

/* Function Definitions */
/*
 * BMFLC_STEP 單樣本 BMFLC 震顫估測（即時版本 v6）
 *
 *    tremor_est = BMFLC_step(signal_sample, fs_in)
 *
 *    v6 改進：支援動態 fs_in 輸入，預設為 100 Hz，並預存 50 Hz 與 100 Hz
 *    之 2-20 Hz 帶通濾波器係數，維持 C-codegen 相容性。
 *
 *    輸入:  signal_sample - 單一 IMU 樣本
 *           fs_in         - (可選) 取樣率 (預設 100 Hz)
 *    輸出:  tremor_est    - 估測震顫值
 *
 * Arguments    : double signal_sample
 * Return Type  : double
 */
double BMFLC_step(double signal_sample)
{
  double x_k[38];
  double e_k;
  double residual;
  double t_k;
  double tremor_est;
  double x_power;
  int r;
  if (!isInitialized_BMFLC_step) {
    BMFLC_step_initialize();
  }
  /*  ================================================================ */
  /*   參數設定 */
  /*  ================================================================ */
  /*  NLMS 正規化學習率 */
  /*  頻率設定：3~12 Hz, 間距 0.5 Hz → 19 個頻率 */
  /*  38 維 */
  /*  ================================================================ */
  /*   持久性狀態變數 */
  /*  ================================================================ */
  /*   4 階因果帶通濾波 (DF-II Transposed) */
  /*  ================================================================ */
  residual = bp_b[0] * signal_sample + bp_z1;
  bp_z1 = (bp_b[1] * signal_sample - bp_a[1] * residual) + bp_z2;
  bp_z2 = (bp_b[2] * signal_sample - bp_a[2] * residual) + bp_z3;
  bp_z3 = (bp_b[3] * signal_sample - bp_a[3] * residual) + bp_z4;
  bp_z4 = bp_b[4] * signal_sample - bp_a[4] * residual;
  /*  ================================================================ */
  /*   NLMS 震顫估測 */
  /*  ================================================================ */
  t_k = k_count * dt;
  k_count++;
  /*  建構參考向量 x_k (38×1) */
  memset(&x_k[0], 0, 38U * sizeof(double));
  for (r = 0; r < 19; r++) {
    tremor_est =
        6.2831853071795862 * ((((double)r + 1.0) - 1.0) * 0.5 + 3.0) * t_k;
    x_k[r] = sin(tremor_est);
    x_k[r + 19] = cos(tremor_est);
  }
  /*  估測（用當前權重） */
  t_k = 0.0;
  /*  誤差 */
  /*  NLMS 權重更新 */
  x_power = 1.0E-8;
  for (r = 0; r < 38; r++) {
    tremor_est = x_k[r];
    t_k += w_k[r] * tremor_est;
    x_power += tremor_est * tremor_est;
  }
  e_k = residual - t_k;
  t_k = 1.0 / x_power;
  /*  輸出（使用更新後的權重） */
  tremor_est = 0.0;
  for (r = 0; r < 38; r++) {
    x_power = x_k[r];
    residual = w_k[r] + t_k * e_k * x_power;
    w_k[r] = residual;
    tremor_est += residual * x_power;
  }
  return tremor_est;
}

/*
 * Arguments    : void
 * Return Type  : void
 */
void BMFLC_step_init(void)
{
  static const double dv[5] = {0.17508764367210086, 0.0, -0.35017528734420172,
                               0.0, 0.17508764367210086};
  static const double dv1[5] = {1.0, -2.299055356038497, 1.9674977599844512,
                                -0.874805556449481, 0.21965398391369484};
  int i;
  for (i = 0; i < 5; i++) {
    bp_b[i] = dv[i];
    bp_a[i] = dv1[i];
  }
  memset(&w_k[0], 0, 38U * sizeof(double));
  k_count = 0.0;
  bp_z1 = 0.0;
  bp_z2 = 0.0;
  bp_z3 = 0.0;
  bp_z4 = 0.0;
  dt = 0.01;
}

/*
 * File trailer for BMFLC_step.c
 *
 * [EOF]
 */
