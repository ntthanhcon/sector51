//+------------------------------------------------------------------+
//|                                        OrderBlockDetector.mqh    |
//|                                     Sector51-Core Library v1.0   |
//|  ICT-style Order Blocks: last opposite candle before BOS         |
//|  Tracks: active, mitigated, invalidated                          |
//+------------------------------------------------------------------+
#pragma once
#ifndef ORDERBLOCKDETECTOR_MQH
#define ORDERBLOCKDETECTOR_MQH

#include "MarketStructure.mqh"
#include "StructureDetector.mqh"

//+------------------------------------------------------------------+
//|  Configuration                                                    |
//+------------------------------------------------------------------+
struct SOrderBlockConfig
{
   int    max_obs;               // max OBs to retain (default 50)
   bool   require_bos_close;     // BOS confirmed on close (passed from StructureDetector)
   double mitigation_percent;    // % into OB body required for mitigation (default 50.0)

   SOrderBlockConfig()
      : max_obs(50), require_bos_close(true), mitigation_percent(50.0) {}
};

//+------------------------------------------------------------------+
//|  OrderBlockDetector                                               |
//|  Depends on CStructureDetector to supply BOS events              |
//+------------------------------------------------------------------+
class COrderBlockDetector
{
private:
   SOrderBlockConfig    m_config;
   string               m_symbol;
   ENUM_TIMEFRAMES      m_timeframe;

   SOrderBlock          m_obs[];
   int                  m_ob_count;

   //--- Track last-seen event count to detect new BOS events
   int                  m_last_event_count;

   //--- Helpers
   bool     FindLastOppositeCandle(const double &open[], const double &high[],
                                    const double &low[], const double &close[],
                                    const datetime &time[], int bos_bar,
                                    bool bullish_bos, SOrderBlock &out);
   void     UpdateStates(const double &high[], const double &low[],
                         const double &close[], int shift);
   void     PushOB(const SOrderBlock &ob);

public:
                     COrderBlockDetector();
                    ~COrderBlockDetector() {}

   bool              Init(const string symbol, ENUM_TIMEFRAMES tf, const SOrderBlockConfig &cfg);

   //--- Must be called AFTER CStructureDetector::Update() on the same bar
   bool              Update(const CStructureDetector &structure,
                            const datetime &time[], const double &open[],
                            const double &high[], const double &low[],
                            const double &close[], int total_bars);

   int                  GetOBCount()      const { return m_ob_count; }
   const SOrderBlock*   GetOB(int idx)    const;
   void                 Reset();
};

//+------------------------------------------------------------------+
COrderBlockDetector::COrderBlockDetector()
   : m_symbol(""), m_timeframe(PERIOD_CURRENT),
     m_ob_count(0), m_last_event_count(0) {}

bool COrderBlockDetector::Init(const string symbol, ENUM_TIMEFRAMES tf, const SOrderBlockConfig &cfg)
{
   m_symbol    = symbol;
   m_timeframe = tf;
   m_config    = cfg;
   ArrayResize(m_obs, m_config.max_obs);
   Reset();
   return true;
}

void COrderBlockDetector::Reset()
{
   m_ob_count        = 0;
   m_last_event_count = 0;
}

//+------------------------------------------------------------------+
//|  Find the last candle that opposes the BOS direction,            |
//|  searching back from bos_bar (bars[bos_bar] is the break bar)   |
//+------------------------------------------------------------------+
bool COrderBlockDetector::FindLastOppositeCandle(const double &open[], const double &high[],
                                                  const double &low[], const double &close[],
                                                  const datetime &time[], int bos_bar,
                                                  bool bullish_bos, SOrderBlock &out)
{
   int total = ArraySize(close);

   //--- For a bullish BOS we want the last BEARISH candle before it
   //--- For a bearish BOS we want the last BULLISH candle before it
   for(int i = bos_bar + 1; i < MathMin(total, bos_bar + 100); i++)
   {
      bool is_bearish = close[i] < open[i];
      bool is_bullish_candle = close[i] > open[i];

      if(bullish_bos && is_bearish)
      {
         out.time      = time[i];
         out.high      = high[i];
         out.low       = low[i];
         out.open      = open[i];
         out.close     = close[i];
         out.type      = OB_BULLISH;   // OB that will act as support after bullish BOS
         out.state     = ZONE_ACTIVE;
         out.bar_index = i;
         return true;
      }
      if(!bullish_bos && is_bullish_candle)
      {
         out.time      = time[i];
         out.high      = high[i];
         out.low       = low[i];
         out.open      = open[i];
         out.close     = close[i];
         out.type      = OB_BEARISH;   // OB that will act as resistance after bearish BOS
         out.state     = ZONE_ACTIVE;
         out.bar_index = i;
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//|  Update mitigation / invalidation states for all active OBs      |
//+------------------------------------------------------------------+
void COrderBlockDetector::UpdateStates(const double &high[], const double &low[],
                                        const double &close[], int shift)
{
   for(int i = 0; i < m_ob_count; i++)
   {
      if(m_obs[i].state != ZONE_ACTIVE) continue;

      double ob_high  = m_obs[i].high;
      double ob_low   = m_obs[i].low;
      double mid      = ob_low + (ob_high - ob_low) * (m_config.mitigation_percent / 100.0);

      if(m_obs[i].type == OB_BULLISH)
      {
         //--- Mitigated: price touches the OB from above and reacts
         if(low[shift] <= mid && close[shift] >= ob_low)
            m_obs[i].state = ZONE_MITIGATED;
         //--- Invalidated: close below the OB low
         else if(close[shift] < ob_low)
            m_obs[i].state = ZONE_INVALIDATED;
      }
      else if(m_obs[i].type == OB_BEARISH)
      {
         //--- Mitigated: price touches OB from below
         if(high[shift] >= mid && close[shift] <= ob_high)
            m_obs[i].state = ZONE_MITIGATED;
         //--- Invalidated: close above the OB high
         else if(close[shift] > ob_high)
            m_obs[i].state = ZONE_INVALIDATED;
      }
   }
}

//+------------------------------------------------------------------+
void COrderBlockDetector::PushOB(const SOrderBlock &ob)
{
   int cap = ArraySize(m_obs);
   if(m_ob_count < cap)
   {
      m_obs[m_ob_count++] = ob;
      return;
   }
   //--- Replace oldest mitigated/invalidated
   for(int i = 0; i < cap; i++)
   {
      if(m_obs[i].state != ZONE_ACTIVE)
      {
         m_obs[i] = ob;
         return;
      }
   }
   //--- Shift and overwrite
   for(int i = 0; i < cap - 1; i++) m_obs[i] = m_obs[i + 1];
   m_obs[cap - 1] = ob;
}

//+------------------------------------------------------------------+
//|  Main update                                                      |
//+------------------------------------------------------------------+
bool COrderBlockDetector::Update(const CStructureDetector &structure,
                                  const datetime &time[], const double &open[],
                                  const double &high[], const double &low[],
                                  const double &close[], int total_bars)
{
   if(total_bars < 3) return false;
   bool detected = false;

   int current_events = structure.GetEventCount();

   //--- Check for new BOS events since last update
   if(current_events > m_last_event_count)
   {
      int new_count = current_events - m_last_event_count;
      for(int e = 0; e < new_count; e++)
      {
         const SStructureEvent *ev = structure.GetEvent(e);
         if(ev == NULL) continue;

         bool bullish_bos = (ev->bias_after == BIAS_BULLISH);

         SOrderBlock ob;
         ob.bos_time = ev->time;

         //--- bos_bar = ev->bar_index (shift into the array)
         if(FindLastOppositeCandle(open, high, low, close, time,
                                    ev->bar_index, bullish_bos, ob))
         {
            PushOB(ob);
            detected = true;
         }
      }
      m_last_event_count = current_events;
   }

   //--- Update all active OB states on bar 1
   UpdateStates(high, low, close, 1);

   return detected;
}

const SOrderBlock* COrderBlockDetector::GetOB(int idx) const
{
   if(idx < 0 || idx >= m_ob_count) return NULL;
   return &m_obs[idx];
}

#endif // ORDERBLOCKDETECTOR_MQH
