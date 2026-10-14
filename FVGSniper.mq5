//+------------------------------------------------------------------+
//| FVGSniper.mq5                                                    |
//| FVG Sniper [JOAT] - MetaTrader 5 port                             |
//| MT5 adaptation: AlgoToolbox (atoskueko)                           |
//+------------------------------------------------------------------+
// SPDX-License-Identifier: MPL-2.0
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// ORIGINAL WORK
// FVG Sniper [JOAT], Pine Script v6.
// © officialjackofalltrades
// Original publication:
// https://www.tradingview.com/script/EYFR2g2G-FVG-Sniper-JOAT/
//
// MT5 ADAPTATION AND MODIFICATIONS
// Copyright 2026 AlgoToolbox (atoskueko).
// https://algotoolbox.com | https://t.me/algotoolbox
// The adaptation credit does not claim authorship of the original work
// or imply endorsement by its author.
//
// PURPOSE AND SCOPE
// Graded fair value gaps, fill/mitigation and IFVG tracking, rejection
// and inversion signals, virtual trade plans, dashboard, and optional
// VWAP bands. This is an analysis indicator, not an Expert Advisor.
// It does not place, modify, or close broker orders or size positions.
//
// EXECUTION AND PRESENTATION
// - Committed gap, signal, and virtual-trade state uses completed bars.
// - Forming-bar series calculations and displays may update on ticks.
// - HTF bias uses the previous closed HTF bar when data are available.
//   This differs from the original unoffset lookahead_off HTF request;
//   exact Pine/MT5 timing and numerical parity are not asserted here.
// - TP1/TP2 are reference levels. Virtual exits are SL, TP3, or timeout.
// - Virtual outcomes omit spread, commissions, and execution slippage.
// - VWAP uses tick volume and broker-day anchoring; its bands use
//   100-bar close standard deviation, not VWAP-weighted variance.
//
// DISTRIBUTION
// Retain the original notices and MPL-2.0 terms for covered source and
// modifications. When distributing a compiled port, inform recipients
// how to obtain the corresponding covered source under MPL-2.0.
//+------------------------------------------------------------------+

#property copyright   "Original Pine © officialjackofalltrades; MT5 adaptation © 2026 AlgoToolbox (atoskueko)"
#property link        "https://algotoolbox.com"
#property version     "1.02"
#property description "MPL-2.0 MT5 port of FVG Sniper [JOAT] by officialjackofalltrades."
#property description "Graded FVGs, mitigation/IFVG tracking, dashboard and optional VWAP bands."
#property description "Virtual Entry/SL/TP1-3 plans; no broker-order execution or account position sizing."
#property description "MT5 adaptation and maintenance: AlgoToolbox (atoskueko)."
#property description "Support: https://algotoolbox.com | https://t.me/algotoolbox"
#property indicator_chart_window
#property indicator_buffers 7
#property indicator_plots   7

#property indicator_label1  "VWAP"
#property indicator_type1   DRAW_LINE
#property indicator_color1  C'198,214,224'
#property indicator_width1  2
#property indicator_label2  "VWAP+s"
#property indicator_type2   DRAW_LINE
#property indicator_color2  C'90,100,108'
#property indicator_label3  "VWAP-s"
#property indicator_type3   DRAW_LINE
#property indicator_color3  C'90,100,108'
#property indicator_label4  "buy_signal"
#property indicator_type4   DRAW_NONE
#property indicator_label5  "sell_signal"
#property indicator_type5   DRAW_NONE
#property indicator_label6  "bull_flip"
#property indicator_type6   DRAW_NONE
#property indicator_label7  "bear_flip"
#property indicator_type7   DRAW_NONE

//============================ INPUTS ================================
enum ENUM_SIGMODE { SIG_REJ=0, SIG_IFVG=1, SIG_BOTH=2 };          // Rejection Only / IFVG Flip Only / Rejection + IFVG
enum ENUM_STOP    { STOP_GAP=0, STOP_ATR=1 };                      // Gap-Protected / ATR
enum ENUM_SIZE    { SZ_TINY=0, SZ_SMALL=1, SZ_NORMAL=2, SZ_LARGE=3 };

input group "01 · Engine"
input bool         InpAllowBull  = true;      // Detect Bullish FVGs
input bool         InpAllowBear  = true;      // Detect Bearish FVGs
input ENUM_SIGMODE InpSigMode    = SIG_BOTH;  // Signal Source
input int          InpMaxGaps    = 14;        // Max Visible Gaps
input int          InpMaxAge     = 220;       // Gap Lifetime (bars)
input int          InpExtendBars = 12;        // Gap Box Extension (bars)

input group "02 · Filters"
input int          InpAtrLen      = 14;       // ATR Length
input double       InpMinGapAtr   = 0.25;     // Min Gap Size (x ATR)
input double       InpMinBodyRat  = 0.45;     // Min Displacement Body Ratio
input double       InpMinGrade    = 4.0;      // Min Signal Grade (0-10)
input bool         InpUseHTF      = true;     // Higher-Timeframe Bias Filter
input ENUM_TIMEFRAMES InpHtfTF    = PERIOD_H4;// HTF Timeframe
input int          InpHtfEma      = 50;       // HTF EMA Length
input bool         InpReqDirClose = true;     // Require Directional Rejection Close

input group "03 · Trade Model"
input ENUM_STOP    InpStopMode    = STOP_GAP; // Stop Basis
input double       InpSlBufAtr    = 0.20;     // Gap Stop Buffer (x ATR)
input double       InpSlAtrMult   = 1.50;     // ATR Stop Distance (x ATR)
input double       InpMinRiskAtr  = 0.40;     // Min Risk (x ATR) - floor
input double       InpMaxRiskAtr  = 4.00;     // Max Risk (x ATR) - cap
input double       InpTp1R        = 1.0;      // TP1 (R)
input double       InpTp2R        = 2.0;      // TP2 (R)
input double       InpTp3R        = 3.0;      // TP3 (R)
input int          InpTradeMaxBars= 120;      // Max Trade Duration (bars)
input int          InpProjBars    = 8;        // Active Zone Projection (bars)
input int          InpMaxHist     = 20;       // Max Drawn Trades

input group "03a · Support & More"
input string       InpInfoTelegram = "https://t.me/algotoolbox";  // Telegram
input string       InpInfoHomepage = "https://algotoolbox.com";   // Homepage

input group "04 · Visuals"
input bool         InpShowBoxes   = true;     // Show Gap Boxes
input bool         InpShowMid     = false;    // Show Gap Midline
input bool         InpHideFilled  = false;    // Hide Mitigated Gap Boxes
input bool         InpShowGrade   = true;     // Show Grade Spotlight *
input bool         InpShowIFVG    = true;     // Show Inversion (IFVG) Styling
input bool         InpShowSignal  = true;     // Show BUY / SELL Labels
input bool         InpShowStars   = true;     // Include * Grade on Label
input bool         InpShowZones   = true;     // Show TP / SL Zone Boxes
input bool         InpShowLines   = true;     // Show Entry / TP / SL Lines
input bool         InpShowLevels  = true;     // Show Level Labels
input bool         InpShowExit    = true;     // Show Result Labels
input bool         InpUseVwap     = false;    // Show VWAP + sigma Bands
input double       InpVwapDev     = 1.0;      // VWAP Band sigma
input color        InpColBull     = C'38,166,154';  // Bullish FVG / Buy    #26A69A
input color        InpColBear     = C'239,83,80';   // Bearish FVG / Sell   #EF5350
input color        InpColIFVG     = C'255,179,0';   // Inversion Accent     #FFB300
input int          InpBoxTransp   = 86;       // Box Transparency (50-98)
input ENUM_SIZE    InpLblSize     = SZ_SMALL; // Label Size

input group "05 · Dashboard"
input bool         InpShowDash    = true;         // Show Dashboard

input group "06 · Alerts (MT5)"
input bool         InpAlerts      = false;    // Enable alerts (on confirmed bar)

//============================ BUFFERS ===============================
double BufVwap[],BufVwUp[],BufVwLo[],BufBuy[],BufSell[],BufBullFlip[],BufBearFlip[];

//============================ PALETTE ===============================
#define CHROME   C'198,214,224'
#define REDRISK  C'230,45,60'

//============================ STATE =================================
struct FVG
  {
   double top,bot; int dir; int bornBar; double grade,ext,fillPct;
   bool mitigated,inverted,reacted; bool hasBox; int id; int rightBar;
  };
struct TradeRec
  {
   int id; int side; int bar; double entry,stop,t1,t2,t3,risk,grade;
   int closeEdge; int result; double resR;     // result: 0 active, 1 SL, 2 TP, 3 EXIT
  };
FVG      gGaps[];
TradeRec gTrades[];              // closed history (<= InpMaxHist) + active (last element when active)
bool     gTradeActive=false;
int      gGapSeq=0,gTradeSeq=0;
int      gLastFlipDir=0,gLastFlipBar=-1;
int      gTotalBull=0,gTotalBear=0,gTotalInv=0;
int      gProcessed=0;           // number of closed bars processed
datetime gProcessedTime=0;       // time of the last processed bar
int      gLastSig=0; string gLastSigTag=""; int gLastSigBar=-1;

//--- series caches (chronological)
double   gAtr[],gTR[],gVolAvg[],gVwap[],gVwSd[];
double   gCumPV=0,gCumV=0; datetime gVwapDay=0;
int      gArr=0;

//--- misc
string   gPrefix;
bool     gHeadless=false;
int      gHtfHandle=INVALID_HANDLE;
datetime gHtfBarT=0; int gHtfBias=0;
color    gBg=clrBlack;
string   gSpotKey="";
#define DROWS 11
#define InpDashSize SZ_NORMAL
#define InpDarkDash true
#define BRAND_TXT "t.me/algotoolbox | algotoolbox.com"
string   gDashTxt[2*DROWS]; color gDashCol[2*DROWS]; color gDashBg[2*DROWS]; bool gDashBuilt=false; int gDashW0=0,gDashW1=0,gDashRowH=0;

//============================ HELPERS ===============================
int  FontSz(const ENUM_SIZE s){ return(s==SZ_TINY ? 7 : (s==SZ_SMALL ? 8 : (s==SZ_NORMAL ? 10 : 12))); }
string Stars(const double g){ return(g>=9.0 ? "★★★★★" : (g>=7.0 ? "★★★★" : (g>=5.0 ? "★★★" : (g>=3.0 ? "★★" : "★")))); }
string SignedR(const double v){ return((v>=0 ? "+" : "")+DoubleToString(v,2)+"R"); }
string Px(const double p){ return(DoubleToString(p,_Digits)); }
string F1(const double v){ return(DoubleToString(v,1)); }
// Pine color.new(c, transp) emulated by blending with the chart background
color Blend(const color c,const int transp)
  {
   double t=MathMax(0,MathMin(100,transp))/100.0;
   int r=(int)MathRound(((c)&0xFF)*(1-t)+((gBg)&0xFF)*t);
   int g=(int)MathRound(((c>>8)&0xFF)*(1-t)+((gBg>>8)&0xFF)*t);
   int b=(int)MathRound(((c>>16)&0xFF)*(1-t)+((gBg>>16)&0xFF)*t);
   return((color)(r|(g<<8)|(b<<16)));
  }
color Grad(const color a,const color b,double f)
  {
   f=MathMax(0,MathMin(1,f));
   int r=(int)MathRound(((a)&0xFF)*(1-f)+((b)&0xFF)*f);
   int g=(int)MathRound(((a>>8)&0xFF)*(1-f)+((b>>8)&0xFF)*f);
   int bb=(int)MathRound(((a>>16)&0xFF)*(1-f)+((b>>16)&0xFF)*f);
   return((color)(r|(g<<8)|(bb<<16)));
  }
datetime TimeAtBar(const int idx,const datetime &time[],const int n)
  {
   if(idx<0) return(time[0]);
   if(idx<n) return(time[idx]);
   return((datetime)(time[n-1]+(idx-n+1)*PeriodSeconds(_Period)));
  }
void DelObj(const string nm){ if(ObjectFind(0,nm)>=0) ObjectDelete(0,nm); }
void ObjCommon(const string nm,const bool back)
  {
   ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,nm,OBJPROP_SELECTED,false);
   ObjectSetInteger(0,nm,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,nm,OBJPROP_BACK,back);
  }
void PutRect(const string nm,const datetime t1,const double p1,const datetime t2,const double p2,const color c,const bool fill,const ENUM_LINE_STYLE st=STYLE_SOLID)
  {
   if(ObjectFind(0,nm)<0){ ObjectCreate(0,nm,OBJ_RECTANGLE,0,t1,p1,t2,p2); ObjCommon(nm,true); }
   ObjectSetInteger(0,nm,OBJPROP_TIME,0,t1); ObjectSetDouble(0,nm,OBJPROP_PRICE,0,p1);
   ObjectSetInteger(0,nm,OBJPROP_TIME,1,t2); ObjectSetDouble(0,nm,OBJPROP_PRICE,1,p2);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,c);
   ObjectSetInteger(0,nm,OBJPROP_FILL,fill);
   ObjectSetInteger(0,nm,OBJPROP_STYLE,st);
   ObjectSetInteger(0,nm,OBJPROP_WIDTH,1);
  }
void PutLine(const string nm,const datetime t1,const datetime t2,const double p,const color c,const int w,const ENUM_LINE_STYLE st)
  {
   if(ObjectFind(0,nm)<0){ ObjectCreate(0,nm,OBJ_TREND,0,t1,p,t2,p); ObjectSetInteger(0,nm,OBJPROP_RAY_RIGHT,false); ObjCommon(nm,true); }
   ObjectSetInteger(0,nm,OBJPROP_TIME,0,t1); ObjectSetDouble(0,nm,OBJPROP_PRICE,0,p);
   ObjectSetInteger(0,nm,OBJPROP_TIME,1,t2); ObjectSetDouble(0,nm,OBJPROP_PRICE,1,p);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,c); ObjectSetInteger(0,nm,OBJPROP_WIDTH,w); ObjectSetInteger(0,nm,OBJPROP_STYLE,st);
  }
void PutText(const string nm,const datetime t,const double p,const string txt,const color c,const int fs,const ENUM_ANCHOR_POINT a,const bool bold=false)
  {
   if(ObjectFind(0,nm)<0){ ObjectCreate(0,nm,OBJ_TEXT,0,t,p); ObjectSetString(0,nm,OBJPROP_FONT,bold ? "Arial Black" : "Arial"); ObjCommon(nm,false); }
   ObjectSetInteger(0,nm,OBJPROP_TIME,0,t); ObjectSetDouble(0,nm,OBJPROP_PRICE,0,p);
   ObjectSetString(0,nm,OBJPROP_TEXT,txt); ObjectSetInteger(0,nm,OBJPROP_COLOR,c);
   ObjectSetInteger(0,nm,OBJPROP_FONTSIZE,fs); ObjectSetInteger(0,nm,OBJPROP_ANCHOR,a);
  }

//============================ HTF BIAS ==============================
// value of the last CLOSED HTF bar at time t (non-repainting, == lookahead_off on history)
int HtfBiasAt(const datetime t)
  {
   if(!InpUseHTF || gHtfHandle==INVALID_HANDLE) return(0);
   int k=iBarShift(_Symbol,InpHtfTF,t,false);
   if(k<0) return(0);
   datetime bt=iTime(_Symbol,InpHtfTF,k);
   if(bt==gHtfBarT) return(gHtfBias);
   double e[]; if(CopyBuffer(gHtfHandle,0,k+1,1,e)<1) return(0);
   double c=iClose(_Symbol,InpHtfTF,k+1);
   if(c<=0 || e[0]<=0) return(0);
   gHtfBarT=bt; gHtfBias=(c>e[0] ? 1 : -1);
   return(gHtfBias);
  }

//============================ GAP OBJECTS ===========================
string GapName(const int id,const string s){ return(gPrefix+"G"+IntegerToString(id)+"_"+s); }
void GapDelete(const FVG &f){ DelObj(GapName(f.id,"F")); DelObj(GapName(f.id,"B")); DelObj(GapName(f.id,"M")); }
void GapRender(FVG &f,const datetime &time[],const int n,const int lastBar)
  {
   if(gHeadless || !InpShowBoxes) return;
   if(!f.hasBox) return;
   datetime t1=TimeAtBar(f.bornBar-2,time,n);
   datetime t2=TimeAtBar(f.rightBar,time,n);      // live gaps keep extending (rightBar updated per bar)
   color base=(f.dir==1 ? InpColBull : InpColBear);
   bool ifvg=(f.inverted && InpShowIFVG);
   color fill=ifvg ? Blend(InpColIFVG,MathMin(InpBoxTransp+4,98)) : Blend(base,InpBoxTransp);
   color bord=ifvg ? Blend(InpColIFVG,10) : Blend(base,35);
   PutRect(GapName(f.id,"F"),t1,f.top,t2,f.bot,fill,true);
   PutRect(GapName(f.id,"B"),t1,f.top,t2,f.bot,bord,false,ifvg ? STYLE_DASH : STYLE_SOLID);
   if(InpShowMid)
     {
      double m=(f.top+f.bot)/2.0;
      PutLine(GapName(f.id,"M"),t1,t2,m,Blend(base,45),1,STYLE_DOT);
     }
  }

//============================ TRADE OBJECTS =========================
string TrName(const int id,const string s){ return(gPrefix+"T"+IntegerToString(id)+"_"+s); }
void TradeDelete(const int id)
  {
   string k[14]={"EN","SL","T1","T2","T3","TB","SB","SG","LE","LS","L1","L2","L3","EX"};
   for(int i=0;i<14;i++) DelObj(TrName(id,k[i]));
  }
void TradeRender(const TradeRec &r,const datetime &time[],const int n,const int lastBar,const double atr0,const double &high[],const double &low[])
  {
   if(gHeadless) return;
   bool L=(r.side==1);
   int  xr=(r.result==0) ? MathMax(r.bar+1,lastBar+InpProjBars) : r.closeEdge;
   datetime t0=TimeAtBar(r.bar,time,n), tx=TimeAtBar(xr,time,n);
   color c=L ? InpColBull : InpColBear;
   int fs=FontSz(InpLblSize);
   if(InpShowSignal && r.bar<n)
     {
      double ly=L ? low[r.bar]-atr0*0.6 : high[r.bar]+atr0*0.6;
      string head=L ? "BUY" : "SELL";
      string txt=InpShowStars ? head+"\n"+Stars(r.grade)+"  "+F1(r.grade)+"/10" : head;
      PutText(TrName(r.id,"SG"),t0,ly,txt,c,fs,L ? ANCHOR_UPPER : ANCHOR_LOWER,true);
     }
   if(InpShowZones)
     {
      PutRect(TrName(r.id,"TB"),t0,L ? r.t3 : r.entry,tx,L ? r.entry : r.t3,Blend(InpColBull,84),true);
      PutRect(TrName(r.id,"SB"),t0,L ? r.entry : r.stop,tx,L ? r.stop : r.entry,Blend(REDRISK,82),true);
     }
   if(InpShowLines)
     {
      PutLine(TrName(r.id,"EN"),t0,tx,r.entry,CHROME,2,STYLE_SOLID);
      PutLine(TrName(r.id,"SL"),t0,tx,r.stop,Blend(REDRISK,10),1,STYLE_DASH);
      PutLine(TrName(r.id,"T1"),t0,tx,r.t1,Blend(InpColBull,12),1,STYLE_SOLID);
      PutLine(TrName(r.id,"T2"),t0,tx,r.t2,Blend(InpColBull,32),1,STYLE_SOLID);
      PutLine(TrName(r.id,"T3"),t0,tx,r.t3,Blend(InpColBull,50),1,STYLE_SOLID);
     }
   if(InpShowLevels)
     {
      datetime tl=(datetime)(tx+PeriodSeconds(_Period));
      PutText(TrName(r.id,"LE"),tl,r.entry,"ENTRY",CHROME,fs,ANCHOR_LEFT);
      PutText(TrName(r.id,"LS"),tl,r.stop,"SL",Blend(REDRISK,10),fs,ANCHOR_LEFT);
      PutText(TrName(r.id,"L1"),tl,r.t1,"TP1",Blend(InpColBull,12),fs,ANCHOR_LEFT);
      PutText(TrName(r.id,"L2"),tl,r.t2,"TP2",Blend(InpColBull,28),fs,ANCHOR_LEFT);
      PutText(TrName(r.id,"L3"),tl,r.t3,"TP3",Blend(InpColBull,44),fs,ANCHOR_LEFT);
     }
   if(InpShowExit && r.result!=0)
     {
      double resPx=(r.result==1) ? r.stop : (r.result==2 ? r.t3 : (L ? r.entry+r.resR*r.risk : r.entry-r.resR*r.risk));
      string txt=(r.result==1) ? "SL ✘ -1R" : (r.result==2 ? "TP ✔ +"+F1(InpTp3R)+"R" : "EXIT "+SignedR(r.resR));
      color rc=(r.resR>=0 ? InpColBull : InpColBear);
      bool down=L ? (r.resR>=0) : (r.resR<0);
      PutText(TrName(r.id,"EX"),tx,resPx,txt,rc,fs,down ? ANCHOR_LOWER : ANCHOR_UPPER,true);
     }
  }

//============================ RESET =================================
void ResetAll()
  {
   ArrayResize(gGaps,0); ArrayResize(gTrades,0); gTradeActive=false;
   gGapSeq=0; gTradeSeq=0; gLastFlipDir=0; gLastFlipBar=-1; gTotalBull=0; gTotalBear=0; gTotalInv=0;
   gProcessed=0; gProcessedTime=0; gLastSig=0; gLastSigTag=""; gLastSigBar=-1;
   gCumPV=0; gCumV=0; gVwapDay=0; gHtfBarT=0; gHtfBias=0; gSpotKey=""; gDashBuilt=false;
   if(!gHeadless) ObjectsDeleteAll(0,gPrefix,-1,-1);
  }

//============================ ENGINE (one confirmed bar) ============
void ProcessBar(const int i,const datetime &time[],const double &open[],const double &high[],const double &low[],
                const double &close[],const long &tick_volume[],const int n,const bool bulk)
  {
   double atr=gAtr[i];
   double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE); if(tick<=0) tick=_Point;
   double safeAtr=(atr<=0.0) ? tick : atr;
   int    htfBias=HtfBiasAt(time[i]);
   bool   useRej=(InpSigMode==SIG_REJ||InpSigMode==SIG_BOTH);
   bool   useInv=(InpSigMode==SIG_IFVG||InpSigMode==SIG_BOTH);
   bool   buySignal=false,sellSignal=false,bullFlip=false,bearFlip=false;
   string sigTag="";
   double capTop=0,capBot=0,capGrade=0; bool hasCap=false;

   //--- 1. update / age / fill / mitigation / inversion / rejection
   for(int g=ArraySize(gGaps)-1;g>=0;g--)
     {
      int age=i-gGaps[g].bornBar;
      bool drop=false;
      if(!gGaps[g].inverted)
        {
         if(gGaps[g].dir==1)
           {
            gGaps[g].ext=MathMin(gGaps[g].ext,low[i]);
            gGaps[g].fillPct=MathMax(0.0,MathMin(1.0,(gGaps[g].top-gGaps[g].ext)/MathMax(gGaps[g].top-gGaps[g].bot,tick)));
            if(low[i]<=gGaps[g].bot)
              {
               gGaps[g].mitigated=true;
               if(InpHideFilled && gGaps[g].hasBox){ if(!bulk) GapDelete(gGaps[g]); gGaps[g].hasBox=false; }
              }
            if(close[i]<gGaps[g].bot)
              {
               gGaps[g].inverted=true; gTotalInv++; gLastFlipDir=-1; gLastFlipBar=i;
               if(!bulk) GapRender(gGaps[g],time,n,i);
               if(useInv)
                 {
                  bearFlip=true;
                  if(htfBias<=0 && gGaps[g].grade>=InpMinGrade)
                    { sellSignal=true; sigTag="IFVG▼"; capTop=gGaps[g].top; capBot=gGaps[g].bot; capGrade=gGaps[g].grade; hasCap=true; }
                 }
              }
           }
         else
           {
            gGaps[g].ext=MathMax(gGaps[g].ext,high[i]);
            gGaps[g].fillPct=MathMax(0.0,MathMin(1.0,(gGaps[g].ext-gGaps[g].bot)/MathMax(gGaps[g].top-gGaps[g].bot,tick)));
            if(high[i]>=gGaps[g].top)
              {
               gGaps[g].mitigated=true;
               if(InpHideFilled && gGaps[g].hasBox){ if(!bulk) GapDelete(gGaps[g]); gGaps[g].hasBox=false; }
              }
            if(close[i]>gGaps[g].top)
              {
               gGaps[g].inverted=true; gTotalInv++; gLastFlipDir=1; gLastFlipBar=i;
               if(!bulk) GapRender(gGaps[g],time,n,i);
               if(useInv)
                 {
                  bullFlip=true;
                  if(htfBias>=0 && gGaps[g].grade>=InpMinGrade)
                    { buySignal=true; sigTag="IFVG▲"; capTop=gGaps[g].top; capBot=gGaps[g].bot; capGrade=gGaps[g].grade; hasCap=true; }
                 }
              }
           }
        }
      // rejection signals from live gaps
      if(useRej && !gGaps[g].mitigated && !gGaps[g].inverted && !gGaps[g].reacted && age>=1)
        {
         if(gGaps[g].dir==1 && InpAllowBull)
           {
            bool tapped=(low[i]<=gGaps[g].top && low[i]>=gGaps[g].bot && close[i]>gGaps[g].bot);
            bool okClose=(!InpReqDirClose || close[i]>open[i]);
            if(tapped && okClose && gGaps[g].grade>=InpMinGrade && htfBias>=0)
              { gGaps[g].reacted=true; buySignal=true; sigTag="FVG▲"; capTop=gGaps[g].top; capBot=gGaps[g].bot; capGrade=gGaps[g].grade; hasCap=true; }
           }
         if(gGaps[g].dir==-1 && InpAllowBear)
           {
            bool tapped=(high[i]>=gGaps[g].bot && high[i]<=gGaps[g].top && close[i]<gGaps[g].top);
            bool okClose=(!InpReqDirClose || close[i]<open[i]);
            if(tapped && okClose && gGaps[g].grade>=InpMinGrade && htfBias<=0)
              { gGaps[g].reacted=true; sellSignal=true; sigTag="FVG▼"; capTop=gGaps[g].top; capBot=gGaps[g].bot; capGrade=gGaps[g].grade; hasCap=true; }
           }
        }
      if(age>InpMaxAge) drop=true;
      else if(!gGaps[g].inverted && !gGaps[g].mitigated) gGaps[g].rightBar=i+InpExtendBars;   // box.set_right
      if(drop){ if(!bulk) GapDelete(gGaps[g]); ArrayRemove(gGaps,g,1); }
     }

   //--- 2. detect new gaps
   if(i>=2)
     {
      double bodyRatio=MathAbs(close[i-1]-open[i-1])/MathMax(high[i-1]-low[i-1],tick);
      double disp3=(high[i-1]-low[i-1])/safeAtr;
      bool   hasVol=(tick_volume[i]>0);
      double volScore=(hasVol && gVolAvg[i]>0) ? MathMin((double)tick_volume[i-1]/gVolAvg[i],2.0)/2.0 : 0.5;
      bool newBull=InpAllowBull && low[i]>high[i-2];
      bool newBear=InpAllowBear && high[i]<low[i-2];
      for(int pass=0;pass<2;pass++)
        {
         bool isB=(pass==0);
         if(isB && !newBull) continue;
         if(!isB && !newBear) continue;
         double gTop=isB ? low[i] : low[i-2];
         double gBot=isB ? high[i-2] : high[i];
         double gapAtr=(gTop-gBot)/safeAtr;
         if(gapAtr>=InpMinGapAtr && bodyRatio>=InpMinBodyRat)
           {
            double sizeScore=MathMin(gapAtr/1.0,1.0), dispScore=MathMin(disp3/2.0,1.0);
            double grade=MathMin(10.0,(sizeScore*0.40+dispScore*0.35+volScore*0.25)*10.0);
            int k=ArraySize(gGaps); ArrayResize(gGaps,k+1);
            gGaps[k].top=gTop; gGaps[k].bot=gBot; gGaps[k].dir=isB ? 1 : -1; gGaps[k].bornBar=i; gGaps[k].grade=grade;
            gGaps[k].ext=isB ? gTop : gBot; gGaps[k].fillPct=0; gGaps[k].mitigated=false; gGaps[k].inverted=false; gGaps[k].reacted=false;
            gGaps[k].hasBox=InpShowBoxes; gGaps[k].id=++gGapSeq; gGaps[k].rightBar=i+InpExtendBars;
            if(isB) gTotalBull++; else gTotalBear++;
            if(!bulk) GapRender(gGaps[k],time,n,i);
           }
        }
     }

   //--- 3. cap visible gaps
   while(ArraySize(gGaps)>InpMaxGaps){ if(!bulk) GapDelete(gGaps[0]); ArrayRemove(gGaps,0,1); }

   //--- 4. open a trade blueprint
   bool takeLong =buySignal  && !gTradeActive && atr>0 && hasCap;
   bool takeShort=sellSignal && !gTradeActive && atr>0 && hasCap && !takeLong;
   if(takeLong||takeShort)
     {
      bool L=takeLong;
      double entv=close[i];
      double rawStop=(InpStopMode==STOP_ATR) ? (L ? entv-atr*InpSlAtrMult : entv+atr*InpSlAtrMult)
                                             : (L ? capBot-atr*InpSlBufAtr : capTop+atr*InpSlBufAtr);
      double risk=MathMin(MathMax(MathAbs(entv-rawStop),atr*InpMinRiskAtr),atr*InpMaxRiskAtr);
      int k=ArraySize(gTrades); ArrayResize(gTrades,k+1);
      gTrades[k].id=++gTradeSeq; gTrades[k].side=L ? 1 : -1; gTrades[k].bar=i; gTrades[k].entry=entv;
      gTrades[k].stop=L ? entv-risk : entv+risk;
      gTrades[k].t1=L ? entv+risk*InpTp1R : entv-risk*InpTp1R;
      gTrades[k].t2=L ? entv+risk*InpTp2R : entv-risk*InpTp2R;
      gTrades[k].t3=L ? entv+risk*InpTp3R : entv-risk*InpTp3R;
      gTrades[k].risk=risk; gTrades[k].grade=capGrade; gTrades[k].closeEdge=-1; gTrades[k].result=0; gTrades[k].resR=0;
      gTradeActive=true;
      if(!bulk) TradeRender(gTrades[k],time,n,i,safeAtr,high,low);
     }

   //--- trade management (after the engine, like the Pine block order)
   if(gTradeActive)
     {
      int k=ArraySize(gTrades)-1;
      if(i>gTrades[k].bar)
        {
         bool L=(gTrades[k].side==1);
         bool slHit=L ? low[i]<=gTrades[k].stop : high[i]>=gTrades[k].stop;
         bool tpHit=L ? high[i]>=gTrades[k].t3 : low[i]<=gTrades[k].t3;
         bool expired=(i-gTrades[k].bar)>=InpTradeMaxBars;
         if(slHit||tpHit||expired)
           {
            gTrades[k].resR=slHit ? -1.0 : (tpHit ? InpTp3R : (L ? (close[i]-gTrades[k].entry)/gTrades[k].risk : (gTrades[k].entry-close[i])/gTrades[k].risk));
            gTrades[k].result=slHit ? 1 : (tpHit ? 2 : 3);
            gTrades[k].closeEdge=MathMax(gTrades[k].bar+3,i);
            gTradeActive=false;
            if(!bulk) TradeRender(gTrades[k],time,n,i,safeAtr,high,low);
            while(ArraySize(gTrades)>InpMaxHist){ if(!bulk) TradeDelete(gTrades[0].id); ArrayRemove(gTrades,0,1); }
           }
        }
     }

   //--- outputs
   BufBuy[i]=buySignal ? 1.0 : EMPTY_VALUE;  BufSell[i]=sellSignal ? 1.0 : EMPTY_VALUE;
   BufBullFlip[i]=bullFlip ? 1.0 : EMPTY_VALUE; BufBearFlip[i]=bearFlip ? 1.0 : EMPTY_VALUE;
   if(buySignal||sellSignal){ gLastSig=buySignal ? 1 : -1; gLastSigTag=sigTag; gLastSigBar=i; }
   if(!bulk && InpAlerts)
     {
      string s=_Symbol+" / "+EnumToString(_Period);
      if(buySignal)  Alert("FVG Sniper [JOAT] | BUY signal on ",s);
      if(sellSignal) Alert("FVG Sniper [JOAT] | SELL signal on ",s);
      if(bullFlip)   Alert("FVG Sniper [JOAT] | Bullish IFVG inversion on ",s);
      if(bearFlip)   Alert("FVG Sniper [JOAT] | Bearish IFVG inversion on ",s);
     }
  }

//============================ SPOTLIGHT + DASHBOARD =================
string DName(const int c,const int r){ return(gPrefix+"D_"+IntegerToString(c)+"_"+IntegerToString(r)); }
void DashCell(const int c,const int r,const string txt,const color col,const color bg)
  {
   int idx=c*DROWS+r; string nm=DName(c,r), bgn=nm+"bg";
   if(gDashTxt[idx]!=txt){ ObjectSetString(0,nm,OBJPROP_TEXT,txt); gDashTxt[idx]=txt; }
   if(gDashCol[idx]!=col){ ObjectSetInteger(0,nm,OBJPROP_COLOR,col); gDashCol[idx]=col; }
   if(gDashBg[idx]!=bg){ ObjectSetInteger(0,bgn,OBJPROP_BGCOLOR,bg); ObjectSetInteger(0,bgn,OBJPROP_COLOR,bg); gDashBg[idx]=bg; }
  }
// pixel width/height of a string in the dashboard font (uses the same font the label will use)
int TextWRaw(const string txt,const int fs,const bool bold=false)
  {
   TextSetFont(bold ? "Arial Black" : "Arial",-fs*10);   // negative = size in 1/10 pt
   uint tw=0,th=0; TextGetSize(txt,tw,th);
   return (int)tw;
  }
int TextW(const string txt,const int fs,const bool bold=false){ return (int)MathCeil(TextWRaw(txt,fs,bold)*1.25)+4; }
int TextH(const int fs){ TextSetFont("Arial",-fs*10); uint tw=0,th=0; TextGetSize("Ag",tw,th); return (int)th; }
void DashBuild(const int w1Req)
  {
   int fs=FontSz(InpDashSize), pad=10;
   int rowH=TextH(fs)+10;
   // label column: widest fixed label
   string labels[DROWS]={"FVG SNIPER","HTF Bias","Active Bull FVG","Active Bear FVG","Nearest Gap","Nearest Fill %","Strongest Gap","Last IFVG Flip","Active Signal","Active Trade","Gaps B / Br / Inv"};
   int w0=0; for(int r=0;r<DROWS;r++) w0=MathMax(w0,TextW(labels[r],fs,r==0));
   w0+=pad*2;
   int w1=MathMax(w1Req,TextW("[JOAT]",fs,true))+pad*2;
   TextSetFont("Consolas",-fs*10); uint bw=0,bhh=0; TextGetSize(BRAND_TXT,bw,bhh);
   int brandW=(int)MathCeil(bw*1.25)+pad*2+4;
   if(w0+w1<brandW) w1=brandW-w0;
   gDashW0=w0; gDashW1=w1; gDashRowH=rowH;
   int w=w0+w1, h=rowH*DROWS;
   ENUM_BASE_CORNER corner=CORNER_LEFT_UPPER; int x0=8,y0=8;
   bool right=false, lower=false;
   for(int c=0;c<2;c++) for(int r=0;r<DROWS;r++)
     {
      string nm=DName(c,r), bgn=nm+"bg";
      int cw=(c==0 ? w0 : w1);
      int xd=right ? x0+(c==0 ? w1 : 0) : x0+(c==0 ? 0 : w0);
      int yd=lower ? y0+(DROWS-1-r)*rowH : y0+r*rowH;
      if(ObjectFind(0,bgn)<0) ObjectCreate(0,bgn,OBJ_RECTANGLE_LABEL,0,0,0);
      ObjectSetInteger(0,bgn,OBJPROP_CORNER,corner);
      ObjectSetInteger(0,bgn,OBJPROP_XDISTANCE,xd); ObjectSetInteger(0,bgn,OBJPROP_YDISTANCE,yd);
      ObjectSetInteger(0,bgn,OBJPROP_XSIZE,cw); ObjectSetInteger(0,bgn,OBJPROP_YSIZE,rowH);
      ObjectSetInteger(0,bgn,OBJPROP_BORDER_TYPE,BORDER_FLAT);
      ObjectSetInteger(0,bgn,OBJPROP_ZORDER,100); ObjCommon(bgn,false);
      if(ObjectFind(0,nm)<0) ObjectCreate(0,nm,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,nm,OBJPROP_CORNER,corner);
      ObjectSetInteger(0,nm,OBJPROP_ANCHOR,right ? (lower ? ANCHOR_RIGHT_LOWER : ANCHOR_RIGHT_UPPER) : (lower ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER));
      ObjectSetInteger(0,nm,OBJPROP_XDISTANCE,xd+pad); ObjectSetInteger(0,nm,OBJPROP_YDISTANCE,yd+5);
      ObjectSetString(0,nm,OBJPROP_FONT,r==0 ? "Arial Black" : "Arial"); ObjectSetInteger(0,nm,OBJPROP_FONTSIZE,fs);
      ObjectSetInteger(0,nm,OBJPROP_ZORDER,101); ObjCommon(nm,false);
      gDashTxt[c*DROWS+r]=""; gDashCol[c*DROWS+r]=clrNONE; gDashBg[c*DROWS+r]=clrNONE;
     }
   //--- brand box under the dashboard (ATB style)
   string bb=gPrefix+"BRAND", bl=gPrefix+"BRANDL"; int bh=rowH;
   if(ObjectFind(0,bb)<0) ObjectCreate(0,bb,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,bb,OBJPROP_CORNER,corner); ObjectSetInteger(0,bb,OBJPROP_XDISTANCE,x0); ObjectSetInteger(0,bb,OBJPROP_YDISTANCE,y0+h+4);
   ObjectSetInteger(0,bb,OBJPROP_XSIZE,w); ObjectSetInteger(0,bb,OBJPROP_YSIZE,bh);
   ObjectSetInteger(0,bb,OBJPROP_BGCOLOR,InpDarkDash ? C'16,18,24' : C'244,246,248'); ObjectSetInteger(0,bb,OBJPROP_BORDER_TYPE,BORDER_FLAT); ObjectSetInteger(0,bb,OBJPROP_COLOR,C'60,64,76');
   ObjectSetInteger(0,bb,OBJPROP_ZORDER,100); ObjCommon(bb,false);
   if(ObjectFind(0,bl)<0) ObjectCreate(0,bl,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,bl,OBJPROP_CORNER,corner); ObjectSetInteger(0,bl,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0,bl,OBJPROP_XDISTANCE,x0+pad); ObjectSetInteger(0,bl,OBJPROP_YDISTANCE,y0+h+4+5);
   ObjectSetString(0,bl,OBJPROP_FONT,"Consolas"); ObjectSetInteger(0,bl,OBJPROP_FONTSIZE,fs);
   ObjectSetString(0,bl,OBJPROP_TEXT,BRAND_TXT); ObjectSetInteger(0,bl,OBJPROP_COLOR,C'255,200,60');
   ObjectSetInteger(0,bl,OBJPROP_ZORDER,101); ObjCommon(bl,false);
   gDashBuilt=true;
  }
void DashDelete(){ if(!gDashBuilt) return; for(int c=0;c<2;c++) for(int r=0;r<DROWS;r++){ DelObj(DName(c,r)); DelObj(DName(c,r)+"bg"); } DelObj(gPrefix+"BRAND"); DelObj(gPrefix+"BRANDL"); gDashBuilt=false; }

void SpotAndDash(const int last,const datetime &time[],const double &close[],const int n)
  {
   if(gHeadless) return;
   if(!InpShowDash && !InpShowGrade){ DashDelete(); DelObj(gPrefix+"SPOT"); return; }
   int actBull=0,actBear=0,bestDir=0,nearDir=0; double bestGrade=0,spotTop=0,spotBot=0,nearDist=-1,nearFill=0,nearPrice=0;
   for(int g=0;g<ArraySize(gGaps);g++)
     {
      if(gGaps[g].inverted||gGaps[g].mitigated) continue;
      if(gGaps[g].dir==1) actBull++; else actBear++;
      if(gGaps[g].grade>bestGrade){ bestGrade=gGaps[g].grade; bestDir=gGaps[g].dir; spotTop=gGaps[g].top; spotBot=gGaps[g].bot; }
      double ref=(gGaps[g].top+gGaps[g].bot)/2.0, d=MathAbs(close[last]-ref);
      if(nearDist<0 || d<nearDist){ nearDist=d; nearFill=gGaps[g].fillPct; nearPrice=ref; nearDir=gGaps[g].dir; }
     }
   //--- spotlight
   if(InpShowGrade)
     {
      string key=(bestGrade>0) ? IntegerToString(bestDir)+"|"+DoubleToString(bestGrade,2)+"|"+IntegerToString((long)time[last]) : "";
      if(key!=gSpotKey)
        {
         gSpotKey=key;
         if(bestGrade<=0) DelObj(gPrefix+"SPOT");
         else
           {
            double sy=(bestDir==1 ? spotBot : spotTop);
            PutText(gPrefix+"SPOT",time[last],sy,Stars(bestGrade)+"  "+F1(bestGrade),bestDir==1 ? InpColBull : InpColBear,FontSz(InpLblSize),bestDir==1 ? ANCHOR_UPPER : ANCHOR_LOWER,true);
           }
        }
     }
   else DelObj(gPrefix+"SPOT");
   //--- dashboard
   if(!InpShowDash){ DashDelete(); return; }
   color bg   =InpDarkDash ? C'16,18,24'    : C'244,246,248';
   color bgAlt=InpDarkDash ? C'26,29,37'    : C'230,233,238';
   color txt  =InpDarkDash ? C'232,236,242' : C'24,26,30';
   color muted=InpDarkDash ? C'150,156,168' : C'96,100,108';
   int htf=HtfBiasAt(time[last]); if(!InpUseHTF) htf=0;
   string biasTxt=htf>0 ? "BULLISH" : (htf<0 ? "BEARISH" : "NEUTRAL"); color biasCol=htf>0 ? InpColBull : (htf<0 ? InpColBear : muted);
   bool sigNow=(gLastSigBar==last-1 || gLastSigBar==last);   // signal on the last confirmed bar
   string activeTxt=sigNow ? ((gLastSig==1 ? "BUY " : "SELL ")+gLastSigTag) : "—";
   color activeCol=sigNow ? (gLastSig==1 ? InpColBull : InpColBear) : muted;
   string flipTxt=gLastFlipDir==1 ? "▲ Bull" : (gLastFlipDir==-1 ? "▼ Bear" : "—");
   string flipAge=(gLastFlipBar<0) ? "" : "  ("+IntegerToString(last-gLastFlipBar)+"b)";
   color flipCol=gLastFlipDir==1 ? InpColBull : (gLastFlipDir==-1 ? InpColBear : muted);
   string trTxt="—"; color trCol=muted;
   if(gTradeActive){ int k=ArraySize(gTrades)-1; trTxt=(gTrades[k].side==1 ? "BUY @ " : "SELL @ ")+Px(gTrades[k].entry); trCol=(gTrades[k].side==1 ? InpColBull : InpColBear); }
   //--- size the value column to the widest value (rebuild only when it changes)
   string vals[DROWS];
   vals[0]="[JOAT]"; vals[1]=biasTxt; vals[2]=IntegerToString(actBull); vals[3]=IntegerToString(actBear);
   vals[4]=nearDist<0 ? "—" : Px(nearPrice)+(nearDir==1 ? " ▲" : " ▼");
   vals[5]=nearDist<0 ? "—" : IntegerToString((int)MathRound(nearFill*100))+"%";
   vals[6]=bestGrade>0 ? Stars(bestGrade)+" "+F1(bestGrade) : "—";
   vals[7]=flipTxt+flipAge; vals[8]=activeTxt; vals[9]=trTxt;
   vals[10]=IntegerToString(gTotalBull)+" / "+IntegerToString(gTotalBear)+" / "+IntegerToString(gTotalInv);
   int fsD=FontSz(InpDashSize), need=0;
   for(int r=0;r<DROWS;r++) need=MathMax(need,TextW(vals[r],fsD,r==0));
   if(!gDashBuilt || ObjectFind(0,DName(0,0))<0 || need+20>gDashW1) DashBuild(need);
   color headHue=Grad(CHROME,InpColBull,bestGrade/10.0);
   color dark=C'10,12,16';
   DashCell(0,0,"FVG SNIPER",dark,headHue);        DashCell(1,0,"[JOAT]",dark,CHROME);
   DashCell(0,1,"HTF Bias",muted,bg);              DashCell(1,1,biasTxt,biasCol,bg);
   DashCell(0,2,"Active Bull FVG",muted,bgAlt);    DashCell(1,2,IntegerToString(actBull),InpColBull,bgAlt);
   DashCell(0,3,"Active Bear FVG",muted,bg);       DashCell(1,3,IntegerToString(actBear),InpColBear,bg);
   DashCell(0,4,"Nearest Gap",muted,bgAlt);        DashCell(1,4,nearDist<0 ? "—" : Px(nearPrice)+(nearDir==1 ? " ▲" : " ▼"),txt,bgAlt);
   DashCell(0,5,"Nearest Fill %",muted,bg);        DashCell(1,5,nearDist<0 ? "—" : IntegerToString((int)MathRound(nearFill*100))+"%",txt,bg);
   DashCell(0,6,"Strongest Gap",muted,bgAlt);      DashCell(1,6,bestGrade>0 ? Stars(bestGrade)+" "+F1(bestGrade) : "—",bestDir==1 ? InpColBull : (bestDir==-1 ? InpColBear : txt),bgAlt);
   DashCell(0,7,"Last IFVG Flip",muted,bg);        DashCell(1,7,flipTxt+flipAge,flipCol,bg);
   DashCell(0,8,"Active Signal",muted,bgAlt);      DashCell(1,8,activeTxt,activeCol,bgAlt);
   DashCell(0,9,"Active Trade",muted,bg);          DashCell(1,9,trTxt,trCol,bg);
   DashCell(0,10,"Gaps B / Br / Inv",muted,bgAlt); DashCell(1,10,IntegerToString(gTotalBull)+" / "+IntegerToString(gTotalBear)+" / "+IntegerToString(gTotalInv),txt,bgAlt);
  }

//============================ INIT ==================================
int OnInit()
  {
   gPrefix="FVGS_"+IntegerToString((int)ChartID())+"_";
   gHeadless=(MQLInfoInteger(MQL_TESTER)&&!MQLInfoInteger(MQL_VISUAL_MODE))||MQLInfoInteger(MQL_OPTIMIZATION);
   gBg=(color)ChartGetInteger(0,CHART_COLOR_BACKGROUND);
   SetIndexBuffer(0,BufVwap,INDICATOR_DATA); SetIndexBuffer(1,BufVwUp,INDICATOR_DATA); SetIndexBuffer(2,BufVwLo,INDICATOR_DATA);
   SetIndexBuffer(3,BufBuy,INDICATOR_DATA); SetIndexBuffer(4,BufSell,INDICATOR_DATA);
   SetIndexBuffer(5,BufBullFlip,INDICATOR_DATA); SetIndexBuffer(6,BufBearFlip,INDICATOR_DATA);
   for(int p=0;p<7;p++) PlotIndexSetDouble(p,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetInteger(0,PLOT_LINE_COLOR,CHROME);
   PlotIndexSetInteger(1,PLOT_LINE_COLOR,Blend(CHROME,70));
   PlotIndexSetInteger(2,PLOT_LINE_COLOR,Blend(CHROME,70));
   if(InpUseHTF) gHtfHandle=iMA(_Symbol,InpHtfTF,InpHtfEma,0,MODE_EMA,PRICE_CLOSE);
   IndicatorSetString(INDICATOR_SHORTNAME,"FVG Sniper");
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   gArr=0; ResetAll();
   return(INIT_SUCCEEDED);
  }
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0,gPrefix,-1,-1);
   if(gHtfHandle!=INVALID_HANDLE) IndicatorRelease(gHtfHandle);
  }

//============================ MAIN ==================================
int OnCalculate(const int rates_total,const int prev_calculated,
                const datetime &time[],const double &open[],const double &high[],
                const double &low[],const double &close[],const long &tick_volume[],
                const long &volume[],const int &spread[])
  {
   if(rates_total<30) return(0);
   if(InpUseHTF && gHtfHandle!=INVALID_HANDLE && BarsCalculated(gHtfHandle)<=0) return(0);   // wait for HTF data
   ArraySetAsSeries(time,false); ArraySetAsSeries(open,false); ArraySetAsSeries(high,false);
   ArraySetAsSeries(low,false); ArraySetAsSeries(close,false); ArraySetAsSeries(tick_volume,false);
   ArraySetAsSeries(BufVwap,false); ArraySetAsSeries(BufVwUp,false); ArraySetAsSeries(BufVwLo,false);
   ArraySetAsSeries(BufBuy,false); ArraySetAsSeries(BufSell,false); ArraySetAsSeries(BufBullFlip,false); ArraySetAsSeries(BufBearFlip,false);

   int n=rates_total, last=n-1;
   bool full=(prev_calculated<=0 || prev_calculated>n || gProcessed>n-1 || (gProcessed>0 && time[gProcessed-1]!=gProcessedTime));
   if(full){ ResetAll(); gArr=0; }
   if(gArr!=n){ ArrayResize(gAtr,n); ArrayResize(gTR,n); ArrayResize(gVolAvg,n); ArrayResize(gVwap,n); ArrayResize(gVwSd,n); gArr=n; }

   //--- series (ATR = RMA of TR, SMA volume 20, session VWAP on hlc3, stdev(close,100)) - incl. live bar
   int from=(full ? 0 : MathMax(0,prev_calculated-1));
   int p=MathMax(1,InpAtrLen);
   for(int i=from;i<n;i++)
     {
      double tr=high[i]-low[i];
      if(i>0){ tr=MathMax(tr,MathAbs(high[i]-close[i-1])); tr=MathMax(tr,MathAbs(low[i]-close[i-1])); }
      gTR[i]=tr;
      if(i<p-1) gAtr[i]=0.0;
      else if(i==p-1 || gAtr[i-1]<=0.0){ double s=0; for(int j=i-p+1;j<=i;j++) s+=gTR[j]; gAtr[i]=s/p; }
      else gAtr[i]=(gAtr[i-1]*(p-1)+tr)/p;
      if(i>=19){ double s=0; for(int j=i-19;j<=i;j++) s+=(double)tick_volume[j]; gVolAvg[i]=s/20.0; } else gVolAvg[i]=0.0;
      // VWAP (daily anchored)
      MqlDateTime dt; TimeToStruct(time[i],dt); dt.hour=0; dt.min=0; dt.sec=0; datetime day=StructToTime(dt);
      if(day!=gVwapDay){ gVwapDay=day; gCumPV=0; gCumV=0; }
      double hlc=(high[i]+low[i]+close[i])/3.0; double v=(double)tick_volume[i];
      double pv=gCumPV+hlc*v, vv=gCumV+v;
      gVwap[i]=(vv>0 ? pv/vv : hlc);
      if(i<n-1){ gCumPV=pv; gCumV=vv; }          // commit only closed bars; live bar recomputed each tick
      if(i>=99){ double m=0; for(int j=i-99;j<=i;j++) m+=close[j]; m/=100.0; double s2=0; for(int j=i-99;j<=i;j++) s2+=(close[j]-m)*(close[j]-m); gVwSd[i]=MathSqrt(s2/100.0); } else gVwSd[i]=0.0;
      BufVwap[i]=InpUseVwap ? gVwap[i] : EMPTY_VALUE;
      BufVwUp[i]=InpUseVwap ? gVwap[i]+InpVwapDev*gVwSd[i] : EMPTY_VALUE;
      BufVwLo[i]=InpUseVwap ? gVwap[i]-InpVwapDev*gVwSd[i] : EMPTY_VALUE;
      if(i>=gProcessed){ BufBuy[i]=EMPTY_VALUE; BufSell[i]=EMPTY_VALUE; BufBullFlip[i]=EMPTY_VALUE; BufBearFlip[i]=EMPTY_VALUE; }
     }

   //--- engine: every CLOSED bar exactly once
   bool bulk=full;
   int closedBars=n-1;
   for(int i=gProcessed;i<closedBars;i++)
     {
      ProcessBar(i,time,open,high,low,close,tick_volume,n,bulk && i<closedBars-1);
      gProcessed=i+1; gProcessedTime=time[i];
     }

   //--- render after a bulk pass: only objects that still exist
   if(!gHeadless)
     {
      double safeAtr=(gAtr[last]>0 ? gAtr[last] : _Point);
      if(full)
        {
         for(int g=0;g<ArraySize(gGaps);g++) GapRender(gGaps[g],time,n,closedBars-1);
         for(int t=0;t<ArraySize(gTrades);t++) TradeRender(gTrades[t],time,n,closedBars-1,safeAtr,high,low);
        }
      else if(prev_calculated<n)      // new bar: extend live gap boxes and the active trade
        {
         for(int g=0;g<ArraySize(gGaps);g++) if(!gGaps[g].inverted && !gGaps[g].mitigated) GapRender(gGaps[g],time,n,closedBars-1);
         if(gTradeActive){ int k=ArraySize(gTrades)-1; TradeRender(gTrades[k],time,n,closedBars-1,safeAtr,high,low); }
        }
      SpotAndDash(last,time,close,n);
      if(full || prev_calculated<n) ChartRedraw(0);
     }
   return(rates_total);
  }
//+------------------------------------------------------------------+
