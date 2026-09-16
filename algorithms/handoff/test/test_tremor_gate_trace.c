#include "tremor_gate.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

/* CSV columns: scenario_id, zero_based_sample, raw_gyro_dps, MATLAB_enabled. */
int main(int argc, char **argv)
{
    FILE *fp;
    TremorGate gate;
    TremorGateConfig config = TremorGate_DefaultConfig();
    unsigned long row = 0;
    unsigned long mismatches = 0;
    int previous_scenario = -1;

    if (argc != 2) {
        fprintf(stderr, "usage: %s matlab_trace.csv\n", argv[0]);
        return 2;
    }

    fp = fopen(argv[1], "r");
    if (fp == NULL) {
        perror(argv[1]);
        return 2;
    }

    for (;;) {
        int scenario;
        unsigned long sample;
        double raw_gyro;
        unsigned expected;
        uint8_t actual;
        int fields = fscanf(fp, "%d,%lu,%lf,%u", &scenario, &sample,
                            &raw_gyro, &expected);

        if (fields == EOF) {
            break;
        }
        if (fields != 4) {
            fprintf(stderr, "malformed trace at row %lu\n", row + 1);
            fclose(fp);
            return 2;
        }
        if (scenario != previous_scenario) {
            TremorGate_Init(&gate, &config);
            previous_scenario = scenario;
        }

        actual = TremorGate_Update(&gate, raw_gyro);
        ++row;
        if (actual != (uint8_t)expected) {
            if (mismatches < 10) {
                fprintf(stderr,
                        "mismatch scenario=%d sample=%lu expected=%u actual=%u\n",
                        scenario, sample, expected, (unsigned)actual);
            }
            ++mismatches;
        }
    }

    fclose(fp);
    printf("V2 MATLAB/C pointwise: %lu samples, %lu mismatches\n",
           row, mismatches);
    return mismatches == 0 ? 0 : 1;
}
