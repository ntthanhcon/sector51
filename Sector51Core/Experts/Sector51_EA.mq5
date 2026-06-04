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
sinput group "=== Timeframes ==="
input ENUM_TIMEFRAMES  InpHTF           = PERIOD_H4;   // Higher Timeframe (HTF)
input ENUM_TIMEFRAMES  InpEntryTF       = PERIOD_M15;  // Entry Timeframe

//--- [2] HTF SIGNAL FILTERS
sinput group "=== HTF Signal Filters ==="
input bool  InpUseHTF_BOS       = true;   // Require BOS or CHoCH on HTF
input bool  InpUseHTF_OB        = true;   // Require active OB on HTF
input bool  InpUseHTF_Sweep     = true;   // Require liquidity sweep on HTF
input bool  InpHTF_BOSonly      = false;  // true = only BOS counts, not CHoCH

//--- [3] ENTRY TF SIGNAL FILTERS
sinput group "=== Entry TF Signal Filters ==="
input bool  InpUseEntry_FVG     = true;   // Require FVG on Entry TF
input bool  InpUseEntry_OB      = false;  // Require active OB on Entry TF
input bool  InpUseEntry_BOS     = false;  // Require BOS on Entry TF
input bool  InpFVGmustBeInOB    = true;   // FVG must overlap HTF OB zone

//--- [4] ENTRY EXECUTION
sinput group "=== Entry Execution ==="
input bool  InpUseLimitOrder    = true;   // true=Limit order | false=Market
input bool  InpEntryAtFVG       = true;   // Entry at FVG edge
input bool  InpEntryAtOBMid     = false;  // Entry at OB midpoint (overrides FVG)
input bool  InpAllowFallbackEntry = false;  // Allow market fallback entry when no OB/FVG
input int   InpPendingExpireBars= 5;      // Cancel pending after N bars (0=never)

//--- [5] STOP LOSS
sinput group "=== Stop Loss ==="
input bool   InpSL_OB           = true;   // SL beyond OB boundary
input bool   InpSL_FVG          = false;  // SL beyond FVG boundary
input bool   InpSL_ATR          = false;  // SL = N x ATR
input double InpSL_ATR_Mult     = 1.5;   // ATR multiplier for SL
input int    InpSL_BufferPoints = 10;     // Buffer on SL (points)

//--- [6] TAKE PROFIT
sinput group "=== Take Profit ==="
input bool   InpTP_RR           = true;   // Fixed R:R ratio
input double InpTP_RR_Value     = 2.0;   // R:R ratio
input bool   InpTP_NextLiq      = false;  // TP at next liquidity level
input bool   InpTP_ATR          = false;  // TP = N x ATR
input double InpTP_ATR_Mult     = 3.0;   // ATR multiplier for TP
input bool   InpUsePartialClose = false;  // Partial close at 1:1
input double InpPartialPct      = 50.0;  // % to close at 1:1

//--- [7] RISK MANAGEMENT
sinput group "=== Risk Management ==="
input double InpLotSize         = 0.01;  // Fixed lot size (ignored when using percent risk)
input bool   InpUseRiskPercent   = false; // Use account risk percent instead of fixed lot
input double InpRiskPercent      = 1.0;   // Risk % of account balance per trade
input double InpMaxLotSize       = 1.0;   // Max lot size when using risk sizing (0 = no limit)
input int    InpMaxOpenTrades    = 1;     // Max concurrent open trades
input bool   InpOnlyOnePerDir    = true;  // Max 1 trade per direction

//--- [8] SESSION FILTER
sinput group "=== Session Filter ==="
input bool  InpUseSessions      = true;  // Enable session filter
input bool  InpSess_Sydney      = false; // Allow Sydney session
input bool  InpSess_Tokyo       = false; // Allow Tokyo session
input bool  InpSess_London      = true;  // Allow London session
input bool  InpSess_NewYork     = true;  // Allow New York session
input bool  InpSess_Metals      = false; // Allow Metals window
input bool  InpSess_Crypto      = false; // Allow Crypto window
input int   InpUTC_Offset       = 0;     // Broker UTC offset (hours)

//--- [9] STRUCTURE CONFIG
sinput group "=== Structure Config ==="
input int    InpHTF_SwingLB     = 3;    // HTF swing lookback bars
input int    InpEntry_SwingLB   = 3;    // Entry TF swing lookback bars
input int    InpATR_Period      = 14;   // ATR period
input double InpEQ_Threshold    = 0.10; // EQH/EQL ATR proximity ratio
input bool   InpBOS_RequireClose= true; // BOS confirmed on candle close

//--- [10] MISC
sinput group "=== Misc ==="
input bool   InpDebugMode       = false;  // Enable debug logging
input int    InpMagicNumber     = 51000; // EA magic number
input string InpComment         = "S51"; // Trade comment

//==================================================================//
//  GLOBALS                                                          //
//==================================================================//

CSector51Core  g_htf;
CSector51Core  g_entry;
CTrade         g_trade;

//--- Track whether partial close already done per ticket
ulong    g_partial_done[];
int      g_partial_count = 0;

//--- Pending order state
ulong    g_pending_ticket = 0;
datetime g_pending_opened = 0;

//==================================================================//
//  INIT                                                             //
//==================================================================//

int OnInit()
{
   //--- HTF core
   SSector51Config htf_cfg;
   htf_cfg.symbol                     = _Symbol;
   htf_cfg.timeframe                  = InpHTF;
   htf_cfg.structure.swing_lookback   = InpHTF_SwingLB;
   htf_cfg.structure.require_close    = InpBOS_RequireClose;
   htf_cfg.liquidity.atr_period       = InpATR_Period;
   htf_cfg.liquidity.eq_threshold_atr = InpEQ_Threshold;
   htf_cfg.session.utc_offset_hours   = InpUTC_Offset;
   htf_cfg.session.use_forex_sessions = true;
   htf_cfg.session.use_metal_sessions = InpSess_Metals;
   htf_cfg.session.use_crypto_windows = InpSess_Crypto;

   if(!g_htf.Init(htf_cfg))
   {
      Alert("Sector51: HTF init failed");
      return INIT_FAILED;
   }

   //--- Entry TF core
   SSector51Config entry_cfg;
   entry_cfg.symbol                     = _Symbol;
   entry_cfg.timeframe                  = InpEntryTF;
   entry_cfg.structure.swing_lookback   = InpEntry_SwingLB;
   entry_cfg.structure.require_close    = InpBOS_RequireClose;
   entry_cfg.liquidity.atr_period       = InpATR_Period;
   entry_cfg.liquidity.eq_threshold_atr = InpEQ_Threshold;
   entry_cfg.session.utc_offset_hours   = InpUTC_Offset;
   entry_cfg.session.use_forex_sessions = true;
   entry_cfg.session.use_metal_sessions = InpSess_Metals;
   entry_cfg.session.use_crypto_windows = InpSess_Crypto;

   if(!g_entry.Init(entry_cfg))
   {
      Alert("Sector51: Entry TF init failed");
      return INIT_FAILED;
   }

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(20);
   g_trade.SetTypeFilling(ORDER_FILLING_IOC);

   ArrayResize(g_partial_done, 100);
   g_partial_count = 0;

   PrintFormat("Sector51 EA | HTF:%s | Entry:%s",
               EnumToString(InpHTF), EnumToString(InpEntryTF));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   Print("Sector51 EA stopped. Reason:", reason);
}

//==================================================================//
//  HELPER — Load bars into series arrays                           //
//==================================================================//

bool LoadBars(ENUM_TIMEFRAMES tf, int count,
              datetime &time[], double &open[],
              double &high[], double &low[], double &close[])
{
   ArraySetAsSeries(time,  true);
   ArraySetAsSeries(open,  true);
   ArraySetAsSeries(high,  true);
   ArraySetAsSeries(low,   true);
   ArraySetAsSeries(close, true);

   int n = CopyTime (_Symbol, tf, 0, count, time);
   if(n < 4) return false;
   CopyOpen (_Symbol, tf, 0, n, open);
   CopyHigh (_Symbol, tf, 0, n, high);
   CopyLow  (_Symbol, tf, 0, n, low);
   CopyClose(_Symbol, tf, 0, n, close);
   return true;
}

//==================================================================//
//  HELPER — Session allowed                                         //
//==================================================================//

bool IsSessionAllowed()
{
   if(!InpUseSessions) return true;
   if(InpSess_London  && g_entry.Session().IsSessionActive(SESSION_LONDON))   return true;
   if(InpSess_NewYork && g_entry.Session().IsSessionActive(SESSION_NEW_YORK)) return true;
   if(InpSess_Tokyo   && g_entry.Session().IsSessionActive(SESSION_TOKYO))    return true;
   if(InpSess_Sydney  && g_entry.Session().IsSessionActive(SESSION_SYDNEY))   return true;
   if(InpSess_Metals  && g_entry.Session().IsSessionActive(SESSION_METALS))   return true;
   if(InpSess_Crypto  && g_entry.Session().IsSessionActive(SESSION_CRYPTO))   return true;
   return false;
}

//==================================================================//
//  HELPER — Count open positions by magic                          //
//==================================================================//

int CountOpen(ENUM_POSITION_TYPE dir = WRONG_VALUE)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC)  != InpMagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL)  != _Symbol) continue;
      if(dir == WRONG_VALUE)
         count++;
      else if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == dir)
         count++;
   }
   return count;
}

int GetVolumeDigits()
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   return (step > 0.0) ? (int)MathMax(0, -MathLog10(step)) : 2;
}

double CalculateRiskLot(double stop_loss_distance)
{
   if(!InpUseRiskPercent || stop_loss_distance <= 0.0)
      return InpLotSize;

   double risk_amount = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
   double tick_size   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tick_value  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tick_size <= 0.0 || tick_value <= 0.0)
      return InpLotSize;

   double value_per_lot = MathAbs(stop_loss_distance) / tick_size * tick_value;
   if(value_per_lot <= 0.0)
      return InpLotSize;

   int vol_digits = GetVolumeDigits();
   double lot = NormalizeDouble(risk_amount / value_per_lot, vol_digits);
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(min_lot > 0.0 && lot < min_lot) lot = min_lot;
   if(max_lot > 0.0 && lot > max_lot) lot = max_lot;
   if(InpMaxLotSize > 0.0 && lot > InpMaxLotSize) lot = InpMaxLotSize;
   return lot;
}

void DebugLog(string message)
{
   if(InpDebugMode)
      Print("Sector51 DEBUG | ", message);
}

//==================================================================//
//  HELPER — HTF confluences                                         //
//==================================================================//

bool HTF_HasBias(ENUM_TREND_BIAS required)
{
   if(!InpUseHTF_BOS) return true;
   if(g_htf.Structure().GetBias() != required) return false;
   if(InpHTF_BOSonly)
   {
      SStructureEvent ev = g_htf.Structure().GetEvent(0);
      if(ev.time == 0 || ev.event_type != STRUCTURE_BOS) return false;
   }
   return true;
}

bool HTF_HasActiveOB(ENUM_TREND_BIAS bias, SOrderBlock &out_ob)
{
   if(!InpUseHTF_OB) { out_ob = SOrderBlock(); return true; }
   ENUM_OB_TYPE wanted = (bias == BIAS_BULLISH) ? OB_BULLISH : OB_BEARISH;
   for(int i = 0; i < g_htf.OB().GetOBCount(); i++)
   {
      SOrderBlock ob = g_htf.OB().GetOB(i);
      if(ob.time == 0) continue;
      if(ob.type == wanted && ob.state == ZONE_ACTIVE)
      {
         out_ob = ob;
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
      SLiquidityLevel lv = g_htf.Liquidity().GetLevel(i);
      if(lv.time != 0 && lv.event_type == wanted)
      {
         DebugLog("HTF sweep found");
         return true;
      }
   }
   DebugLog("HTF sweep not found");
   return false;
}

//==================================================================//
//  HELPER — Entry TF confluences                                    //
//==================================================================//

bool Entry_HasFVG(ENUM_TREND_BIAS bias, const SOrderBlock &htf_ob, SFVG &out_fvg)
{
   if(!InpUseEntry_FVG) { out_fvg = SFVG(); return true; }
   ENUM_FVG_TYPE wanted = (bias == BIAS_BULLISH) ? FVG_BULLISH : FVG_BEARISH;
   for(int i = 0; i < g_entry.FVG().GetFVGCount(); i++)
   {
      SFVG fvg = g_entry.FVG().GetFVG(i);
      if(fvg.time == 0 || fvg.type != wanted || fvg.state != ZONE_ACTIVE) continue;
      if(InpFVGmustBeInOB && InpUseHTF_OB)
      {
         if(!(fvg.top >= htf_ob.low && fvg.bottom <= htf_ob.high)) continue;
      }
      out_fvg = fvg;
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
      SOrderBlock ob = g_entry.OB().GetOB(i);
      if(ob.time != 0 && ob.type == wanted && ob.state == ZONE_ACTIVE) return true;
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
//  HELPER — SL calculation                                          //
//==================================================================//

double CalcSL(bool is_buy, double entry, const SOrderBlock &ob,
              const SFVG &fvg, double atr)
{
   double buf = InpSL_BufferPoints * _Point;
   double sl  = 0.0;

   if(InpSL_FVG && fvg.time != 0)
      sl = is_buy ? fvg.bottom - buf : fvg.top + buf;
   else if(InpSL_ATR || (InpSL_OB && ob.time == 0))
      sl = is_buy ? entry - atr * InpSL_ATR_Mult : entry + atr * InpSL_ATR_Mult;
   else // default: OB boundary
      sl = is_buy ? ob.low - buf : ob.high + buf;

   return NormalizeDouble(sl, _Digits);
}

//==================================================================//
//  HELPER — TP calculation                                          //
//==================================================================//

double CalcTP(bool is_buy, double entry, double sl, double atr)
{
   double sl_dist = MathAbs(entry - sl);
   double tp      = 0.0;

   if(InpTP_NextLiq)
   {
      double best = 0.0;
      for(int i = 0; i < g_entry.Liquidity().GetLevelCount(); i++)
      {
         SLiquidityLevel lv = g_entry.Liquidity().GetLevel(i);
         if(lv.time == 0 || lv.swept) continue;
         if(is_buy && lv.price > entry + sl_dist)  // must be at least 1R away
         {
            if(best == 0.0 || lv.price < best) best = lv.price;
         }
         else if(!is_buy && lv.price < entry - sl_dist)
         {
            if(best == 0.0 || lv.price > best) best = lv.price;
         }
      }
      if(best > 0.0) tp = best;
   }

   if(tp == 0.0)
   {
      if(InpTP_ATR)
         tp = is_buy ? entry + atr * InpTP_ATR_Mult : entry - atr * InpTP_ATR_Mult;
      else  // default: R:R
         tp = is_buy ? entry + sl_dist * InpTP_RR_Value : entry - sl_dist * InpTP_RR_Value;
   }

   return NormalizeDouble(tp, _Digits);
}

//==================================================================//
//  HELPER — Cancel expired pending                                  //
//==================================================================//

void ManagePending()
{
   if(g_pending_ticket == 0 || InpPendingExpireBars <= 0) return;
   if(!OrderSelect(g_pending_ticket)) { g_pending_ticket = 0; return; }
   if(OrderGetString(ORDER_SYMBOL) != _Symbol) { g_pending_ticket = 0; return; }

   int elapsed = Bars(_Symbol, InpEntryTF, g_pending_opened, TimeCurrent());
   if(elapsed >= InpPendingExpireBars)
   {
      if(g_trade.OrderDelete(g_pending_ticket))
         PrintFormat("Sector51: pending #%d expired (%d bars)", g_pending_ticket, elapsed);
      g_pending_ticket = 0;
   }
}

//==================================================================//
//  HELPER — Partial close tracking                                  //
//==================================================================//

bool IsPartialDone(ulong ticket)
{
   for(int i = 0; i < g_partial_count; i++)
      if(g_partial_done[i] == ticket) return true;
   return false;
}

void MarkPartialDone(ulong ticket)
{
   if(g_partial_count < ArraySize(g_partial_done))
      g_partial_done[g_partial_count++] = ticket;
}

void CheckPartialClose()
{
   if(!InpUsePartialClose) return;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(IsPartialDone(ticket)) continue;

      double entry   = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl      = PositionGetDouble(POSITION_SL);
      double price   = PositionGetDouble(POSITION_PRICE_CURRENT);
      double sl_dist = MathAbs(entry - sl);
      bool   is_buy  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);

      double target_1r = is_buy ? entry + sl_dist : entry - sl_dist;
      bool hit = is_buy ? price >= target_1r : price <= target_1r;
      if(!hit) continue;

      double lot = PositionGetDouble(POSITION_VOLUME);
      double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      int vol_digits = (step > 0.0) ? (int)MathMax(0, -MathLog10(step)) : 2;
      double close_lot = NormalizeDouble(lot * InpPartialPct / 100.0, vol_digits);
      double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      if(close_lot < min_lot) close_lot = min_lot;

      if(g_trade.PositionClosePartial(ticket, close_lot))
         MarkPartialDone(ticket);
   }
}

//==================================================================//
//  MAIN SIGNAL EVALUATION                                           //
//==================================================================//

void TryBuy()
{
   if(!HTF_HasBias(BIAS_BULLISH))  return;
   if(!HTF_HasSweep(BIAS_BULLISH)) return;

   SOrderBlock htf_ob;
   if(!HTF_HasActiveOB(BIAS_BULLISH, htf_ob)) return;

   SFVG entry_fvg;
   if(!Entry_HasFVG(BIAS_BULLISH, htf_ob, entry_fvg)) return;
   if(!Entry_HasOB(BIAS_BULLISH))  return;
   if(!Entry_HasBOS(BIAS_BULLISH)) return;

   if(InpOnlyOnePerDir && CountOpen(POSITION_TYPE_BUY) > 0) return;

   double atr = g_entry.Liquidity().GetATR();
   double entry_price = 0.0;

   if(InpEntryAtOBMid)
      entry_price = htf_ob.low + (htf_ob.high - htf_ob.low) * 0.5;
   else if(InpUseEntry_FVG && entry_fvg.time != 0)
      entry_price = entry_fvg.bottom; // default: FVG bottom for buy
   else if(htf_ob.time != 0)
      entry_price = htf_ob.low;
   else
   {
      if(!InpAllowFallbackEntry)
         return;
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(bid <= 0.0) return;
      entry_price = InpUseLimitOrder ? bid - _Point : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      DebugLog("Buy fallback entry price from market because no HTF OB or FVG");
   }

   if(entry_price <= 0.0) return;
   entry_price = NormalizeDouble(entry_price, _Digits);

   double sl = CalcSL(true, entry_price, htf_ob, entry_fvg, atr);
   if(sl <= 0.0 || sl >= entry_price) return;

   double lot = InpLotSize;
   if(InpUseRiskPercent)
      lot = CalculateRiskLot(MathAbs(entry_price - sl));
   if(lot <= 0.0) return;

   double tp = CalcTP(true, entry_price, sl, atr);
   if(tp <= entry_price) return;

   if(InpUseLimitOrder)
   {
      if(g_trade.BuyLimit(lot, entry_price, _Symbol, sl, tp,
                          ORDER_TIME_GTC, 0, InpComment + "_BUY"))
      {
         g_pending_ticket = g_trade.ResultOrder();
         g_pending_opened = TimeCurrent();
         PrintFormat("Sector51 BUY LIMIT | lot=%.2f entry=%.5f sl=%.5f tp=%.5f rr=%.2f",
                     lot, entry_price, sl, tp, MathAbs(tp-entry_price)/MathAbs(entry_price-sl));
      }
   }
   else
   {
      if(g_trade.Buy(lot, _Symbol, 0, sl, tp, InpComment + "_BUY"))
         PrintFormat("Sector51 BUY MKT | lot=%.2f sl=%.5f tp=%.5f", lot, sl, tp);
   }
}

void TrySell()
{
   if(!HTF_HasBias(BIAS_BEARISH))  return;
   if(!HTF_HasSweep(BIAS_BEARISH)) return;

   SOrderBlock htf_ob;
   if(!HTF_HasActiveOB(BIAS_BEARISH, htf_ob)) return;

   SFVG entry_fvg;
   if(!Entry_HasFVG(BIAS_BEARISH, htf_ob, entry_fvg)) return;
   if(!Entry_HasOB(BIAS_BEARISH))  return;
   if(!Entry_HasBOS(BIAS_BEARISH)) return;

   if(InpOnlyOnePerDir && CountOpen(POSITION_TYPE_SELL) > 0) return;

   double atr = g_entry.Liquidity().GetATR();
   double entry_price = 0.0;

   if(InpEntryAtOBMid)
      entry_price = htf_ob.low + (htf_ob.high - htf_ob.low) * 0.5;
   else if(InpUseEntry_FVG && entry_fvg.time != 0)
      entry_price = entry_fvg.top; // FVG top for sell
   else if(htf_ob.time != 0)
      entry_price = htf_ob.high;
   else
   {
      if(!InpAllowFallbackEntry)
         return;
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(ask <= 0.0) return;
      entry_price = InpUseLimitOrder ? ask + _Point : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      DebugLog("Sell fallback entry price from market because no HTF OB or FVG");
   }

   if(entry_price <= 0.0) return;
   entry_price = NormalizeDouble(entry_price, _Digits);

   double sl = CalcSL(false, entry_price, htf_ob, entry_fvg, atr);
   if(sl <= 0.0 || sl <= entry_price) return;

   double lot = InpLotSize;
   if(InpUseRiskPercent)
      lot = CalculateRiskLot(MathAbs(entry_price - sl));
   if(lot <= 0.0) return;

   double tp = CalcTP(false, entry_price, sl, atr);
   if(tp >= entry_price) return;

   if(InpUseLimitOrder)
   {
      if(g_trade.SellLimit(lot, entry_price, _Symbol, sl, tp,
                           ORDER_TIME_GTC, 0, InpComment + "_SELL"))
      {
         g_pending_ticket = g_trade.ResultOrder();
         g_pending_opened = TimeCurrent();
         PrintFormat("Sector51 SELL LIMIT | lot=%.2f entry=%.5f sl=%.5f tp=%.5f rr=%.2f",
                     lot, entry_price, sl, tp, MathAbs(tp-entry_price)/MathAbs(sl-entry_price));
      }
   }
   else
   {
      if(g_trade.Sell(lot, _Symbol, 0, sl, tp, InpComment + "_SELL"))
         PrintFormat("Sector51 SELL MKT | lot=%.2f sl=%.5f tp=%.5f", lot, sl, tp);
   }
}

void EvaluateSignal()
{
   if(!IsSessionAllowed())
   {
      if(InpDebugMode)
         Print("Sector51 DEBUG | session blocked");
      return;
   }

   if(CountOpen() >= InpMaxOpenTrades)
   {
      if(InpDebugMode)
         PrintFormat("Sector51 DEBUG | max open trades reached (%d)", CountOpen());
      return;
   }

   if(InpDebugMode)
      PrintFormat("Sector51 DEBUG | bias=%s open=%d htf_ob_count=%d fvg_count=%d entry_tf_bias=%s",
                  EnumToString(g_htf.Structure().GetBias()), CountOpen(),
                  g_htf.OB().GetOBCount(), g_entry.FVG().GetFVGCount(),
                  EnumToString(g_entry.Structure().GetBias()));

   ManagePending();

   TryBuy();
   TrySell();
}

//==================================================================//
//  ON TICK                                                          //
//==================================================================//

void OnTick()
{
   //--- Load HTF bars
   datetime htf_t[]; double htf_o[], htf_h[], htf_l[], htf_c[];
   if(!LoadBars(InpHTF, 500, htf_t, htf_o, htf_h, htf_l, htf_c)) return;

   SSector51Snapshot htf_snap;
   g_htf.Update(htf_t, htf_o, htf_h, htf_l, htf_c, ArraySize(htf_t), htf_snap);

   //--- Load Entry TF bars
   datetime ent_t[]; double ent_o[], ent_h[], ent_l[], ent_c[];
   if(!LoadBars(InpEntryTF, 500, ent_t, ent_o, ent_h, ent_l, ent_c)) return;

   SSector51Snapshot ent_snap;
   bool new_bar = g_entry.Update(ent_t, ent_o, ent_h, ent_l, ent_c,
                                  ArraySize(ent_t), ent_snap);

   //--- Partial close every tick
   CheckPartialClose();

   //--- Signal only on new Entry TF bar
   if(!new_bar) return;

   EvaluateSignal();
}
