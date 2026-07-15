/*
 * Academic License - for use in teaching, academic research, and meeting
 * course requirements at degree granting institutions only.  Not for
 * government, commercial, or other organizational use.
 * File: BMFLC_step_initialize.c
 *
 * MATLAB Coder version            : 25.2
 * C/C++ source code generated on  : 01-Jul-2026 14:37:38
 */

/* Include Files */
#include "BMFLC_step_initialize.h"
#include "BMFLC_step.h"
#include "BMFLC_step_data.h"

/* Function Definitions */
/*
 * Arguments    : void
 * Return Type  : void
 */
void BMFLC_step_initialize(void)
{
  BMFLC_step_init();
  isInitialized_BMFLC_step = true;
}

/*
 * File trailer for BMFLC_step_initialize.c
 *
 * [EOF]
 */
