//+------------------------------------------------------------------+
//|                                          StructureDetector.mqh   |
//|                                     Sector51-Core Library v1.0   |
//|  Detects: HH, HL, LH, LL, BOS, CHoCH                            |
//|  Non-repainting. Multi-timeframe ready.                          |
//+------------------------------------------------------------------+

#ifndef STRUCTUREDETECTOR_MQH
#define STRUCTUREDETECTOR_MQH

#include <Sector51/Core/MarketStructure.mqh>

//+------------------------------------------------------------------+
//|  Configuration                                                    |
//+------------------------------------------------------------------+
struct SStructureConfig
{
   int   swing_lookback;       // bars left+right for pivot confirmation (default 3)
   int   max_swings;           // max swing history to retain
   int   max_events;           // max structure events to retain
   bool  require_close;        // BOS confirmed on close vs wick

   SStructureConfig() : swing_lookback(3), max_swings(100), max_events(50), require_close(true) {}
};

//+------------------------------------------------------------------+
//|  StructureDetector                                                |
//+------------------------------------------------------------------+
class CStructureDetector
{
private:
   SStructureConfig  m_config;
   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;

   SSwingPoint       m_swings[];    // ordered newest-first
   SStructureEvent   m_events[];

   //--- Internal tracking
   double            m_last_swing_high;
   double            m_last_swing_low;
   ENUM_TREND_BIAS   m_current_bias;
   int               m_swing_count;
   int               m_event_count;

   //--- Helpers
   bool              IsPivotHigh(const double &high[], int shift);
   bool              IsPivotLow(const double &low[], int shift);
   ENUM_SWING_TYPE   ClassifySwing(bool is_high, double price);
   bool              CheckBOS(const SSwingPoint &new_swing, const datetime &bar_time[],
                              const double &close_arr[], SStructureEvent &out_event);

   void              PushSwing(const SSwingPoint &sp);
   void              PushEvent(const SStructureEvent &ev);
   void              UpdateKeyLevels();

public:
                     CStructureDetector();
                    ~CStructureDetector() {}

   //--- Initialization
   bool              Init(const string symbol, ENUM_TIMEFRAMES tf, const SStructureConfig &cfg);

   //--- Main update — call once per new bar (shift = bar whose pivots are now confirmed)
   //    Returns true if any new swing or structure event was detected.
   bool              Update(const datetime &time[], const double &open[], const double &high[],
                            const double &low[], const double &close[], int total_bars);

   //--- Accessors
   int               GetSwingCount()  const { return m_swing_count; }
   int               GetEventCount()  const { return m_event_count; }

   SSwingPoint          GetSwing(int idx)  const;   // 0 = most recent
   SStructureEvent      GetEvent(int idx) const;  // 0 = most recent

   ENUM_TREND_BIAS   GetBias()          const { return m_current_bias; }
   double            GetLastSwingHigh() const { return m_last_swing_high; }
   double            GetLastSwingLow()  const { return m_last_swing_low; }

   //--- Reset
   void              Reset();
};

//+------------------------------------------------------------------+
//|  Constructor                                                      |
//+------------------------------------------------------------------+
CStructureDetector::CStructureDetector()
   : m_symbol(""), m_timeframe(PERIOD_CURRENT),
     m_last_swing_high(0.0), m_last_swing_low(DBL_MAX),
     m_current_bias(BIAS_NONE), m_swing_count(0), m_event_count(0)
{
}

//+------------------------------------------------------------------+
bool CStructureDetector::Init(const string symbol, ENUM_TIMEFRAMES tf, const SStructureConfig &cfg)
{
   m_symbol    = symbol;
   m_timeframe = tf;
   m_config    = cfg;

   ArrayResize(m_swings, m_config.max_swings);
   ArrayResize(m_events, m_config.max_events);
   Reset();
   return true;
}

//+------------------------------------------------------------------+
void CStructureDetector::Reset()
{
   m_swing_count      = 0;
   m_event_count      = 0;
   m_last_swing_high  = 0.0;
   m_last_swing_low   = DBL_MAX;
   m_current_bias     = BIAS_NONE;
}

//+------------------------------------------------------------------+
//|  Pivot detection (symmetric lookback, non-repainting)            |
//|  shift must be >= m_config.swing_lookback from the right edge    |
//+------------------------------------------------------------------+
bool CStructureDetector::IsPivotHigh(const double &high[], int shift)
{
   int lb = m_config.swing_lookback;
   if(shift < lb) return false;

   double pivot = high[shift];
   for(int i = shift - lb; i <= shift + lb; i++)
   {
      if(i == shift) continue;
      if(i < 0 || i >= ArraySize(high)) return false;
      if(high[i] >= pivot) return false;
   }
   return true;
}

bool CStructureDetector::IsPivotLow(const double &low[], int shift)
{
   int lb = m_config.swing_lookback;
   if(shift < lb) return false;

   double pivot = low[shift];
   for(int i = shift - lb; i <= shift + lb; i++)
   {
      if(i == shift) continue;
      if(i < 0 || i >= ArraySize(low)) return false;
      if(low[i] <= pivot) return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//|  Classify a new swing relative to previous same-type swing       |
//+------------------------------------------------------------------+
ENUM_SWING_TYPE CStructureDetector::ClassifySwing(bool is_high, double price)
{
   //--- Find last swing of same type
   for(int i = 0; i < m_swing_count; i++)
   {
      if(is_high && (m_swings[i].type == SWING_HH || m_swings[i].type == SWING_LH))
      {
         return (price > m_swings[i].price) ? SWING_HH : SWING_LH;
      }
      if(!is_high && (m_swings[i].type == SWING_HL || m_swings[i].type == SWING_LL))
      {
         return (price > m_swings[i].price) ? SWING_HL : SWING_LL;
      }
   }
   //--- No prior swing found: classify by position relative to the other type
   if(is_high)
      return (m_last_swing_high == 0.0 || price > m_last_swing_high) ? SWING_HH : SWING_LH;
   else
      return (m_last_swing_low == DBL_MAX || price < m_last_swing_low) ? SWING_LL : SWING_HL;
}

//+------------------------------------------------------------------+
//|  Check BOS / CHoCH after adding a new swing                      |
//+------------------------------------------------------------------+
bool CStructureDetector::CheckBOS(const SSwingPoint &new_swing, const datetime &bar_time[],
                                   const double &close_arr[], SStructureEvent &out_event)
{
   //--- Need at least one prior swing to compare against
   if(m_swing_count < 1) return false;

   //--- Find the most recent opposing swing
   for(int i = 0; i < m_swing_count; i++)
   {
      bool new_is_high  = (new_swing.type == SWING_HH || new_swing.type == SWING_LH);
      bool prev_is_high = (m_swings[i].type == SWING_HH || m_swings[i].type == SWING_LH);
      if(new_is_high == prev_is_high) continue; // skip same-type

      double level = m_swings[i].price;

      bool broken = m_config.require_close
                    ? (new_is_high ? close_arr[0] > level : close_arr[0] < level)
                    : (new_is_high ? new_swing.price > level : new_swing.price < level);

      if(!broken) break; // levels are ordered newest-first; no need to check further

      out_event.time        = bar_time[0];
      out_event.break_price = level;
      out_event.bar_index   = 0;

      //--- CHoCH = break against current bias; BOS = continuation
      if(m_current_bias == BIAS_NONE)
      {
         out_event.event_type  = STRUCTURE_BOS;
         out_event.bias_after  = new_is_high ? BIAS_BULLISH : BIAS_BEARISH;
      }
      else if((new_is_high && m_current_bias == BIAS_BEARISH) ||
              (!new_is_high && m_current_bias == BIAS_BULLISH))
      {
         out_event.event_type = STRUCTURE_CHOCH;
         out_event.bias_after = new_is_high ? BIAS_BULLISH : BIAS_BEARISH;
      }
      else
      {
         out_event.event_type = STRUCTURE_BOS;
         out_event.bias_after = m_current_bias;
      }

      m_current_bias = out_event.bias_after;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void CStructureDetector::PushSwing(const SSwingPoint &sp)
{
   //--- Shift array right and insert at [0]
   int cap = ArraySize(m_swings);
   for(int i = MathMin(m_swing_count, cap - 1); i > 0; i--)
      m_swings[i] = m_swings[i - 1];
   m_swings[0] = sp;
   if(m_swing_count < cap) m_swing_count++;
}

void CStructureDetector::PushEvent(const SStructureEvent &ev)
{
   int cap = ArraySize(m_events);
   for(int i = MathMin(m_event_count, cap - 1); i > 0; i--)
      m_events[i] = m_events[i - 1];
   m_events[0] = ev;
   if(m_event_count < cap) m_event_count++;
}

void CStructureDetector::UpdateKeyLevels()
{
   for(int i = 0; i < m_swing_count; i++)
   {
      if(m_swings[i].type == SWING_HH || m_swings[i].type == SWING_LH)
      { m_last_swing_high = m_swings[i].price; break; }
   }
   for(int i = 0; i < m_swing_count; i++)
   {
      if(m_swings[i].type == SWING_HL || m_swings[i].type == SWING_LL)
      { m_last_swing_low = m_swings[i].price; break; }
   }
}

//+------------------------------------------------------------------+
//|  Main update — arrays in series mode (0 = current / newest bar)  |
//+------------------------------------------------------------------+
bool CStructureDetector::Update(const datetime &time[], const double &open[], const double &high[],
                                 const double &low[], const double &close[], int total_bars)
{
   bool detected = false;
   int lb = m_config.swing_lookback;

   //--- The first bar that is now fully confirmed: shift = lb
   //    (it has lb bars to its right already printed)
   int confirmed_shift = lb;
   if(total_bars < 2 * lb + 1) return false;

   if(IsPivotHigh(high, confirmed_shift))
   {
      SSwingPoint sp;
      sp.time      = time[confirmed_shift];
      sp.price     = high[confirmed_shift];
      sp.bar_index = confirmed_shift;
      sp.confirmed = true;
      sp.type      = ClassifySwing(true, sp.price);
      PushSwing(sp);
      UpdateKeyLevels();

      SStructureEvent ev;
      if(CheckBOS(sp, time, close, ev))
      {
         PushEvent(ev);
      }
      detected = true;
   }

   if(IsPivotLow(low, confirmed_shift))
   {
      SSwingPoint sp;
      sp.time      = time[confirmed_shift];
      sp.price     = low[confirmed_shift];
      sp.bar_index = confirmed_shift;
      sp.confirmed = true;
      sp.type      = ClassifySwing(false, sp.price);
      PushSwing(sp);
      UpdateKeyLevels();

      SStructureEvent ev;
      if(CheckBOS(sp, time, close, ev))
      {
         PushEvent(ev);
      }
      detected = true;
   }

   return detected;
}

//+------------------------------------------------------------------+
SSwingPoint CStructureDetector::GetSwing(int idx) const
{
   SSwingPoint empty;
   if(idx < 0 || idx >= m_swing_count) return empty;
   return m_swings[idx];
}

SStructureEvent CStructureDetector::GetEvent(int idx) const
{
   SStructureEvent empty;
   if(idx < 0 || idx >= m_event_count) return empty;
   return m_events[idx];
}

#endif // STRUCTUREDETECTOR_MQH
