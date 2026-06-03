//+------------------------------------------------------------------+
//|                                             MarketStructure.mqh  |
//|                                     Sector51-Core Library v1.0   |
//|                    Core enums, structs, and interfaces            |
//+------------------------------------------------------------------+
#pragma once
#ifndef MARKETSTRUCTURE_MQH
#define MARKETSTRUCTURE_MQH

//--- Swing point types
enum ENUM_SWING_TYPE
{
   SWING_NONE = 0,
   SWING_HH   = 1,   // Higher High
   SWING_HL   = 2,   // Higher Low
   SWING_LH   = 3,   // Lower High
   SWING_LL   = 4    // Lower Low
};

//--- Market structure events
enum ENUM_STRUCTURE_EVENT
{
   STRUCTURE_NONE  = 0,
   STRUCTURE_BOS   = 1,   // Break of Structure
   STRUCTURE_CHOCH = 2    // Change of Character
};

//--- Trend direction
enum ENUM_TREND_BIAS
{
   BIAS_NONE    = 0,
   BIAS_BULLISH = 1,
   BIAS_BEARISH = -1
};

//--- Liquidity event types
enum ENUM_LIQUIDITY_EVENT
{
   LIQ_NONE          = 0,
   LIQ_EQH           = 1,   // Equal Highs
   LIQ_EQL           = 2,   // Equal Lows
   LIQ_SWEEP_HIGH    = 3,   // Liquidity Sweep above highs
   LIQ_SWEEP_LOW     = 4    // Liquidity Sweep below lows
};

//--- FVG direction
enum ENUM_FVG_TYPE
{
   FVG_NONE    = 0,
   FVG_BULLISH = 1,
   FVG_BEARISH = -1
};

//--- FVG / OrderBlock state
enum ENUM_ZONE_STATE
{
   ZONE_ACTIVE      = 0,
   ZONE_FILLED      = 1,
   ZONE_INVALIDATED = 2,
   ZONE_MITIGATED   = 3
};

//--- Order block type
enum ENUM_OB_TYPE
{
   OB_NONE    = 0,
   OB_BULLISH = 1,
   OB_BEARISH = -1
};

//--- Session names
enum ENUM_SESSION
{
   SESSION_NONE     = 0,
   SESSION_SYDNEY   = 1,
   SESSION_TOKYO    = 2,
   SESSION_LONDON   = 3,
   SESSION_NEW_YORK = 4,
   SESSION_METALS   = 5,
   SESSION_CRYPTO   = 6   // 24/7 — tracked by volatility windows
};

//+------------------------------------------------------------------+
//|  Swing Point                                                      |
//+------------------------------------------------------------------+
struct SSwingPoint
{
   datetime          time;
   double            price;
   ENUM_SWING_TYPE   type;
   int               bar_index;   // index at detection time (0 = current)
   bool              confirmed;   // true once N bars have passed

   SSwingPoint() : time(0), price(0.0), type(SWING_NONE), bar_index(-1), confirmed(false) {}
};

//+------------------------------------------------------------------+
//|  Structure Event (BOS / CHoCH)                                   |
//+------------------------------------------------------------------+
struct SStructureEvent
{
   datetime              time;
   double                break_price;   // level that was broken
   ENUM_STRUCTURE_EVENT  event_type;
   ENUM_TREND_BIAS       bias_after;    // bias after the event
   int                   bar_index;

   SStructureEvent() : time(0), break_price(0.0), event_type(STRUCTURE_NONE), bias_after(BIAS_NONE), bar_index(-1) {}
};

//+------------------------------------------------------------------+
//|  Liquidity Level                                                  |
//+------------------------------------------------------------------+
struct SLiquidityLevel
{
   datetime              time;
   double                price;
   ENUM_LIQUIDITY_EVENT  event_type;
   int                   touch_count;
   bool                  swept;
   datetime              sweep_time;

   SLiquidityLevel() : time(0), price(0.0), event_type(LIQ_NONE), touch_count(0), swept(false), sweep_time(0) {}
};

//+------------------------------------------------------------------+
//|  Fair Value Gap                                                   |
//+------------------------------------------------------------------+
struct SFVG
{
   datetime        time;        // time of the middle candle
   double          top;
   double          bottom;
   ENUM_FVG_TYPE   type;
   ENUM_ZONE_STATE state;
   double          fill_percent; // 0–100
   int             bar_index;

   SFVG() : time(0), top(0.0), bottom(0.0), type(FVG_NONE), state(ZONE_ACTIVE), fill_percent(0.0), bar_index(-1) {}
};

//+------------------------------------------------------------------+
//|  Order Block                                                      |
//+------------------------------------------------------------------+
struct SOrderBlock
{
   datetime        time;        // candle time
   double          high;
   double          low;
   double          open;
   double          close;
   ENUM_OB_TYPE    type;
   ENUM_ZONE_STATE state;
   datetime        bos_time;    // BOS that confirmed this OB
   int             bar_index;

   SOrderBlock() : time(0), high(0.0), low(0.0), open(0.0), close(0.0),
                   type(OB_NONE), state(ZONE_ACTIVE), bos_time(0), bar_index(-1) {}
};

//+------------------------------------------------------------------+
//|  Session Window                                                   |
//+------------------------------------------------------------------+
struct SSessionWindow
{
   ENUM_SESSION  session;
   datetime      open_time;
   datetime      close_time;
   double        high;
   double        low;
   bool          is_active;

   SSessionWindow() : session(SESSION_NONE), open_time(0), close_time(0), high(0.0), low(0.0), is_active(false) {}
};

#endif // MARKETSTRUCTURE_MQH
