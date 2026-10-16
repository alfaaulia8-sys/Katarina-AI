from datetime import datetime,timezone,timedelta
from hashlib import sha256
import sqlite3
import unittest
from katarina.intelligence.research_news_collection import collect,parse_feed,event_study,allowed
from katarina.intelligence.observational_associations import observe_associations


class ResearchNewsTests(unittest.TestCase):
    def setUp(self):
        self.db=sqlite3.connect(':memory:')
        self.now=datetime.now(timezone.utc)
    def tearDown(self):self.db.close()

    def test_rss_and_rdf_feed_dates_and_hosts(self):
        date=(self.now-timedelta(hours=1)).isoformat()
        xml=f'<rss><channel><item><title>Policy</title><link>https://www.rba.gov.au/media.html</link><pubDate>{date}</pubDate></item></channel></rss>'.encode()
        self.assertEqual(len(parse_feed(xml,'www.rba.gov.au',self.now)),1)
        self.assertEqual(parse_feed(xml,'other.example',self.now),[])
        rdf=f'<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns="http://purl.org/rss/1.0/" xmlns:dc="http://purl.org/dc/elements/1.1/"><item><title>Policy</title><link>https://www.rba.gov.au/media.html</link><dc:date>{date}</dc:date></item></rdf:RDF>'.encode()
        self.assertEqual(len(parse_feed(rdf,'www.rba.gov.au',self.now)),1)
        self.assertFalse(allowed('https://www.rba.gov.au@127.0.0.1/file','www.rba.gov.au'))

    def test_real_body_required_cached_and_first_seen_not_backdated(self):
        date=(self.now-timedelta(days=1)).isoformat()
        calls=[]
        def exchange(url,host):
            calls.append(url)
            if '/feed/' in url or '/rss/' in url:
                return f'<rss><channel><item><title>Policy</title><link>https://{host}/statement</link><pubDate>{date}</pubDate></item></channel></rss>'.encode()
            return ('<html>'+''.join('<p>'+'policy economy inflation '*40+'</p>' for _ in range(3))+'</html>').encode()
        result=collect(self.db,self.now,exchange=exchange)
        self.assertEqual(result['status'],'FULL_BODY_STORED')
        row=result['new_documents'][0]
        self.assertGreater(datetime.fromisoformat(row['known_utc']),datetime.fromisoformat(date))
        self.assertFalse(row['semantic_interpretation_verified'])
        collect(self.db,self.now,exchange=exchange)
        before=len(calls)
        result=collect(self.db,self.now,exchange=exchange)
        self.assertEqual(result['status'],'CACHED')
        self.assertEqual(len(calls),before)

    def test_event_study_waits_for_future_and_reports_observed_reaction(self):
        collect(self.db,self.now,exchange=lambda *a:b'<rss/>')
        known=self.now-timedelta(hours=2)
        body='body'
        self.db.execute('INSERT INTO research_news_documents VALUES(?,?,?,?,?,?,?,?)',
            ('id','boc','https://www.bankofcanada.ca/a',known.isoformat(),known.isoformat(),body,sha256(body.encode()).hexdigest(),'summary'))
        for seconds,mid in [(0,100),(900,101),(3600,99)]:
            clock=known+timedelta(seconds=seconds)
            observe_associations(self.db,{'A':(mid,mid,clock.timestamp())},clock)
        result=event_study(self.db,self.now)
        self.assertEqual(len(result['groups']),2)
        self.assertAlmostEqual(result['groups'][0]['mean_mid_return_bps'],100)
        self.assertEqual(result['groups'][0]['status'],'INSUFFICIENT_EVENTS')
        self.assertFalse(result['causality_proven'])
        self.assertFalse(result['strategy_validated'])

    def test_missing_quotes_are_not_invented(self):
        collect(self.db,self.now,exchange=lambda *a:b'<rss/>')
        result=event_study(self.db,self.now)
        self.assertEqual(result['status'],'WAITING_FOR_DATA')
