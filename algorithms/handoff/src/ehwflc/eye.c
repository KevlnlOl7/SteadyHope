/*
 * Academic License - for use in teaching, academic research, and meeting
 * course requirements at degree granting institutions only.  Not for
 * government, commercial, or other organizational use.
 * File: eye.c
 *
 * MATLAB Coder version            : 25.2
 * C/C++ source code generated on  : 01-Jul-2026 14:37:51
 */

/* Include Files */
#include "eye.h"
#include <string.h>

/* Function Definitions */
/*
 * Arguments    : double b_I[36]
 * Return Type  : void
 */
void eye(double b_I[36])
{
  int k;
  memset(&b_I[0], 0, 36U * sizeof(double));
  for (k = 0; k < 6; k++) {
    b_I[k + 6 * k] = 1.0;
  }
}

/*
 * File trailer for eye.c
 *
 * [EOF]
 */
