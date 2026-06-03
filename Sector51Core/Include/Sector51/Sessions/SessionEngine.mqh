//+------------------------------------------------------------------+
//|                                              SessionEngine.mqh   |
//|                                     Sector51-Core Library v1.0   |
//|  Forex, Metal, and Crypto sessions with configurable profiles    |
//+------------------------------------------------------------------+
#pragma once
#ifndef SESSIONENGINE_MQH
#define SESSIONENGINE_MQH

#include "MarketStructure.mqh"

//+------------------------------------------------------------------+
//|  Session time definition (UTC hours, 0–23)                       |
//+------------------------------------------------------------------+
struct SSessionProfile
{
   ENUM_SESSION  session;
   int           open_hour;    // UTC
   int           open_min;
   int           close_hour;   // UTC
   int           close_min;
   bool          enabled;
   bool          crosses_midnight;  // auto-derived

   SSessionProfile() : session(SESSION_NONE), open_hour(0), open_min(0),
                       close_hour(0), close_min(0), enabled(true), crosses_midnight(false) {}
};

//+------------------------------------------------------------------+
//|  Configuration                                                    |
//+------------------------------------------------------------------+
struct SSessionConfig
{
   int   utc_offset_hours;     // broker UTC offset (e.g. +2 for EET, +3 for EEST)
   bool  use_forex_sessions;
   bool  use_metal_sessions;
   bool  use_crypto_windows;   // volatility windows only (crypto is 24/7)

   SSessionConfig()
      : utc_offset_hours(0), use_forex_sessions(true),
        use_metal_sessions(true), use_crypto_windows(true) {}
};

//+------------------------------------------------------------------+
//|  SessionEngine                                                    |
//+------------------------------------------------------------------+
class CSessionEngine
{
private:
   SSessionConfig    m_config;
   SSessionProfile   m_profiles[8];
   int               m_profile_count;

   SSessionWindow    m_windows[];     // rolling history of session windows
   int               m_window_count;
   int               m_max_windows;

   SSessionWindow    m_active[];      // currently open sessions
   int               m_active_count;

   //--- Helpers
   void              BuildDefaultProfiles();
   bool              IsInSession(const SSessionProfile &p, int bar_hour, int bar_min) const;
   datetime          NextSessionOpen(const SSessionProfile &p, datetime from) const;
   void              OpenSession(const SSessionProfile &p, const datetime &bar_time,
                                 double bar_high, double bar_low);
   void              CloseSession(int active_idx, datetime close_time);
   void              UpdateActiveHLs(double bar_high, double bar_low);

   int               HourFromTime(datetime t) const { return (int)(t / 3600) % 24; }
   int               MinFromTime(datetime t)  const { return (int)(t / 60)   % 60; }

public:
                     CSessionEngine();
                    ~CSessionEngine() {}

   bool              Init(const SSessionConfig &cfg, int max_window_history = 200);

   //--- Override individual session profiles
   void              SetProfile(const SSessionProfile &p);

   //--- Call on every new bar (bar[1] = last completed)
   bool              Update(const datetime &time[], const double &high[],
                            const double &low[], int total_bars);

   //--- Accessors
   int               GetActiveCount()   const { return m_active_count; }
   int               GetWindowCount()   const { return m_window_count; }

   SSessionWindow         GetActive(int idx) const;
   SSessionWindow         GetWindow(int idx) const;  // 0 = most recent closed

   bool              IsSessionActive(ENUM_SESSION s) const;
   void              Reset();
};

//+------------------------------------------------------------------+
CSessionEngine::CSessionEngine()
   : m_profile_count(0), m_window_count(0), m_max_windows(200), m_active_count(0) {}

bool CSessionEngine::Init(const SSessionConfig &cfg, int max_window_history)
{
   m_config      = cfg;
   m_max_windows = max_window_history;
   ArrayResize(m_windows, m_max_windows);
   ArrayResize(m_active,  8);
   BuildDefaultProfiles();
   Reset();
   return true;
}

void CSessionEngine::Reset()
{
   m_window_count = 0;
   m_active_count = 0;
}

//+------------------------------------------------------------------+
//|  Default UTC session times                                        |
//+------------------------------------------------------------------+
void CSessionEngine::BuildDefaultProfiles()
{
   m_profile_count = 0;

   //--- Sydney: 22:00 – 07:00 UTC (crosses midnight)
   if(m_config.use_forex_sessions)
   {
      SSessionProfile sydney;
      sydney.session          = SESSION_SYDNEY;
      sydney.open_hour        = 22; sydney.open_min  = 0;
      sydney.close_hour       = 7;  sydney.close_min = 0;
      sydney.enabled          = true;
      sydney.crosses_midnight = true;
      m_profiles[m_profile_count++] = sydney;

      //--- Tokyo: 00:00 – 09:00 UTC
      SSessionProfile tokyo;
      tokyo.session          = SESSION_TOKYO;
      tokyo.open_hour        = 0; tokyo.open_min  = 0;
      tokyo.close_hour       = 9; tokyo.close_min = 0;
      tokyo.enabled          = true;
      m_profiles[m_profile_count++] = tokyo;

      //--- London: 07:00 – 16:00 UTC
      SSessionProfile london;
      london.session          = SESSION_LONDON;
      london.open_hour        = 7; london.open_min  = 0;
      london.close_hour       = 16; london.close_min = 0;
      london.enabled          = true;
      m_profiles[m_profile_count++] = london;

      //--- New York: 12:00 – 21:00 UTC
      SSessionProfile ny;
      ny.session          = SESSION_NEW_YORK;
      ny.open_hour        = 12; ny.open_min  = 0;
      ny.close_hour       = 21; ny.close_min = 0;
      ny.enabled          = true;
      m_profiles[m_profile_count++] = ny;
   }

   //--- Metals (COMEX): 08:00 – 13:30 UTC (peak liquidity)
   if(m_config.use_metal_sessions)
   {
      SSessionProfile metals;
      metals.session          = SESSION_METALS;
      metals.open_hour        = 13; metals.open_min  = 30;  // CME metals open
      metals.close_hour       = 18; metals.close_min = 15;
      metals.enabled          = true;
      m_profiles[m_profile_count++] = metals;
   }

   //--- Crypto high-volatility window: 00:00 – 04:00 UTC & 12:00 – 16:00 UTC
   //    Represented as SESSION_CRYPTO; two windows — open first one here
   if(m_config.use_crypto_windows)
   {
      SSessionProfile crypto;
      crypto.session          = SESSION_CRYPTO;
      crypto.open_hour        = 0;  crypto.open_min  = 0;
      crypto.close_hour       = 4;  crypto.close_min = 0;
      crypto.enabled          = true;
      m_profiles[m_profile_count++] = crypto;
   }
}

//+------------------------------------------------------------------+
void CSessionEngine::SetProfile(const SSessionProfile &p)
{
   for(int i = 0; i < m_profile_count; i++)
   {
      if(m_profiles[i].session == p.session)
      {
         m_profiles[i] = p;
         return;
      }
   }
   if(m_profile_count < 8)
      m_profiles[m_profile_count++] = p;
}

//+------------------------------------------------------------------+
bool CSessionEngine::IsInSession(const SSessionProfile &p, int bar_hour, int bar_min) const
{
   if(!p.enabled) return false;

   int bar_total  = bar_hour * 60 + bar_min;
   int open_total = p.open_hour  * 60 + p.open_min;
   int close_total= p.close_hour * 60 + p.close_min;

   if(!p.crosses_midnight)
      return (bar_total >= open_total && bar_total < close_total);
   else
      return (bar_total >= open_total || bar_total < close_total);
}

//+------------------------------------------------------------------+
void CSessionEngine::OpenSession(const SSessionProfile &p, const datetime &bar_time,
                                  double bar_high, double bar_low)
{
   if(m_active_count >= ArraySize(m_active)) return;
   SSessionWindow &w = m_active[m_active_count++];
   w.session    = p.session;
   w.open_time  = bar_time;
   w.close_time = 0;
   w.high       = bar_high;
   w.low        = bar_low;
   w.is_active  = true;
}

void CSessionEngine::CloseSession(int active_idx, datetime close_time)
{
   if(active_idx < 0 || active_idx >= m_active_count) return;
   SSessionWindow closed = m_active[active_idx];
   closed.close_time = close_time;
   closed.is_active  = false;

   //--- Push to history
   int cap = ArraySize(m_windows);
   if(m_window_count < cap)
      m_windows[m_window_count++] = closed;
   else
   {
      for(int i = 0; i < cap - 1; i++) m_windows[i] = m_windows[i + 1];
      m_windows[cap - 1] = closed;
   }

   //--- Remove from active array
   for(int i = active_idx; i < m_active_count - 1; i++)
      m_active[i] = m_active[i + 1];
   m_active_count--;
}

void CSessionEngine::UpdateActiveHLs(double bar_high, double bar_low)
{
   for(int i = 0; i < m_active_count; i++)
   {
      if(bar_high > m_active[i].high) m_active[i].high = bar_high;
      if(bar_low  < m_active[i].low)  m_active[i].low  = bar_low;
   }
}

//+------------------------------------------------------------------+
//|  Main update                                                      |
//+------------------------------------------------------------------+
bool CSessionEngine::Update(const datetime &time[], const double &high[],
                             const double &low[], int total_bars)
{
   if(total_bars < 2) return false;

   //--- Use bar[1] (last closed bar); convert broker time → UTC
   datetime bar_dt   = time[1] - (datetime)(m_config.utc_offset_hours * 3600);
   int      bar_hour = HourFromTime(bar_dt);
   int      bar_min  = MinFromTime(bar_dt);

   double bar_h = high[1];
   double bar_l = low[1];

   bool changed = false;

   //--- Check which profiles should be active
   for(int p = 0; p < m_profile_count; p++)
   {
      bool should_be_active = IsInSession(m_profiles[p], bar_hour, bar_min);

      //--- Find if already active
      int active_idx = -1;
      for(int a = 0; a < m_active_count; a++)
         if(m_active[a].session == m_profiles[p].session) { active_idx = a; break; }

      if(should_be_active && active_idx < 0)
      {
         OpenSession(m_profiles[p], time[1], bar_h, bar_l);
         changed = true;
      }
      else if(!should_be_active && active_idx >= 0)
      {
         CloseSession(active_idx, time[1]);
         changed = true;
      }
   }

   //--- Update highs/lows for all still-active windows
   UpdateActiveHLs(bar_h, bar_l);

   return changed;
}

//+------------------------------------------------------------------+
SSessionWindow CSessionEngine::GetActive(int idx) const
{
   SSessionWindow empty;
   if(idx < 0 || idx >= m_active_count) return empty;
   return m_active[idx];
}

SSessionWindow CSessionEngine::GetWindow(int idx) const
{
   SSessionWindow empty;
   if(idx < 0 || idx >= m_window_count) return empty;
   //--- 0 = most recent (last element)
   return m_windows[m_window_count - 1 - idx];
}

bool CSessionEngine::IsSessionActive(ENUM_SESSION s) const
{
   for(int i = 0; i < m_active_count; i++)
      if(m_active[i].session == s) return true;
   return false;
}

#endif // SESSIONENGINE_MQH
