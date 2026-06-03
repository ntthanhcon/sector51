//+------------------------------------------------------------------+
//|                                             Sector51Core.mqh     |
//|                                     Sector51-Core Library v1.0   |
//|  Single-include facade — plug-and-play entry point               |
//+------------------------------------------------------------------+

#ifndef SECTOR51CORE_MQH
#define SECTOR51CORE_MQH

#include <Sector51/Core/MarketStructure.mqh>
#include <Sector51/Detectors/StructureDetector.mqh>
#include <Sector51/Detectors/LiquidityDetector.mqh>
#include <Sector51/Detectors/FVGDetector.mqh>
#include <Sector51/Detectors/OrderBlockDetector.mqh>
#include <Sector51/Sessions/SessionEngine.mqh>

//+------------------------------------------------------------------+
//|  Unified config bundle                                            |
//+------------------------------------------------------------------+
struct SSector51Config
{
   string               symbol;
   ENUM_TIMEFRAMES      timeframe;
   SStructureConfig     structure;
   SLiquidityConfig     liquidity;
   SFVGConfig           fvg;
   SOrderBlockConfig    ob;
   SSessionConfig       session;

   SSector51Config()
   {
      symbol    = _Symbol;
      timeframe = _Period;
   }
};

//+------------------------------------------------------------------+
//|  Market event snapshot emitted every bar                         |
//+------------------------------------------------------------------+
struct SSector51Snapshot
{
   datetime  bar_time;

   //--- New detections this bar
   bool      new_swing;
   bool      new_structure_event;
   bool      new_fvg;
   bool      new_liquidity;
   bool      new_ob;
   bool      session_changed;

   //--- Current state
   ENUM_TREND_BIAS  bias;
   bool             london_active;
   bool             new_york_active;
   bool             tokyo_active;
   bool             sydney_active;
   bool             metals_active;
   bool             crypto_active;

   SSector51Snapshot()
      : bar_time(0), new_swing(false), new_structure_event(false),
        new_fvg(false), new_liquidity(false), new_ob(false),
        session_changed(false), bias(BIAS_NONE),
        london_active(false), new_york_active(false), tokyo_active(false),
        sydney_active(false), metals_active(false), crypto_active(false) {}
};

//+------------------------------------------------------------------+
//|  CSector51Core — unified facade                                  |
//+------------------------------------------------------------------+
class CSector51Core
{
private:
   CStructureDetector   m_structure;
   CLiquidityDetector   m_liquidity;
   CFVGDetector         m_fvg;
   COrderBlockDetector  m_ob;
   CSessionEngine       m_session;

   SSector51Config      m_config;
   bool                 m_initialized;
   datetime             m_last_bar_time;

public:
                        CSector51Core();
                       ~CSector51Core() {}

   bool                 Init(const SSector51Config &cfg);
   bool                 Init(); // default config

   //--- Call from OnCalculate / OnTick
   //    Returns true if at least one detector found something new this bar
   bool                 Update(const datetime &time[], const double &open[],
                                const double &high[], const double &low[],
                                const double &close[], int total_bars,
                                SSector51Snapshot &snap);

   //--- Direct access to sub-detectors
   CStructureDetector*   Structure() { return GetPointer(m_structure); }
   CLiquidityDetector*   Liquidity() { return GetPointer(m_liquidity); }
   CFVGDetector*         FVG()       { return GetPointer(m_fvg);       }
   COrderBlockDetector*  OB()        { return GetPointer(m_ob);        }
   CSessionEngine*       Session()   { return GetPointer(m_session);   }

   bool                 IsInitialized() const { return m_initialized; }
   void                 Reset();
};

//+------------------------------------------------------------------+
CSector51Core::CSector51Core() : m_initialized(false), m_last_bar_time(0) {}

bool CSector51Core::Init()
{
   SSector51Config cfg;
   return Init(cfg);
}

bool CSector51Core::Init(const SSector51Config &cfg)
{
   m_config = cfg;

   if(!m_structure.Init(cfg.symbol, cfg.timeframe, cfg.structure)) return false;
   if(!m_liquidity.Init(cfg.symbol, cfg.timeframe, cfg.liquidity)) return false;
   if(!m_fvg.Init      (cfg.symbol, cfg.timeframe, cfg.fvg))       return false;
   if(!m_ob.Init       (cfg.symbol, cfg.timeframe, cfg.ob))         return false;
   if(!m_session.Init  (cfg.session))                               return false;

   m_initialized   = true;
   m_last_bar_time = 0;
   return true;
}

void CSector51Core::Reset()
{
   m_structure.Reset();
   m_liquidity.Reset();
   m_fvg.Reset();
   m_ob.Reset();
   m_session.Reset();
   m_last_bar_time = 0;
}

//+------------------------------------------------------------------+
bool CSector51Core::Update(const datetime &time[], const double &open[],
                            const double &high[], const double &low[],
                            const double &close[], int total_bars,
                            SSector51Snapshot &snap)
{
   if(!m_initialized || total_bars < 4) return false;

   snap = SSector51Snapshot();
   snap.bar_time = time[0];

   //--- Only process once per new bar
   if(time[1] == m_last_bar_time) return false;
   m_last_bar_time = time[1];

   //--- Run detectors
   snap.new_swing           = m_structure.Update(time, open, high, low, close, total_bars);
   snap.new_structure_event = (m_structure.GetEventCount() > 0 && snap.new_swing);
   snap.new_liquidity       = m_liquidity.Update(time, high, low, close, total_bars);
   snap.new_fvg             = m_fvg.Update(time, high, low, close, total_bars);
   snap.new_ob              = m_ob.Update(m_structure, time, open, high, low, close, total_bars);
   snap.session_changed     = m_session.Update(time, high, low, total_bars);

   //--- Populate state fields
   snap.bias          = m_structure.GetBias();
   snap.london_active = m_session.IsSessionActive(SESSION_LONDON);
   snap.new_york_active = m_session.IsSessionActive(SESSION_NEW_YORK);
   snap.tokyo_active  = m_session.IsSessionActive(SESSION_TOKYO);
   snap.sydney_active = m_session.IsSessionActive(SESSION_SYDNEY);
   snap.metals_active = m_session.IsSessionActive(SESSION_METALS);
   snap.crypto_active = m_session.IsSessionActive(SESSION_CRYPTO);

   return (snap.new_swing || snap.new_structure_event || snap.new_fvg ||
           snap.new_liquidity || snap.new_ob || snap.session_changed);
}

#endif // SECTOR51CORE_MQH
