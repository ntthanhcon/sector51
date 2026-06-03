//+------------------------------------------------------------------+
//|                                               Sector51_EA.mq5   |
//|                              Sector51 Hybrid ICT Confluence EA   |
//|  Fully configurable — all conditions toggleable via inputs       |
//+------------------------------------------------------------------+
#property copyright "Sector51-Core"
#property version   "1.00"
#property strict

#include <Sector51/Sector51Core.mqh>
#include <Trade/Trade.mqh>

//==================================================================//
//  INPUT GROUPS                                                     //
//==================================================================//

//--- [1] TIMEFRAMES
input group "=== Timeframes ==="
input ENUM_TIMEFRAMES  InpHTF           = PERIOD_H4;   // Higher Timeframe (HTF)
input ENUM_TIMEFRAMES  InpEntryTF       = PERIOD_M15;  // Entry Timeframe

//--- [2] HTF SIGNAL FILTERS (toggleable)
input group "=== HTF Signal Filters ==="
input bool  InpUseHTF_BOS       = true;   // Require BOS or CHoCH on HTF
input bool  InpUseHTF_OB        = true;   // Require active OB on HTF
input bool  InpUseHTF_Sweep     = true;   // Require liquidity sweep on HTF before entry
input bool  InpHTF_BOSonly      = false;  // If true: only BOS counts (not CHoCH)

//--- [3] ENTRY TF SIGNAL FILTERS
input group "=== Entry TF Signal Filters ==="
input bool  InpUseEntry_FVG     = true;   // Require FVG on Entry TF
input bool  InpUseEntry_OB      = false;  // Require active OB on Entry TF as well
input bool  InpUseEntry_BOS     = false;  // Require BOS on Entry TF (confirmation)
input bool  InpFVGmustBeInOB    = true;   // FVG must overlap HTF OB zone

//--- [4] ENTRY EXECUTION
input group "=== Entry Execution ==="
input bool  InpUseLimitOrder    = true;   // true=Limit order | false=Market on signal
input bool  InpEntryAtFVG       = true;   // Entry at FVG edge (50% if false)
input bool  InpEntryAtOBMid     = false;  // Entry at OB midpoint
input int   InpPendingExpireBars= 5;      // Cancel pending after N bars (0=never)

//--- [5] STOP LOSS
input group "=== Stop Loss ==="
input bool  InpSL_OB            = true;   // SL beyond OB boundary
input bool  InpSL_FVG           = false;  // SL beyond FVG boundary (tighter)
input bool  InpSL_ATR           = false;  // SL = N × ATR from entry
input double InpSL_ATR_Mult     = 1.5;   // ATR multiplier for SL
input int   InpSL_BufferPoints  = 10;     // Extra buffer on SL (points)

//--- [6] TAKE PROFIT
input group "=== Take Profit ==="
input bool  InpTP_RR            = true;   // Fixed R:R ratio
input double InpTP_RR_Value     = 2.0;   // R:R ratio (e.g. 2.0 = 1:2)
input bool  InpTP_NextLiq       = false;  // TP at next liquidity level
input bool  InpTP_ATR           = false;  // TP = N × ATR
input double InpTP_ATR_Mult     = 3.0;   // ATR multiplier for TP
input bool  InpUsePartialClose  = false;  // Partial close at 1:1
input double InpPartialPct      = 50.0;  // % to close at 1:1

//--- [7] RISK MANAGEMENT
input group "=== Risk Management ==="
input double InpLotSize         = 0.01;  // Fixed lot size
input int    InpMaxOpenTrades   = 1;     // Max concurrent open trades
input bool   InpOnlyOnePerDir   = true;  // Max 1 trade per direction

//--- [8] SESSION FILTER
input group "=== Session Filter ==="
input bool  InpUseSessions      = true;  // Enable session filter
input bool  InpSess_Sydney      = false; // Allow Sydney
input bool  InpSess_Tokyo       = false; // Allow Tokyo
input bool  InpSess_London      = true;  // Allow London
input bool  InpSess_NewYork     = true;  // Allow New York
input bool  InpSess_Metals      = false; // Allow Metals window
input bool  InpSess_Crypto      = false; // Allow Crypto window
input int   InpUTC_Offset       = 0;     // Broker UTC offset (hours)

//--- [9] STRUCTURE CONFIG
input group "=== Structure Config ==="
input int   InpHTF_SwingLB      = 3;    // HTF swing lookback bars
input int   InpEntry_SwingLB    = 3;    // Entry TF swing lookback bars
input int   InpATR_Period       = 14;   // ATR period (liquidity & SL)
input double InpEQ_Threshold    = 0.10; // EQH/EQL ATR proximity ratio
input bool  InpBOS_RequireClose = true; // BOS confirmed on candle close

//--- [10] MISC
input group "=== Misc ==="
input int   InpMagicNumber      = 51000; // EA magic number
input string InpComment         = "S51"; // Trade comment

//==================================================================//
//  GLOBALS                                                          //
//==================================================================//

CSector51Core  g_htf;        // HTF detector instance
CSector51Core  g_entry;      // Entry TF detector instance
CTrade         g_trade;

datetime  g_htf_last_bar   = 0;
datetime  g_entry_last_bar = 0;

//--- Pending order state
ulong    g_pending_ticket  = 0;
datetime g_pending_opened  = 0;
int      g_pending_bars    = 0;

//==================================================================//
//  INIT                                                             //
//==================================================================//

int OnInit()
{
   //--- HTF core
   SSector51Config htf_cfg;
   htf_cfg.symbol                        = _Symbol;
   htf_cfg.timeframe                     = InpHTF;
   htf_cfg.structure.swing_lookback      = InpHTF_SwingLB;
   htf_cfg.structure.require_close       = InpBOS_RequireClose;
   htf_cfg.liquidity.atr_period          = InpATR_Period;
   htf_cfg.liquidity.eq_threshold_atr    = InpEQ_Threshold;
   htf_cfg.session.utc_offset_hours      = InpUTC_Offset;
   htf_cfg.session.use_forex_sessions    = true;
   htf_cfg.session.use_metal_sessions    = InpSess_Metals;
   htf_cfg.session.use_crypto_windows    = InpSess_Crypto;

   if(!g_htf.Init(htf_cfg))
   { Alert("Sector51 HTF init failed"); return INIT_FAILED; }

   //--- Entry TF core
   SSector51Config entry_cfg;
   entry_cfg.symbol                      = _Symbol;
   entry_cfg.timeframe                   = InpEntryTF;
   entry_cfg.structure.swing_lookback    = InpEntry_SwingLB;
   entry_cfg.structure.require_close     = InpBOS_RequireClose;
   entry_cfg.liquidity.atr_period        = InpATR_Period;
   entry_cfg.liquidity.eq_threshold_atr  = InpEQ_Threshold;
   entry_cfg.session.utc_offset_hours    = InpUTC_Offset;
   entry_cfg.session.use_forex_sessions  = true;
   entry_cfg.session.use_metal_sessions  = InpSess_Metals;
   entry_cfg.session.use_crypto_windows  = InpSess_Crypto;

   if(!g_entry.Init(entry_cfg))
   { Alert("Sector51 Entry TF init failed"); return INIT_FAILED; }

   //--- Trade setup
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(20);
   g_trade.SetTypeFilling(ORDER_FILLING_IOC);

   Print("Sector51 EA initialized | HTF:", EnumToString(InpHTF),
         " | Entry:", EnumToString(InpEntryTF));
   return INIT_SUCCEEDED;
}

//==================================================================//
//  DEINIT                                                           //
//==================================================================//

void OnDeinit(const int reason)
{
   Print("Sector51 EA stopped. Reason:", reason);
}

//==================================================================//
//  HELPERS — Array loading                                          //
//==================================================================//

bool LoadBars(ENUM_TIMEFRAMES tf, int count,
              datetime &time[], double &open[], double &high[],
              double &low[], double &close[])
{
   ArraySetAsSeries(time,  true);
   ArraySetAsSeries(open,  true);
   ArraySetAsSeries(high,  true);
   ArraySetAsSeries(low,   true);
   ArraySetAsSeries(close, true);

   int n = CopyTime (_Symbol, tf, 0, count, time);
   if(n < 4) return false;
   CopyOpen (_Symbol, tf, 0, count, open);
   CopyHigh (_Symbol, tf, 0, count, high);
   CopyLow  (_Symbol, tf, 0, count, low);
   CopyClose(_Symbol, tf, 0, count, close);
   return true;
}

//==================================================================//
//  HELPERS — Session check                                          //
//==================================================================//

bool IsSessionAllowed()
{
   if(!InpUseSessions) return true;

   if(InpSess_London   && g_entry.Session().IsSessionActive(SESSION_LONDON))   return true;
   if(InpSess_NewYork  && g_entry.Session().IsSessionActive(SESSION_NEW_YORK)) return true;
   if(InpSess_Tokyo    && g_entry.Session().IsSessionActive(SESSION_TOKYO))    return true;
   if(InpSess_Sydney   && g_entry.Session().IsSessionActive(SESSION_SYDNEY))   return true;
   if(InpSess_Metals   && g_entry.Session().IsSessionActive(SESSION_METALS))   return true;
   if(InpSess_Crypto   && g_entry.Session().IsSessionActive(SESSION_CRYPTO))   return true;
   return false;
}

//==================================================================//
//  HELPERS — Count open trades                                      //
//==================================================================//

int CountOpenByMagic(ENUM_ORDER_TYPE dir = WRONG_VALUE)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(dir == WRONG_VALUE) count++;
      else if((dir == ORDER_TYPE_BUY  && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ||
              (dir == ORDER_TYPE_SELL && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL))
         count++;
   }
   return count;
}

//==================================================================//
//  HELPERS — HTF Confluence checks                                  //
//==================================================================//

bool HTF_HasBias(ENUM_TREND_BIAS required_bias)
{
   if(!InpUseHTF_BOS) return true;

   ENUM_TREND_BIAS bias = g_htf.Structure().GetBias();
   if(bias != required_bias) return false;

   if(InpHTF_BOSonly)
   {
      const SStructureEvent *ev = g_htf.Structure().GetEvent(0);
      if(ev == NULL || ev->event_type != STRUCTURE_BOS) return false;
   }
   return true;
}

bool HTF_HasActiveOB(ENUM_TREND_BIAS bias, SOrderBlock &out_ob)
{
   if(!InpUseHTF_OB) return true;

   ENUM_OB_TYPE wanted = (bias == BIAS_BULLISH) ? OB_BULLISH : OB_BEARISH;
   for(int i = 0; i < g_htf.OB().GetOBCount(); i++)
   {
      const SOrderBlock *ob = g_htf.OB().GetOB(i);
      if(ob == NULL) continue;
      if(ob->type == wanted && ob->state == ZONE_ACTIVE)
      {
         out_ob = *ob;
         return true;
      }
   }
   return false;
}

bool HTF_HasSweep(ENUM_TREND_BIAS bias)
{
   if(!InpUseHTF_Sweep) return true;

   ENUM_LIQUIDITY_EVENT wanted = (bias == BIAS_BULLISH) ? LIQ_SWEEP_LOW : LIQ_SWEEP_HIGH;
   for(int i = 0; i < g_htf.Liquidity().GetLevelCount(); i++)
   {
      const SLiquidityLevel *lv = g_htf.Liquidity().GetLevel(i);
      if(lv == NULL) continue;
      if(lv->event_type == wanted && lv->swept) return true;
   }
   return false;
}

//==================================================================//
//  HELPERS — Entry TF confluence                                    //
//==================================================================//

bool Entry_HasFVG(ENUM_TREND_BIAS bias, const SOrderBlock &htf_ob, SFVG &out_fvg)
{
   if(!InpUseEntry_FVG) return true;

   ENUM_FVG_TYPE wanted = (bias == BIAS_BULLISH) ? FVG_BULLISH : FVG_BEARISH;
   for(int i = 0; i < g_entry.FVG().GetFVGCount(); i++)
   {
      const SFVG *fvg = g_entry.FVG().GetFVG(i);
      if(fvg == NULL) continue;
      if(fvg->type != wanted || fvg->state != ZONE_ACTIVE) continue;

      if(InpFVGmustBeInOB && InpUseHTF_OB)
      {
         //--- FVG must overlap the HTF OB zone
         bool overlap = (fvg->top >= htf_ob.low && fvg->bottom <= htf_ob.high);
         if(!overlap) continue;
      }

      out_fvg = *fvg;
      return true;
   }
   return false;
}

bool Entry_HasOB(ENUM_TREND_BIAS bias)
{
   if(!InpUseEntry_OB) return true;

   ENUM_OB_TYPE wanted = (bias == BIAS_BULLISH) ? OB_BULLISH : OB_BEARISH;
   for(int i = 0; i < g_entry.OB().GetOBCount(); i++)
   {
      const SOrderBlock *ob = g_entry.OB().GetOB(i);
      if(ob == NULL) continue;
      if(ob->type == wanted && ob->state == ZONE_ACTIVE) return true;
   }
   return false;
}

bool Entry_HasBOS(ENUM_TREND_BIAS bias)
{
   if(!InpUseEntry_BOS) return true;
   return (g_entry.Structure().GetBias() == bias &&
           g_entry.Structure().GetEventCount() > 0);
}

//==================================================================//
//  HELPERS — Calculate SL / TP                                     //
//==================================================================//

double CalcSL(bool is_buy, double entry_price, const SOrderBlock &htf_ob,
              const SFVG &fvg, double atr)
{
   double sl = 0.0;
   double buf = InpSL_BufferPoints * _Point;

   if(InpSL_OB)
   {
      sl = is_buy ? htf_ob.low - buf : htf_ob.high + buf;
   }
   else if(InpSL_FVG)
   {
      sl = is_buy ? fvg.bottom - buf : fvg.top + buf;
   }
   else if(InpSL_ATR)
   {
      sl = is_buy ? entry_price - atr * InpSL_ATR_Mult
                  : entry_price + atr * InpSL_ATR_Mult;
   }

   return NormalizeDouble(sl, _Digits);
}

double CalcTP(bool is_buy, double entry_price, double sl_price, double atr,
              const double &high[], const double &low[], ENUM_TREND_BIAS bias)
{
   double tp = 0.0;
   double sl_dist = MathAbs(entry_price - sl_price);

   if(InpTP_RR)
   {
      tp = is_buy ? entry_price + sl_dist * InpTP_RR_Value
                  : entry_price - sl_dist * InpTP_RR_Value;
   }
   else if(InpTP_ATR)
   {
      tp = is_buy ? entry_price + atr * InpTP_ATR_Mult
                  : entry_price - atr * InpTP_ATR_Mult;
   }
   else if(InpTP_NextLiq)
   {
      //--- Find nearest unswept liquidity level in profit direction
      double best = 0.0;
      for(int i = 0; i < g_entry.Liquidity().GetLevelCount(); i++)
      {
         const SLiquidityLevel *lv = g_entry.Liquidity().GetLevel(i);
         if(lv == NULL || lv->swept) continue;
         if(is_buy && lv->price > entry_price)
         {
            if(best == 0.0 || lv->price < best) best = lv->price;
         }
         else if(!is_buy && lv->price < entry_price)
         {
            if(best == 0.0 || lv->price > best) best = lv->price;
         }
      }
      tp = (best > 0.0) ? best : (is_buy ? entry_price + sl_dist * 2.0
                                          : entry_price - sl_dist * 2.0);
   }

   return NormalizeDouble(tp, _Digits);
}

//==================================================================//
//  HELPERS — Cancel expired pending                                 //
//==================================================================//

void ManagePending()
{
   if(g_pending_ticket == 0) return;
   if(InpPendingExpireBars <= 0) return;

   if(!OrderSelect(g_pending_ticket)) { g_pending_ticket = 0; return; }
   if(OrderGetString(ORDER_SYMBOL) != _Symbol) { g_pending_ticket = 0; return; }

   int bars_since = Bars(_Symbol, InpEntryTF, g_pending_opened, TimeCurrent());
   if(bars_since >= InpPendingExpireBars)
   {
      g_trade.OrderDelete(g_pending_ticket);
      g_pending_ticket = 0;
      Print("Sector51: pending expired after ", bars_since, " bars");
   }
}

//==================================================================//
//  HELPERS — Partial close                                          //
//==================================================================//

void CheckPartialClose()
{
   if(!InpUsePartialClose) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      double entry  = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl     = PositionGetDouble(POSITION_SL);
      double tp     = PositionGetDouble(POSITION_TP);
      double price  = PositionGetDouble(POSITION_PRICE_CURRENT);
      double sl_dist = MathAbs(entry - sl);
      bool is_buy   = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);

      double target_1r = is_buy ? entry + sl_dist : entry - sl_dist;
      bool hit_1r = is_buy ? price >= target_1r : price <= target_1r;

      //--- Only close once: check comment
      string comment = PositionGetString(POSITION_COMMENT);
      if(hit_1r && StringFind(comment, "P50") < 0)
      {
         double lot = PositionGetDouble(POSITION_VOLUME);
         double close_lot = NormalizeDouble(lot * InpPartialPct / 100.0,
                                            (int)SymbolInfoInteger(_Symbol, SYMBOL_VOLUME_DIGITS));
         if(close_lot >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
            g_trade.PositionClosePartial(ticket, close_lot);
      }
   }
}

//==================================================================//
//  MAIN SIGNAL EVALUATION                                           //
//==================================================================//

void EvaluateSignal()
{
   //--- Session check
   if(!IsSessionAllowed()) return;

   //--- Max trades check
   if(CountOpenByMagic() >= InpMaxOpenTrades) return;

   //--- Cancel previous pending if still waiting
   ManagePending();

   //--- Evaluate BULLISH setup
   {
      if(HTF_HasBias(BIAS_BULLISH) && HTF_HasSweep(BIAS_BULLISH))
      {
         SOrderBlock htf_ob; SFVG entry_fvg;
         if(HTF_HasActiveOB(BIAS_BULLISH, htf_ob))
         {
            if(Entry_HasFVG(BIAS_BULLISH, htf_ob, entry_fvg) &&
               Entry_HasOB(BIAS_BULLISH) &&
               Entry_HasBOS(BIAS_BULLISH))
            {
               if(InpOnlyOnePerDir && CountOpenByMagic(ORDER_TYPE_BUY) > 0) goto check_bear;

               double atr   = g_entry.Liquidity().GetATR();
               double entry = InpEntryAtFVG ? entry_fvg.bottom
                            : InpEntryAtOBMid ? htf_ob.low + (htf_ob.high - htf_ob.low) * 0.5
                            : entry_fvg.bottom;

               datetime htf_time[]; double htf_open[], htf_high[], htf_low[], htf_close[];
               double sl, tp;
               sl = CalcSL(true, entry, htf_ob, entry_fvg, atr);
               tp = CalcTP(true, entry, sl, atr, htf_high, htf_low, BIAS_BULLISH);

               if(sl >= entry) goto check_bear;  // sanity
               if(tp <= entry) goto check_bear;

               if(InpUseLimitOrder)
               {
                  g_trade.BuyLimit(InpLotSize, entry, _Symbol, sl, tp,
                                   ORDER_TIME_GTC, 0, InpComment + "_BUY");
                  g_pending_ticket = g_trade.ResultOrder();
                  g_pending_opened = TimeCurrent();
               }
               else
               {
                  g_trade.Buy(InpLotSize, _Symbol, 0, sl, tp, InpComment + "_BUY");
               }
               PrintFormat("Sector51 BUY | entry=%.5f sl=%.5f tp=%.5f", entry, sl, tp);
               return;
            }
         }
      }
   }

   check_bear:
   //--- Evaluate BEARISH setup
   {
      if(HTF_HasBias(BIAS_BEARISH) && HTF_HasSweep(BIAS_BEARISH))
      {
         SOrderBlock htf_ob; SFVG entry_fvg;
         if(HTF_HasActiveOB(BIAS_BEARISH, htf_ob))
         {
            if(Entry_HasFVG(BIAS_BEARISH, htf_ob, entry_fvg) &&
               Entry_HasOB(BIAS_BEARISH) &&
               Entry_HasBOS(BIAS_BEARISH))
            {
               if(InpOnlyOnePerDir && CountOpenByMagic(ORDER_TYPE_SELL) > 0) return;

               double atr   = g_entry.Liquidity().GetATR();
               double entry = InpEntryAtFVG ? entry_fvg.top
                            : InpEntryAtOBMid ? htf_ob.low + (htf_ob.high - htf_ob.low) * 0.5
                            : entry_fvg.top;

               double htf_high[], htf_low[];
               double sl, tp;
               sl = CalcSL(false, entry, htf_ob, entry_fvg, atr);
               tp = CalcTP(false, entry, sl, atr, htf_high, htf_low, BIAS_BEARISH);

               if(sl <= entry) return;
               if(tp >= entry) return;

               if(InpUseLimitOrder)
               {
                  g_trade.SellLimit(InpLotSize, entry, _Symbol, sl, tp,
                                    ORDER_TIME_GTC, 0, InpComment + "_SELL");
                  g_pending_ticket = g_trade.ResultOrder();
                  g_pending_opened = TimeCurrent();
               }
               else
               {
                  g_trade.Sell(InpLotSize, _Symbol, 0, sl, tp, InpComment + "_SELL");
               }
               PrintFormat("Sector51 SELL | entry=%.5f sl=%.5f tp=%.5f", entry, sl, tp);
            }
         }
      }
   }
}

//==================================================================//
//  ON TICK                                                          //
//==================================================================//

void OnTick()
{
   //--- Load and update HTF bars
   datetime htf_time[]; double htf_open[], htf_high[], htf_low[], htf_close[];
   if(!LoadBars(InpHTF, 500, htf_time, htf_open, htf_high, htf_low, htf_close)) return;

   SSector51Snapshot htf_snap;
   g_htf.Update(htf_time, htf_open, htf_high, htf_low, htf_close,
                ArraySize(htf_time), htf_snap);

   //--- Load and update Entry TF bars
   datetime ent_time[]; double ent_open[], ent_high[], ent_low[], ent_close[];
   if(!LoadBars(InpEntryTF, 500, ent_time, ent_open, ent_high, ent_low, ent_close)) return;

   SSector51Snapshot ent_snap;
   bool new_bar = g_entry.Update(ent_time, ent_open, ent_high, ent_low, ent_close,
                                  ArraySize(ent_time), ent_snap);

   //--- Partial close management (every tick)
   CheckPartialClose();

   //--- Only evaluate signal on new Entry TF bar
   if(!new_bar) return;

   EvaluateSignal();
}
