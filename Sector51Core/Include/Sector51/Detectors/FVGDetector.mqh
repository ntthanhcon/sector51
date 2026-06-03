//+------------------------------------------------------------------+
//|                                              FVGDetector.mqh     |
//|                                     Sector51-Core Library v1.0   |
//|  Detects bullish / bearish Fair Value Gaps                       |
//|  Tracks: active, filled, invalidated states                      |
//+------------------------------------------------------------------+
#pragma once
#ifndef FVGDETECTOR_MQH
#define FVGDETECTOR_MQH

#include "MarketStructure.mqh"

//+------------------------------------------------------------------+
//|  Configuration                                                    |
//+------------------------------------------------------------------+
struct SFVGConfig
{
   int     max_fvgs;             // max FVGs to track (default 100)
   double  min_size_points;      // minimum FVG size in points (0 = no filter)
   bool    remove_on_fill;       // remove from array once 100% filled
   bool    invalidate_on_close;  // invalidate if opposite close violates top/bottom

   SFVGConfig()
      : max_fvgs(100), min_size_points(0.0),
        remove_on_fill(false), invalidate_on_close(true) {}
};

//+------------------------------------------------------------------+
//|  FVGDetector                                                      |
//+------------------------------------------------------------------+
class CFVGDetector
{
private:
   SFVGConfig        m_config;
   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;

   SFVG              m_fvgs[];
   int               m_fvg_count;

   double            m_point;   // symbol point size

   //--- Helpers
   bool     DetectNewFVG(const datetime &time[], const double &high[], const double &low[],
                         int shift, SFVG &out);
   void     UpdateStates(const double &high[], const double &low[], const double &close[], int shift);
   void     PushFVG(const SFVG &fvg);
   double   CalcFillPercent(const SFVG &fvg, const double &high[], const double &low[], int shift);

public:
                     CFVGDetector();
                    ~CFVGDetector() {}

   bool              Init(const string symbol, ENUM_TIMEFRAMES tf, const SFVGConfig &cfg);
   bool              Update(const datetime &time[], const double &high[],
                            const double &low[], const double &close[], int total_bars);

   int               GetFVGCount()           const { return m_fvg_count; }
   const SFVG*       GetFVG(int idx)          const;
   void              Reset();
};

//+------------------------------------------------------------------+
CFVGDetector::CFVGDetector()
   : m_symbol(""), m_timeframe(PERIOD_CURRENT), m_fvg_count(0), m_point(0.00001) {}

bool CFVGDetector::Init(const string symbol, ENUM_TIMEFRAMES tf, const SFVGConfig &cfg)
{
   m_symbol    = symbol;
   m_timeframe = tf;
   m_config    = cfg;
   m_point     = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(m_point <= 0.0) m_point = 0.00001;
   ArrayResize(m_fvgs, m_config.max_fvgs);
   Reset();
   return true;
}

void CFVGDetector::Reset()
{
   m_fvg_count = 0;
}

//+------------------------------------------------------------------+
//|  FVG pattern: 3-candle                                           |
//|  Bullish FVG: low[shift] > high[shift+2]  (gap between c1 & c3) |
//|  Bearish FVG: high[shift] < low[shift+2]                        |
//|  shift = index of the third candle (newest of the 3)            |
//+------------------------------------------------------------------+
bool CFVGDetector::DetectNewFVG(const datetime &time[], const double &high[],
                                 const double &low[], int shift, SFVG &out)
{
   if(shift + 2 >= ArraySize(high)) return false;

   //--- Bullish FVG
   if(low[shift] > high[shift + 2])
   {
      double size = (low[shift] - high[shift + 2]);
      if(size < m_config.min_size_points * m_point) return false;

      out.time       = time[shift + 1]; // middle candle
      out.top        = low[shift];
      out.bottom     = high[shift + 2];
      out.type       = FVG_BULLISH;
      out.state      = ZONE_ACTIVE;
      out.fill_percent = 0.0;
      out.bar_index  = shift;
      return true;
   }

   //--- Bearish FVG
   if(high[shift] < low[shift + 2])
   {
      double size = (low[shift + 2] - high[shift]);
      if(size < m_config.min_size_points * m_point) return false;

      out.time       = time[shift + 1];
      out.top        = low[shift + 2];
      out.bottom     = high[shift];
      out.type       = FVG_BEARISH;
      out.state      = ZONE_ACTIVE;
      out.fill_percent = 0.0;
      out.bar_index  = shift;
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
double CFVGDetector::CalcFillPercent(const SFVG &fvg, const double &high[],
                                      const double &low[], int shift)
{
   double range = fvg.top - fvg.bottom;
   if(range <= 0.0) return 100.0;

   if(fvg.type == FVG_BULLISH)
   {
      //--- Fill from above: price retraces down into the gap
      double filled = fvg.top - MathMax(low[shift], fvg.bottom);
      return MathMin(100.0, (filled / range) * 100.0);
   }
   else
   {
      //--- Fill from below: price retraces up into the gap
      double filled = MathMin(high[shift], fvg.top) - fvg.bottom;
      return MathMin(100.0, (filled / range) * 100.0);
   }
}

//+------------------------------------------------------------------+
void CFVGDetector::UpdateStates(const double &high[], const double &low[],
                                 const double &close[], int shift)
{
   for(int i = 0; i < m_fvg_count; i++)
   {
      if(m_fvgs[i].state != ZONE_ACTIVE) continue;

      m_fvgs[i].fill_percent = CalcFillPercent(m_fvgs[i], high, low, shift);

      if(m_fvgs[i].fill_percent >= 100.0)
      {
         m_fvgs[i].state = ZONE_FILLED;
         continue;
      }

      if(m_config.invalidate_on_close)
      {
         //--- Bullish FVG invalidated if price closes below its bottom
         if(m_fvgs[i].type == FVG_BULLISH && close[shift] < m_fvgs[i].bottom)
            m_fvgs[i].state = ZONE_INVALIDATED;
         //--- Bearish FVG invalidated if price closes above its top
         else if(m_fvgs[i].type == FVG_BEARISH && close[shift] > m_fvgs[i].top)
            m_fvgs[i].state = ZONE_INVALIDATED;
      }
   }
}

//+------------------------------------------------------------------+
void CFVGDetector::PushFVG(const SFVG &fvg)
{
   int cap = ArraySize(m_fvgs);
   if(m_fvg_count < cap)
   {
      m_fvgs[m_fvg_count++] = fvg;
      return;
   }
   //--- Replace oldest filled/invalidated slot
   for(int i = 0; i < cap; i++)
   {
      if(m_fvgs[i].state != ZONE_ACTIVE)
      {
         m_fvgs[i] = fvg;
         return;
      }
   }
   //--- All active: replace oldest (index 0, shift everything)
   for(int i = 0; i < cap - 1; i++) m_fvgs[i] = m_fvgs[i + 1];
   m_fvgs[cap - 1] = fvg;
}

//+------------------------------------------------------------------+
//|  Main update (call on every new bar)                             |
//+------------------------------------------------------------------+
bool CFVGDetector::Update(const datetime &time[], const double &high[],
                           const double &low[], const double &close[], int total_bars)
{
   if(total_bars < 3) return false;

   bool detected = false;

   //--- Check for new FVG formed by bars 1,2,3 (shift=1 = most recent completed candle)
   SFVG new_fvg;
   if(DetectNewFVG(time, high, low, 1, new_fvg))
   {
      PushFVG(new_fvg);
      detected = true;
   }

   //--- Update states for all active FVGs on bar 1
   UpdateStates(high, low, close, 1);

   return detected;
}

const SFVG* CFVGDetector::GetFVG(int idx) const
{
   if(idx < 0 || idx >= m_fvg_count) return NULL;
   return &m_fvgs[idx];
}

#endif // FVGDETECTOR_MQH
