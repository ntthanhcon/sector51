//+------------------------------------------------------------------+
//|                                         LiquidityDetector.mqh   |
//|                                     Sector51-Core Library v1.0   |
//|  Detects: EQH, EQL, Liquidity Sweeps                            |
//|  ATR-normalized proximity thresholds                             |
//+------------------------------------------------------------------+
#pragma once
#ifndef LIQUIDITYDETECTOR_MQH
#define LIQUIDITYDETECTOR_MQH

#include "MarketStructure.mqh"

//+------------------------------------------------------------------+
//|  Configuration                                                    |
//+------------------------------------------------------------------+
struct SLiquidityConfig
{
   int    atr_period;           // ATR period for threshold normalization (default 14)
   double eq_threshold_atr;     // max ATR ratio for two highs/lows to be "equal" (default 0.1)
   int    lookback_bars;        // how many bars back to look for equal levels (default 100)
   int    max_levels;           // max stored liquidity levels (default 200)
   int    min_touches;          // min touches before level is flagged as EQH/EQL (default 2)

   SLiquidityConfig()
      : atr_period(14), eq_threshold_atr(0.1),
        lookback_bars(100), max_levels(200), min_touches(2) {}
};

//+------------------------------------------------------------------+
//|  LiquidityDetector                                                |
//+------------------------------------------------------------------+
class CLiquidityDetector
{
private:
   SLiquidityConfig  m_config;
   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;

   SLiquidityLevel   m_levels[];
   int               m_level_count;

   double            m_atr;   // last calculated ATR

   //--- Helpers
   double   CalcATR(const double &high[], const double &low[], const double &close[], int total);
   bool     IsEqual(double a, double b) const;
   int      FindNearestLevel(double price, bool check_highs) const;
   void     PushLevel(const SLiquidityLevel &lv);
   bool     CheckSweep(const double &high[], const double &low[], const double &close[],
                       int shift, int level_idx, SLiquidityLevel &updated);

public:
                     CLiquidityDetector();
                    ~CLiquidityDetector() {}

   bool              Init(const string symbol, ENUM_TIMEFRAMES tf, const SLiquidityConfig &cfg);
   bool              Update(const datetime &time[], const double &high[],
                            const double &low[], const double &close[], int total_bars);

   int                       GetLevelCount()         const { return m_level_count; }
   SLiquidityLevel           GetLevel(int idx)        const;
   double                    GetATR()                 const { return m_atr; }

   void              Reset();
};

//+------------------------------------------------------------------+
CLiquidityDetector::CLiquidityDetector()
   : m_symbol(""), m_timeframe(PERIOD_CURRENT), m_level_count(0), m_atr(0.0) {}

bool CLiquidityDetector::Init(const string symbol, ENUM_TIMEFRAMES tf, const SLiquidityConfig &cfg)
{
   m_symbol    = symbol;
   m_timeframe = tf;
   m_config    = cfg;
   ArrayResize(m_levels, m_config.max_levels);
   Reset();
   return true;
}

void CLiquidityDetector::Reset()
{
   m_level_count = 0;
   m_atr         = 0.0;
}

//+------------------------------------------------------------------+
//|  Wilder's ATR (manual, no indicator dependency)                  |
//+------------------------------------------------------------------+
double CLiquidityDetector::CalcATR(const double &high[], const double &low[],
                                    const double &close[], int total)
{
   int period = m_config.atr_period;
   if(total < period + 1) return 0.0;

   //--- Seed with simple average of first 'period' TRs
   double sum = 0.0;
   for(int i = total - 1; i >= total - period; i--)
   {
      double tr = MathMax(high[i], close[i + 1]) - MathMin(low[i], close[i + 1]);
      sum += tr;
   }
   double atr = sum / period;

   //--- Smooth remaining bars
   for(int i = total - period - 1; i >= 0; i--)
   {
      double tr = MathMax(high[i], close[i + 1]) - MathMin(low[i], close[i + 1]);
      atr = (atr * (period - 1) + tr) / period;
   }
   return atr;
}

bool CLiquidityDetector::IsEqual(double a, double b) const
{
   if(m_atr <= 0.0) return false;
   return MathAbs(a - b) <= m_atr * m_config.eq_threshold_atr;
}

//+------------------------------------------------------------------+
//|  Find existing level within ATR proximity                        |
//|  check_highs: true=look in EQH candidates, false=EQL            |
//+------------------------------------------------------------------+
int CLiquidityDetector::FindNearestLevel(double price, bool check_highs) const
{
   for(int i = 0; i < m_level_count; i++)
   {
      if(m_levels[i].swept) continue;
      bool is_high_level = (m_levels[i].event_type == LIQ_EQH || m_levels[i].event_type == LIQ_NONE);
      if(is_high_level != check_highs) continue;
      if(IsEqual(m_levels[i].price, price)) return i;
   }
   return -1;
}

void CLiquidityDetector::PushLevel(const SLiquidityLevel &lv)
{
   int cap = ArraySize(m_levels);
   if(m_level_count < cap)
   {
      m_levels[m_level_count++] = lv;
   }
   else
   {
      //--- Replace oldest swept level or oldest level
      int replace = 0;
      for(int i = 0; i < cap; i++)
         if(m_levels[i].swept) { replace = i; break; }
      m_levels[replace] = lv;
   }
}

//+------------------------------------------------------------------+
//|  Check if a level has been swept on this bar                     |
//+------------------------------------------------------------------+
bool CLiquidityDetector::CheckSweep(const double &high[], const double &low[],
                                     const double &close[], int shift, int level_idx,
                                     SLiquidityLevel &updated)
{
   updated = m_levels[level_idx];
   if(updated.swept) return false;

   bool is_high_level = (updated.event_type == LIQ_EQH);
   if(is_high_level)
   {
      //--- Wick above level but close below = sweep
      if(high[shift] > updated.price && close[shift] < updated.price)
      {
         updated.swept       = true;
         updated.event_type  = LIQ_SWEEP_HIGH;
         return true;
      }
   }
   else
   {
      if(low[shift] < updated.price && close[shift] > updated.price)
      {
         updated.swept       = true;
         updated.event_type  = LIQ_SWEEP_LOW;
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//|  Main update                                                      |
//+------------------------------------------------------------------+
bool CLiquidityDetector::Update(const datetime &time[], const double &high[],
                                 const double &low[], const double &close[], int total_bars)
{
   if(total_bars < m_config.atr_period + 2) return false;

   m_atr = CalcATR(high, low, close, total_bars);

   bool detected = false;
   int lookback = MathMin(m_config.lookback_bars, total_bars - 1);

   //--- Scan recent bars for new equal highs / lows
   //    We process bar at shift=1 (last completed bar)
   {
      int shift = 1;

      //--- Equal High check
      int idx_h = FindNearestLevel(high[shift], true);
      if(idx_h >= 0)
      {
         m_levels[idx_h].touch_count++;
         if(m_levels[idx_h].touch_count >= m_config.min_touches)
            m_levels[idx_h].event_type = LIQ_EQH;
         detected = true;
      }
      else
      {
         //--- Register as candidate
         SLiquidityLevel lv;
         lv.time         = time[shift];
         lv.price        = high[shift];
         lv.event_type   = LIQ_NONE; // candidate only
         lv.touch_count  = 1;
         lv.swept        = false;
         PushLevel(lv);
      }

      //--- Equal Low check
      int idx_l = FindNearestLevel(low[shift], false);
      if(idx_l >= 0)
      {
         m_levels[idx_l].touch_count++;
         if(m_levels[idx_l].touch_count >= m_config.min_touches)
            m_levels[idx_l].event_type = LIQ_EQL;
         detected = true;
      }
      else
      {
         SLiquidityLevel lv;
         lv.time         = time[shift];
         lv.price        = low[shift];
         lv.event_type   = LIQ_NONE;
         lv.touch_count  = 1;
         lv.swept        = false;
         PushLevel(lv);
      }
   }

   //--- Check sweeps on bar 1 (just closed)
   for(int i = 0; i < m_level_count; i++)
   {
      if(m_levels[i].event_type != LIQ_EQH && m_levels[i].event_type != LIQ_EQL) continue;

      SLiquidityLevel updated;
      if(CheckSweep(high, low, close, 1, i, updated))
      {
         updated.sweep_time = time[1];
         m_levels[i]        = updated;
         detected           = true;
      }
   }

   return detected;
}

SLiquidityLevel CLiquidityDetector::GetLevel(int idx) const
{
   SLiquidityLevel empty;
   if(idx < 0 || idx >= m_level_count) return empty;
   return m_levels[idx];
}

#endif // LIQUIDITYDETECTOR_MQH
