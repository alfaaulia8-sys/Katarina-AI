"""Compatibility CLI: all observation lifecycle is owned by one Katarina brain."""
from pathlib import Path
import argparse
import json
import sys

sys.path.insert(0,str(Path(__file__).resolve().parents[2]/"src"))
from katarina.intelligence.unified_brain import UnifiedKatarinaBrain


def observe(root, *, max_symbols=17, fetch_news=True):
    return UnifiedKatarinaBrain.observe_once(
        Path(root), max_symbols=max_symbols, fetch_news=fetch_news)


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--state-dir",default=r"C:\KatarinaDev\artifacts\contextual-observer")
    parser.add_argument("--max-symbols",type=int,default=17)
    parser.add_argument("--no-fetch",action="store_true")
    args=parser.parse_args()
    if not 1<=args.max_symbols<=17:parser.error("max 17 broker markets")
    result=observe(Path(args.state_dir),max_symbols=args.max_symbols,fetch_news=not args.no_fetch)
    print("KATARINA_CONTEXTUAL_ONE_PASS",json.dumps(result,sort_keys=True),flush=True)


if __name__=="__main__":
    main()
