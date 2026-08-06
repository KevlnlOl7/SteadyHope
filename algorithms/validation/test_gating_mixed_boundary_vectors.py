# -*- coding: utf-8 -*-

import unittest

from generate_gating_mixed_boundary_vectors import (
    CASES,
    SAMPLE_COUNT,
    make_vector,
    run_reference,
    summarize,
)


class GatingMixedBoundaryVectorTest(unittest.TestCase):
    def test_all_vectors_have_fixed_length(self):
        for case in CASES:
            self.assertEqual(len(make_vector(case)), SAMPLE_COUNT)

    def test_reference_results_cover_pass_and_difficult_cases(self):
        vectors = {case.case_id: make_vector(case) for case in CASES}
        summaries = {
            row["test_case_id"]: row for row in summarize(run_reference(vectors))
        }
        self.assertEqual(summaries["PURE_T15"]["reference_did_enable"], 1)
        self.assertEqual(summaries["MIX_V10_T10"]["reference_did_enable"], 0)
        self.assertEqual(summaries["MIX_V10_T20"]["reference_did_enable"], 1)
        self.assertEqual(summaries["MIX_V20_T20"]["reference_did_enable"], 0)
        self.assertTrue(all(row["final_enabled"] == 0 for row in summaries.values()))


if __name__ == "__main__":
    unittest.main()
