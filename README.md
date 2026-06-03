# Sector51-Core

Production-grade MQL5 market-structure detection library. **No EA logic. No trade execution. No chart drawing.**

Pure detection engine that emits structured market events through clean interfaces.

---

## Architecture

```
Sector51Core/
├── Include/
│   └── Sector51/
│       ├── Sector51Core.mqh          ← single-include facade
│       ├── Core/
│       │   └── MarketStructure.mqh   ← enums, structs, interfaces
│       ├── Detectors/
│       │   ├── StructureDetector.mqh
│       │   ├── LiquidityDetector.mqh
│       │   ├── FVGDetector.mqh
│       │   └── OrderBlockDetector.mqh
│       └── Sessions/
│           └── SessionEngine.mqh
└── Scripts/
    └── Sector51_UsageExample.mq5
```

---

## Modules

### StructureDetector
| Feature | Detail |
|---|---|
| Swing detection | HH, HL, LH, LL via symmetric pivot lookback |
| BOS | Break of Structure on close (configurable) |
| CHoCH | Change of Character (counter-trend break) |
| Non-repainting | Confirmed only after N bars on each side |
| MTF | Instantiate one detector per timeframe |

### LiquidityDetector
| Feature | Detail |
|---|---|
| EQH / EQL | ATR-normalized proximity threshold |
| Sweeps | Wick beyond level + close inside = confirmed sweep |
| Threshold | `eq_threshold_atr` × ATR (Wilder, no indicator) |

### FVGDetector
| Feature | Detail |
|---|---|
| Pattern | 3-candle gap: `low[i] > high[i+2]` (bull), inverse (bear) |
| States | `ZONE_ACTIVE`, `ZONE_FILLED`, `ZONE_INVALIDATED` |
| Fill % | Continuous tracking (0–100%) |
| Invalidation | Close beyond gap boundary |

### OrderBlockDetector
| Feature | Detail |
|---|---|
| ICT definition | Last opposite candle before confirmed BOS |
| States | `ZONE_ACTIVE`, `ZONE_MITIGATED`, `ZONE_INVALIDATED` |
| Mitigation | Configurable % into OB body (default 50%) |
| Dependency | Requires `CStructureDetector` — pass by reference |

### SessionEngine
| Session | UTC Window |
|---|---|
| Sydney | 22:00 – 07:00 (crosses midnight) |
| Tokyo | 00:00 – 09:00 |
| London | 07:00 – 16:00 |
| New York | 12:00 – 21:00 |
| Metals (COMEX) | 13:30 – 18:15 |
| Crypto window | 00:00 – 04:00 (high-vol) |

All windows configurable via `SSessionProfile`. Broker UTC offset supported.

---

## Installation

1. Copy `Sector51Core/Include/Sector51/` → `MQL5/Include/Sector51/`
2. Copy `Sector51Core/Scripts/` → `MQL5/Scripts/`
3. Compile `Sector51_UsageExample.mq5` to verify (zero warnings expected)

---

## Quick Start

```mql5
#include <Sector51/Sector51Core.mqh>

CSector51Core g_core;

int OnInit()
{
   SSector51Config cfg;
   cfg.structure.swing_lookback = 3;
   cfg.session.utc_offset_hours = 0;
   return g_core.Init(cfg) ? INIT_SUCCEEDED : INIT_FAILED;
}

int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[],
                const double &high[], const double &low[],
                const double &close[], ...)
{
   SSector51Snapshot snap;
   if(g_core.Update(time, open, high, low, close, rates_total, snap))
   {
      if(snap.new_structure_event)
      {
         const SStructureEvent *ev = g_core.Structure().GetEvent(0);
         // use ev->event_type, ev->bias_after, ev->break_price ...
      }
      if(snap.new_fvg)
      {
         const SFVG *fvg = g_core.FVG().GetFVG(0);
         // use fvg->type, fvg->top, fvg->bottom, fvg->state ...
      }
   }
   return rates_total;
}
```

---

## Key Design Decisions

- **No repainting** — pivots confirmed only after `swing_lookback` bars on both sides
- **Series-mode arrays** — all arrays expected in `ArraySetAsSeries(true)` format (index 0 = current bar)
- **No globals / no chart objects** — pure computation, zero side effects
- **OOP** — each detector is an independent class; compose what you need
- **Configurable via structs** — no magic numbers in logic
- **MTF** — instantiate `CSector51Core` once per timeframe

---

## Plugging Into Other Systems

```
Indicators  →  #include <Sector51/Sector51Core.mqh>
Backtesters →  same include, drive Update() from your bar loop
Expert Advisors → same include, read snap / detector state, apply your own logic
```
