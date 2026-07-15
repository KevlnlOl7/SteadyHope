/*
 * Academic License - for use in teaching, academic research, and meeting
 * course requirements at degree granting institutions only.  Not for
 * government, commercial, or other organizational use.
 * File: eHWFLC_KF_step.c
 *
 * MATLAB Coder version            : 25.2
 * C/C++ source code generated on  : 01-Jul-2026 14:37:51
 */

/* Include Files */
#include "eHWFLC_KF_step.h"
#include "eHWFLC_KF_step_data.h"
#include "eHWFLC_KF_step_initialize.h"
#include "eye.h"
#include <math.h>
#include <string.h>

/* Variable Definitions */
static double phi_k;

static double omega_k;

static double w_wflc[6];

static double w_est[6];

static double P_est[36];

static double bp_z1;

static double bp_z2;

static double bp_z3;

static double bp_z4;

static double bp_b[5];

static double bp_a[5];

static double dt;

/* Function Definitions */
/*
 * eHWFLC_KF_STEP 單樣本 eHWFLC-KF 震顫估測（即時版本 v6）
 *
 *    [tremor_est, freq_hz] = eHWFLC_KF_step(signal_sample, fs_in)
 *
 *    v6 改進：支援動態 fs_in 輸入，預設為 100 Hz，並預存 50 Hz 與 100 Hz
 *    之 2-20 Hz 帶通濾波器係數，維持 C-codegen 相容性。
 *
 *    輸入:  signal_sample - 單一 IMU 樣本
 *           fs_in         - (可選) 取樣率 (預設 100 Hz)
 *    輸出:  tremor_est    - 估測震顫值
 *           freq_hz       - 估測基頻 (Hz)
 *
 * Arguments    : double signal_sample
 *                double *tremor_est
 *                double *freq_hz
 * Return Type  : void
 */
void eHWFLC_KF_step(double signal_sample, double *tremor_est, double *freq_hz)
{
  double P_pred[36];
  double U[36];
  double b_U[36];
  double K_k[6];
  double x_k[6];
  double b_x_k_tmp;
  double c_x_k_tmp;
  double d_x_k_tmp;
  double e_wflc;
  double e_x_k_tmp;
  double f_x_k_tmp;
  double residual;
  double s_hat_wflc;
  double x_k_tmp;
  int U_tmp;
  int b_i;
  int i;
  int j;
  if (!isInitialized_eHWFLC_KF_step) {
    eHWFLC_KF_step_initialize();
  }
  /*  ================================================================ */
  /*   參數設定 */
  /*  ================================================================ */
  /*  諧波階數 */
  /*  狀態維度 = 6 */
  /*  WFLC 參數 */
  /*  KF 參數 */
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
  /*   WFLC 頻率追蹤 */
  /*  ================================================================ */
  phi_k += omega_k * dt;
  x_k_tmp = sin(phi_k);
  x_k[0] = x_k_tmp;
  b_x_k_tmp = cos(phi_k);
  x_k[3] = b_x_k_tmp;
  s_hat_wflc = 2.0 * phi_k;
  c_x_k_tmp = sin(s_hat_wflc);
  x_k[1] = c_x_k_tmp;
  d_x_k_tmp = cos(s_hat_wflc);
  x_k[4] = d_x_k_tmp;
  s_hat_wflc = 3.0 * phi_k;
  e_x_k_tmp = sin(s_hat_wflc);
  x_k[2] = e_x_k_tmp;
  f_x_k_tmp = cos(s_hat_wflc);
  x_k[5] = f_x_k_tmp;
  s_hat_wflc = 0.0;
  for (i = 0; i < 6; i++) {
    s_hat_wflc += w_wflc[i] * x_k[i];
  }
  e_wflc = residual - s_hat_wflc;
  omega_k += 0.01 * e_wflc *
             (((w_wflc[0] * b_x_k_tmp - w_wflc[3] * x_k_tmp) +
               2.0 * (w_wflc[1] * d_x_k_tmp - w_wflc[4] * c_x_k_tmp)) +
              3.0 * (w_wflc[2] * f_x_k_tmp - w_wflc[5] * e_x_k_tmp));
  if (omega_k < 18.849555921538759) {
    omega_k = 18.849555921538759;
  } else if (omega_k > 75.398223686155035) {
    omega_k = 75.398223686155035;
  }
  for (i = 0; i < 6; i++) {
    w_wflc[i] += 0.02 * e_wflc * x_k[i];
  }
  /*  ================================================================ */
  /*   高階 Kalman Filter */
  /*  ================================================================ */
  memset(&U[0], 0, 36U * sizeof(double));
  s_hat_wflc = omega_k * dt;
  e_wflc = cos(s_hat_wflc);
  s_hat_wflc = sin(s_hat_wflc);
  U[0] = e_wflc;
  U[6] = s_hat_wflc;
  U[1] = -s_hat_wflc;
  U[7] = e_wflc;
  x_k[0] = x_k_tmp;
  x_k[1] = b_x_k_tmp;
  s_hat_wflc = 2.0 * omega_k * dt;
  e_wflc = cos(s_hat_wflc);
  s_hat_wflc = sin(s_hat_wflc);
  U[14] = e_wflc;
  U[20] = s_hat_wflc;
  U[15] = -s_hat_wflc;
  U[21] = e_wflc;
  x_k[2] = c_x_k_tmp;
  x_k[3] = d_x_k_tmp;
  s_hat_wflc = 3.0 * omega_k * dt;
  e_wflc = cos(s_hat_wflc);
  s_hat_wflc = sin(s_hat_wflc);
  U[28] = e_wflc;
  U[34] = s_hat_wflc;
  U[29] = -s_hat_wflc;
  U[35] = e_wflc;
  x_k[4] = e_x_k_tmp;
  x_k[5] = f_x_k_tmp;
  /*  KF 預測 */
  memset(&K_k[0], 0, 6U * sizeof(double));
  for (i = 0; i < 6; i++) {
    for (j = 0; j < 6; j++) {
      K_k[j] += U[j + 6 * i] * w_est[i];
    }
  }
  memset(&b_U[0], 0, 36U * sizeof(double));
  for (i = 0; i < 6; i++) {
    w_est[i] = K_k[i];
    for (j = 0; j < 6; j++) {
      s_hat_wflc = P_est[j + 6 * i];
      for (b_i = 0; b_i < 6; b_i++) {
        U_tmp = b_i + 6 * i;
        b_U[U_tmp] += U[b_i + 6 * j] * s_hat_wflc;
      }
    }
  }
  memset(&P_pred[0], 0, 36U * sizeof(double));
  for (i = 0; i < 6; i++) {
    for (j = 0; j < 6; j++) {
      s_hat_wflc = U[i + 6 * j];
      for (b_i = 0; b_i < 6; b_i++) {
        U_tmp = b_i + 6 * i;
        P_pred[U_tmp] += b_U[b_i + 6 * j] * s_hat_wflc;
      }
    }
  }
  for (i = 0; i < 6; i++) {
    U_tmp = i + 6 * i;
    P_pred[U_tmp] += 0.01;
  }
  /*  KF 更新 */
  s_hat_wflc = 0.05;
  for (i = 0; i < 6; i++) {
    for (j = 0; j < 6; j++) {
      s_hat_wflc += x_k[i] * P_pred[i + 6 * j] * x_k[j];
    }
  }
  for (i = 0; i < 6; i++) {
    e_wflc = 0.0;
    for (j = 0; j < 6; j++) {
      e_wflc += P_pred[i + 6 * j] * x_k[j];
    }
    K_k[i] = e_wflc / s_hat_wflc;
    residual -= x_k[i] * w_est[i];
  }
  /*  P 更新 */
  eye(U);
  for (i = 0; i < 6; i++) {
    w_est[i] += K_k[i] * residual;
    for (j = 0; j < 6; j++) {
      U_tmp = j + 6 * i;
      b_U[U_tmp] = U[U_tmp] - K_k[j] * x_k[i];
    }
  }
  memset(&P_est[0], 0, 36U * sizeof(double));
  for (i = 0; i < 6; i++) {
    for (j = 0; j < 6; j++) {
      s_hat_wflc = P_pred[j + 6 * i];
      for (b_i = 0; b_i < 6; b_i++) {
        U_tmp = b_i + 6 * i;
        P_est[U_tmp] += b_U[b_i + 6 * j] * s_hat_wflc;
      }
    }
  }
  for (i = 0; i < 6; i++) {
    for (j = 0; j < 6; j++) {
      U_tmp = j + 6 * i;
      U[U_tmp] = (P_est[U_tmp] + P_est[i + 6 * j]) * 0.5;
    }
  }
  memcpy(&P_est[0], &U[0], 36U * sizeof(double));
  /*  ================================================================ */
  /*   輸出 */
  /*  ================================================================ */
  *tremor_est = 0.0;
  for (i = 0; i < 6; i++) {
    *tremor_est += x_k[i] * w_est[i];
  }
  *freq_hz = omega_k / 6.2831853071795862;
}

/*
 * Arguments    : void
 * Return Type  : void
 */
void eHWFLC_KF_step_init(void)
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
  phi_k = 0.0;
  omega_k = 31.415926535897931;
  for (i = 0; i < 6; i++) {
    w_wflc[i] = 0.0;
    w_est[i] = 0.0;
  }
  eye(P_est);
  bp_z1 = 0.0;
  bp_z2 = 0.0;
  bp_z3 = 0.0;
  bp_z4 = 0.0;
  /*  預設 100 Hz */
  dt = 0.01;
}

/*
 * File trailer for eHWFLC_KF_step.c
 *
 * [EOF]
 */
