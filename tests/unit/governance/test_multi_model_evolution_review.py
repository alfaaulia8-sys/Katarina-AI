"""Multiple independently sourced AI reviews never bypass trading safety."""
import unittest
from katarina.governance.multi_model_evolution_review import (
    IndependentModelVerdict, review_candidate,
)

RECEIPT="a"*64
GOOD={"review_receipt_sha256":RECEIPT,"decision":"RESEARCH_PROPOSAL_ONLY",
      "reviewers":[{"reviewer":"data_integrity","pass":True},
                   {"reviewer":"quant_out_of_sample","pass":True},
                   {"reviewer":"broker_execution","pass":False},
                   {"reviewer":"engineering_review","pass":False}]}


def vote(provider="vendor-a",model="model-a",receipt=RECEIPT,verdict="APPROVE_RESEARCH"):
    return IndependentModelVerdict(provider,model,receipt,verdict,
                                   ("audit://cohort-statistics",),"check")


class ModelReviewTests(unittest.TestCase):
    def test_absent_external_models_never_pretends_review(self):
        x=review_candidate(GOOD)
        self.assertEqual(x.status,"REVIEW_BLOCKED")
        self.assertIn("no_external_models_connected",x.blockers)
        self.assertEqual(x.valid_reviews,0)

    def test_independent_models_can_only_review_research(self):
        x=review_candidate(GOOD,(vote(),vote("vendor-b","model-b")))
        self.assertEqual(x.status,"RESEARCH_IDEA_READY_FOR_ADDITIONAL_TESTS")
        self.assertFalse(x.real_execution_authorized)
        self.assertFalse(x.code_mutation_authorized)
        self.assertEqual(x.independent_providers,2)

    def test_duplicate_same_provider_not_independent(self):
        x=review_candidate(GOOD,(vote(),vote("vendor-a","model-b")))
        self.assertEqual(x.status,"REVIEW_BLOCKED")
        self.assertIn("two_independent_providers_required",x.blockers)

    def test_stale_review_blocks(self):
        x=review_candidate(GOOD,(vote(receipt="b"*64),vote("vendor-b","model-b")))
        self.assertEqual(x.status,"REVIEW_BLOCKED")
        self.assertIn("stale_or_invalid_model_verdict",x.blockers)

    def test_one_model_rejects(self):
        x=review_candidate(GOOD,(vote(),vote("vendor-b","model-b",verdict="REJECT")))
        self.assertEqual(x.status,"REVIEW_BLOCKED")
        self.assertIn("model_dissent_or_abstention",x.blockers)

    def test_quant_failure_prevents_external_overrides(self):
        bad={**GOOD,"reviewers":[{"reviewer":"quant_out_of_sample","pass":False}]}
        x=review_candidate(bad,(vote(),vote("vendor-b","model-b")))
        self.assertEqual(x.status,"REVIEW_BLOCKED")
        self.assertIn("statistical_or_data_review_not_passed",x.blockers)

    def test_invalid_receipt_fails(self):
        with self.assertRaises(ValueError):
            review_candidate({"review_receipt_sha256":"bad"})

if __name__=="__main__":
    unittest.main()

[executed on device: WIN-4TTT19K3CL8 (06bb71fa-caee-4271-a9ca-1e9cb7db4c2a)]
