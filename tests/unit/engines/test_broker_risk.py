import unittest

from katarina.engines.broker_risk import BrokerNativeRiskBook, BrokerRiskRequest


class BrokerRiskTests(unittest.TestCase):
    def test_broker_calc_report_becomes_native_loss(self):
        b=BrokerNativeRiskBook()
        req=BrokerRiskRequest("abc","position:7","BUY",1,1,.1,2000,1990)
        b.register(req)
        e=b.observe_report({"calc_request_id":"abc","profit_valid":1,"profit_units":-25000},money_scale=2)
        self.assertTrue(e.valid)
        self.assertAlmostEqual(e.loss_native,250)
        self.assertAlmostEqual(b.loss_for("position:7"),250)

    def test_invalid_report_fails_closed(self):
        b=BrokerNativeRiskBook(); b.register(BrokerRiskRequest("a","x","BUY",1,1,.1,1,1))
        self.assertFalse(b.observe_report({"calc_request_id":"a","profit_valid":0},money_scale=2).valid)


if __name__=="__main__": unittest.main()
