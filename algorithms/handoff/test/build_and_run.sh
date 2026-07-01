#!/bin/sh
# 在 PC 上編譯等價性測試並執行 (需要 gcc/clang)。
# 用法:  sh test/build_and_run.sh        # 從 handoff/ 目錄執行
set -e
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)
SRC="$ROOT/src"
CC="${CC:-gcc}"

"$CC" -O2 -std=c11 \
  -I"$SRC/bmflc" -I"$SRC/ehwflc" \
  "$HERE/test_equivalence.c" \
  "$SRC/bmflc/BMFLC_step.c" "$SRC/bmflc/BMFLC_step_data.c" "$SRC/bmflc/BMFLC_step_initialize.c" \
  "$SRC/ehwflc/eHWFLC_KF_step.c" "$SRC/ehwflc/eHWFLC_KF_step_data.c" "$SRC/ehwflc/eHWFLC_KF_step_initialize.c" \
  "$SRC/ehwflc/eye.c" \
  -lm -o "$HERE/test_equivalence"

"$HERE/test_equivalence" "$ROOT/golden"
