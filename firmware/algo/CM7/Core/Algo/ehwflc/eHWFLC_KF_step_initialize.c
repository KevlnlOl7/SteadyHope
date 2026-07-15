/*
 * Academic License - for use in teaching, academic research, and meeting
 * course requirements at degree granting institutions only.  Not for
 * government, commercial, or other organizational use.
 * File: eHWFLC_KF_step_initialize.c
 *
 * MATLAB Coder version            : 25.2
 * C/C++ source code generated on  : 01-Jul-2026 14:37:51
 */

/* Include Files */
#include "eHWFLC_KF_step_initialize.h"
#include "eHWFLC_KF_step.h"
#include "eHWFLC_KF_step_data.h"

/* Function Definitions */
/*
 * Arguments    : void
 * Return Type  : void
 */
void eHWFLC_KF_step_initialize(void)
{
  eHWFLC_KF_step_init();
  isInitialized_eHWFLC_KF_step = true;
}

/*
 * File trailer for eHWFLC_KF_step_initialize.c
 *
 * [EOF]
 */
