"""Predictive evidence: no future-label leakage, no spurious promotions."""
import sys,unittest
from pathlib import Path
SCRIPTS=Path(__file__).resolve().parents[3]/"scripts"/"research"
sys.path.insert(0,str(SCRIPTS))
from evaluate_regime_prediction_ml import (
    chronological_split,make_features,scores,train_logistic,predict)
from compare_regime_gate_to_raw_setups import gate,metric
from build_quant_evidence_registry import registry

class QuantEvidenceUnitTests(unittest.TestCase):
    def test_purging_discards_training_horizon_overlapping_test(self):
        train_start=20000.
        rows=[
          dict(period="august",signal_time=4000.,label_end=6000.,y=1),
          dict(period="august",signal_time=6000.,label_end=15000.,y=0),
          dict(period="august",signal_time=7000.,label_end=21000.,y=1),
          dict(period="september",signal_time=train_start,label_end=23600.,y=1)]
        train,test=chronological_split(rows,("august",),"september")
        self.assertEqual(len(train),0)  # First finishes at 6000, +4h = 20400 > 20000
        self.assertEqual(len(test),1)
        rows[0]["label_end"]=3000.
        train,_=chronological_split(rows,("august",),"september")
        self.assertEqual(len(train),1)

    def test_source_features_ignore_future_result_and_label(self):
        from datetime import datetime,timezone
        clock=datetime(2026,8,20,14,tzinfo=timezone.utc).isoformat()
        frames={k:dict(direction="UP",adx14=25.,plus_di14=29.,
            minus_di14=17.,efficiency=.45) for k in ("M5","M15","H1")}
        a=dict(frames=frames,regime="CONTINUATION_UP",
               close_time_utc=clock,
               future_close_displacement={"1h":{"signed_directional_displacement_ATR":1.}})
        v=make_features(a,"technical_plus_regime")
        a["future_close_displacement"]["1h"]["signed_directional_displacement_ATR"]=-999999
        self.assertEqual(v,make_features(a,"technical_plus_regime"))
        self.assertEqual(len(v),21)

    def test_logistic_model_training_has_finite_probabilities(self):
        from datetime import datetime,timezone,timedelta
        stamps=[(datetime(2026,8,20,tzinfo=timezone.utc)+timedelta(minutes=30*i)).isoformat()
                for i in range(100)]
        frame=lambda sign: {k:dict(direction="UP" if sign else "DOWN",
            adx14=20.+sign*10,plus_di14=10+sign*20,minus_di14=25-sign*15,
            efficiency=.25+.2*sign) for k in ("M5","M15","H1")}
        rows=[dict(source=dict(frames=frame(i%2),regime=
                 "CONTINUATION_UP" if i%2 else "CONTINUATION_DOWN",
                 close_time_utc=stamps[i]),y=i%2) for i in range(100)]
        m=train_logistic(rows,"technical")
        p=predict(m,rows)
        self.assertEqual(len(p),100)
        self.assertTrue(all(.025<=v<=.975 for v in p))
        self.assertGreater(p[1],p[0])

    def test_Brier_must_score_probability_not_trade_winrate(self):
        out=scores([.8,.2],[1,0])
        self.assertAlmostEqual(out["brier"],.04)
        self.assertEqual(out["accuracy"],1.)

    def test_symbol_gate_does_not_swap_reversal_and_trend(self):
        self.assertTrue(gate("NAS100.vx","BUY","CONTINUATION_UP"))
        self.assertTrue(gate("NAS100.vx","BUY","PULLBACK_UP"))
        self.assertFalse(gate("NAS100.vx","BUY","CONTINUATION_DOWN"))
        self.assertFalse(gate("XAUUSD.vx","BUY","CONTINUATION_UP"))
        self.assertTrue(gate("XAUUSD.vx","BUY","REVERSAL_UP"))
        self.assertFalse(gate("JPN225.vx","BUY","SIDEWAYS"))

    def test_one_successful_gate_trade_must_not_validate_setup(self):
        self.assertEqual(metric([])["n"],0)
        self.assertAlmostEqual(metric([dict(R=1.5,
            entry_signal_close_utc="2026-10-05T10:00:00+00:00")])["mean_R"],1.5)

    def test_registry_refuses_live_enabled_archive(self):
        with self.assertRaisesRegex(ValueError,"do_not_register_live_predictions"):
            registry(dict(decision="LIVE"),dict(decision="NO_TRADE"))
        with self.assertRaisesRegex(ValueError,"do_not_register_live_predictions"):
            registry(dict(decision="NO_TRADE"),dict(decision="LIVE"))

if __name__=="__main__":
    unittest.main()
