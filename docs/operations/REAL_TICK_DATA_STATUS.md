# Real-Tick Data Status

Status: **broker tick cache discovered; Python adapter installed; service-session MT5 IPC unavailable**.

VPS evidence discovered local Valetax XAUUSD tick-cache files covering **July 2024 through September 2026**, plus XAUUSD/XAUUSDc bar history from Valetax and HFM.

The KATARINA portable runtime now includes:
- Python 3.12.10;
- MetaTrader5 5.0.6231;
- NumPy 2.5.3;
- a lazy read-only MT5 tick adapter;
- a tick-by-tick KATARINA backtest engine using the same 80% partial / 30% peak-profit trail logic as position management.

A read-only IPC probe from the Windows service session could not attach to the interactive MT5 terminals. The generic terminal returned IPC timeout and the ALFA terminal did not answer its pipe. This is treated as an environment/session boundary, not as absence of tick data.

No credential bypass is attempted. The historical cache remains available for Strategy Tester/interactive-terminal validation, and the adapter is ready when the runtime runs in an MT5-accessible user session.

Economic-calendar integration remains fail-closed until a fresh provider snapshot is available.
