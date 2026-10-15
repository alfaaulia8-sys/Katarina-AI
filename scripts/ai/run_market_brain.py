"""Disabled legacy observer entry point. Use the single canonical brain CLI.

Kept only to make stale scheduled commands fail visibly, without starting
another worker, touching old state or loading a broker terminal.
"""

def main():
    raise SystemExit(
        "LEGACY_OBSERVER_DISABLED: use scripts/ai/run_contextual_market_observer.py; "
        "do not run a second observer or migrate its private state automatically")


if __name__ == "__main__":
    main()
