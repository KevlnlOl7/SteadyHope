/*
 * test_equivalence.c
 * ------------------------------------------------------------
 * 黃金向量等價性測試 (Model-in-the-Loop equivalence check)
 *
 * 用途: 證明「在 STM32 上會跑的這份 C」逐點等於 MATLAB 模型。
 *       讀 golden/input.csv 餵進 BMFLC_step / eHWFLC_KF_step,
 *       與 golden/golden_*.csv (MATLAB 產生) 比對, 印 max|err| 與 PASS/FAIL。
 *
 * 這是「驗證演算法有沒有用」的第一關: 先確定移植沒改變數值,
 * 再去信任硬體上的即時 / 閉迴路結果。
 *
 * 用法:  test_equivalence [golden_dir]
 *        golden_dir 預設為 "." ; build_and_run 腳本會帶入 ../golden。
 * 回傳:  0 = 全部 PASS, 1 = 有 FAIL, 2 = 檔案/長度錯誤。
 * ------------------------------------------------------------
 */
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include "BMFLC_step.h"
#include "eHWFLC_KF_step.h"

#define MAXN     200000
#define ABS_TOL  1e-6   /* 容差: PC 交叉驗證為 ~1e-14, ARM scalar 應 <=1e-12, 餘裕充足 */

static int load1(const char *path, double *a) {
    FILE *f = fopen(path, "r");
    if (!f) { fprintf(stderr, "[ERR] 無法開啟 %s\n", path); exit(2); }
    int n = 0; char line[256];
    while (fgets(line, sizeof line, f)) {
        if (line[0] == '\n' || line[0] == '\r' || line[0] == '\0') continue;
        if (n >= MAXN) break;
        a[n++] = strtod(line, NULL);
    }
    fclose(f); return n;
}

static int load2(const char *path, double *a, double *b) {
    FILE *f = fopen(path, "r");
    if (!f) { fprintf(stderr, "[ERR] 無法開啟 %s\n", path); exit(2); }
    int n = 0; char line[256];
    while (fgets(line, sizeof line, f)) {
        if (line[0] == '\n' || line[0] == '\r' || line[0] == '\0') continue;
        if (n >= MAXN) break;
        char *p;
        a[n] = strtod(line, &p);
        while (*p == ',' || *p == ' ') p++;
        b[n] = strtod(p, NULL);
        n++;
    }
    fclose(f); return n;
}

int main(int argc, char **argv) {
    static double in[MAXN], gb[MAXN], ge_t[MAXN], ge_f[MAXN];
    const char *dir = (argc > 1) ? argv[1] : ".";
    char p[600];

    snprintf(p, sizeof p, "%s/input.csv", dir);         int N  = load1(p, in);
    snprintf(p, sizeof p, "%s/golden_bmflc.csv", dir);  int Nb = load1(p, gb);
    snprintf(p, sizeof p, "%s/golden_ehwflc.csv", dir); int Ne = load2(p, ge_t, ge_f);

    if (N != Nb || N != Ne || N == 0) {
        fprintf(stderr, "[ERR] 長度不符: input=%d bmflc=%d ehwflc=%d\n", N, Nb, Ne);
        return 2;
    }

    double mb = 0.0, met = 0.0, mef = 0.0;
    for (int k = 0; k < N; k++) {
        double bm = BMFLC_step(in[k]);
        double tr, fr;
        eHWFLC_KF_step(in[k], &tr, &fr);
        /* 用 !(e<=max) 而非 (e>max): 讓 NaN 也傳進 max -> 後面判定 FAIL (NaN>max 恆 false 會漏抓) */
        double e1 = fabs(bm - gb[k]);   if (!(e1 <= mb))  mb  = e1;
        double e2 = fabs(tr - ge_t[k]); if (!(e2 <= met)) met = e2;
        double e3 = fabs(fr - ge_f[k]); if (!(e3 <= mef)) mef = e3;
    }

    int pb = mb  < ABS_TOL, pet = met < ABS_TOL, pef = mef < ABS_TOL;
    printf("------------------------------------------------------------\n");
    printf(" 等價性測試: C  vs  MATLAB 黃金向量   (N=%d, tol=%.0e)\n", N, ABS_TOL);
    printf("------------------------------------------------------------\n");
    printf("  BMFLC  tremor   max|err| = %.3e   %s\n", mb,  pb  ? "PASS" : "FAIL");
    printf("  eHWFLC tremor   max|err| = %.3e   %s\n", met, pet ? "PASS" : "FAIL");
    printf("  eHWFLC freq     max|err| = %.3e   %s\n", mef, pef ? "PASS" : "FAIL");
    printf("------------------------------------------------------------\n");

    int ok = pb && pet && pef;
    printf(" ==> %s\n", ok ? "ALL PASS  — C 輸出等於 MATLAB 模型"
                           : "FAIL  — 移植與模型不一致, 請檢查");
    return ok ? 0 : 1;
}
