Create a production-grade MQL5 project called Sector51-Core.
IMPORTANT:
Do NOT create an Expert Advisor.
Do NOT create any trade execution logic.
Do NOT create lot sizing.
Do NOT create risk management.
The goal is to build a reusable detection library.
Architecture requirements:

1. StructureDetector

* Detect HH, HL, LH, LL
* Detect BOS
* Detect CHOCH
* Non-repainting
* Multi-timeframe support

1. LiquidityDetector

* Detect EQH
* Detect EQL
* Detect Liquidity Sweeps
* ATR-normalized thresholds

1. FVGDetector

* Detect bullish and bearish FVG
* Track active, filled, invalidated states

1. OrderBlockDetector

* ICT-style order blocks
* Last opposite candle before BOS
* Track active, mitigated, invalidated

1. SessionEngine

* Forex sessions
* Metal sessions
* Crypto sessions
* Configurable profiles
Requirements:

* MQL5
* OOP architecture
* Separate .mqh files
* No chart drawing
* No indicators
* No EA logic
* No trade logic
Output only structured market events through clean interfaces.
The result must be a reusable market-structure library that can later be plugged into indicators, backtest engines, or Expert Advisors.