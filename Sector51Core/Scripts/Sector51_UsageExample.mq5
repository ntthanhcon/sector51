//+------------------------------------------------------------------+
//|                                      Sector51_UsageExample.mq5  |
//|  Script — demonstrates how to consume Sector51-Core             |
//|  NOT an EA. No trade logic. Print-only output.                  |
//+------------------------------------------------------------------+
#property script_show_inputs

#include <Sector51/Sector51Core.mqh>

//--- Inputs
input int    InpSwingLookback      = 3;
input int    InpATRPeriod          = 14;
input double InpEQThresholdATR     = 0.10;
input int    InpUtcOffsetHours     = 0;    // broker UTC offset
input int    InpBarsToLoad         = 500;

//+------------------------------------------------------------------+
void OnStart()
{
   //--- Build config
   SSector51Config cfg;
   cfg.symbol                     = _Symbol;
   cfg.timeframe                  = _Period;
   cfg.structure.swing_lookback   = InpSwingLookback;
   cfg.liquidity.atr_period       = InpATRPeriod;
   cfg.liquidity.eq_threshold_atr = InpEQThresholdATR;
   cfg.session.utc_offset_hours   = InpUtcOffsetHours;

   //--- Init core
   CSector51Core core;
   if(!core.Init(cfg))
   {
      Print("Sector51Core Init failed.");
      return;
   }

   //--- Load historical bars
   datetime time[];
   double   open[], high[], low[], close[];
   long     volume[];

   ArraySetAsSeries(time,  true);
   ArraySetAsSeries(open,  true);
   ArraySetAsSeries(high,  true);
   ArraySetAsSeries(low,   true);
   ArraySetAsSeries(close, true);

   int copied = CopyRates(_Symbol, _Period, 0, InpBarsToLoad,
                           time, open, high, low, close, volume);
   if(copied < 10)
   {
      Print("Not enough bars: ", copied);
      return;
   }

   //--- Replay bar by bar (newest bar = index 0, oldest = index copied-1)
   //    We iterate from oldest to newest so structure builds correctly
   SSector51Snapshot snap;

   for(int bar = copied - 1; bar >= 1; bar--)
   {
      //--- Build sub-arrays from bar..copied-1 (oldest portion visible)
      int window = copied - bar;

      datetime sub_time[];   ArrayResize(sub_time,  window);
      double   sub_open[];   ArrayResize(sub_open,  window);
      double   sub_high[];   ArrayResize(sub_high,  window);
      double   sub_low[];    ArrayResize(sub_low,   window);
      double   sub_close[];  ArrayResize(sub_close, window);

      ArraySetAsSeries(sub_time,  true);
      ArraySetAsSeries(sub_open,  true);
      ArraySetAsSeries(sub_high,  true);
      ArraySetAsSeries(sub_low,   true);
      ArraySetAsSeries(sub_close, true);

      for(int k = 0; k < window; k++)
      {
         sub_time [k] = time [bar + window - 1 - k];
         sub_open [k] = open [bar + window - 1 - k];
         sub_high [k] = high [bar + window - 1 - k];
         sub_low  [k] = low  [bar + window - 1 - k];
         sub_close[k] = close[bar + window - 1 - k];
      }

      core.Update(sub_time, sub_open, sub_high, sub_low, sub_close, window, snap);
   }

   //--- Print summary
   Print("=== Sector51-Core Summary ===");
   Print("Symbol   : ", _Symbol);
   Print("Timeframe: ", EnumToString(_Period));
   Print("Bias     : ", EnumToString(core.Structure().GetBias()));
   Print("Swings   : ", core.Structure().GetSwingCount());
   Print("BOS/CHoCH: ", core.Structure().GetEventCount());
   Print("FVGs     : ", core.FVG().GetFVGCount());
   Print("OBs      : ", core.OB().GetOBCount());
   Print("Liq Lvls : ", core.Liquidity().GetLevelCount());

   //--- Print last 3 structure events
   Print("--- Recent Structure Events ---");
   for(int i = 0; i < MathMin(3, core.Structure().GetEventCount()); i++)
   {
      const SStructureEvent *ev = core.Structure().GetEvent(i);
      if(ev == NULL) continue;
      PrintFormat("  [%s] %s @ %.5f | Bias after: %s",
                  TimeToString(ev->time, TIME_DATE | TIME_MINUTES),
                  (ev->event_type == STRUCTURE_BOS ? "BOS" : "CHoCH"),
                  ev->break_price,
                  EnumToString(ev->bias_after));
   }

   //--- Print active FVGs
   Print("--- Active FVGs ---");
   for(int i = 0; i < core.FVG().GetFVGCount(); i++)
   {
      const SFVG *fvg = core.FVG().GetFVG(i);
      if(fvg == NULL || fvg->state != ZONE_ACTIVE) continue;
      PrintFormat("  [%s] %s FVG top=%.5f bot=%.5f fill=%.1f%%",
                  TimeToString(fvg->time, TIME_DATE | TIME_MINUTES),
                  (fvg->type == FVG_BULLISH ? "Bull" : "Bear"),
                  fvg->top, fvg->bottom, fvg->fill_percent);
   }

   //--- Print active OBs
   Print("--- Active Order Blocks ---");
   for(int i = 0; i < core.OB().GetOBCount(); i++)
   {
      const SOrderBlock *ob = core.OB().GetOB(i);
      if(ob == NULL || ob->state != ZONE_ACTIVE) continue;
      PrintFormat("  [%s] %s OB H=%.5f L=%.5f",
                  TimeToString(ob->time, TIME_DATE | TIME_MINUTES),
                  (ob->type == OB_BULLISH ? "Bull" : "Bear"),
                  ob->high, ob->low);
   }

   Print("=== Done ===");
}
