//+------------------------------------------------------------------+
//|                                            BreakoutStraddle.mq5  |
//|  Scalper de breakout para MT5 (pensado para XAUUSD M1).          |
//|                                                                  |
//|  Logica:                                                         |
//|   1. Sem posicao aberta -> coloca BUY STOP acima do Ask e        |
//|      SELL STOP abaixo do Bid, ambos com Stop Loss curto.         |
//|   2. As ordens pendentes seguem o preco enquanto nao disparam.   |
//|   3. Quando uma dispara, a outra e apagada (OCO).                |
//|   4. A posicao e gerida com break-even + trailing stop.          |
//|   5. Quando a posicao fecha, o ciclo repete.                     |
//+------------------------------------------------------------------+
#property copyright "BreakoutStraddle"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Entradas
input group "Lote / Risco"
input double InpLots            = 0.10;   // Lote fixo (usado se RiskPercent = 0)
input double InpRiskPercent     = 0.0;    // Risco por trade em % do saldo (0 = usar lote fixo)

input group "Ordens pendentes (em pontos)"
input int    InpEntryDistance   = 100;    // Distancia das ordens STOP ao preco
input int    InpPendingTrail    = 30;     // Reajustar pendentes se o preco se afastar mais que isto
input int    InpStopLoss        = 150;    // Stop Loss
input int    InpTakeProfit      = 0;      // Take Profit (0 = sem TP, sai por trailing)

input group "Gestao da posicao (em pontos)"
input int    InpBreakEvenStart  = 80;     // Lucro para mover SL para break-even (0 = desligado)
input int    InpBreakEvenLock   = 10;     // Pontos garantidos no break-even
input int    InpTrailStart      = 120;    // Lucro para iniciar trailing (0 = desligado)
input int    InpTrailDistance   = 80;     // Distancia do trailing stop
input int    InpTrailStep       = 10;     // Passo minimo para mover o SL

input group "Filtros"
input int    InpMaxSpread       = 40;     // Spread maximo permitido (pontos)
input int    InpStartHour       = 0;      // Hora de inicio (hora do servidor)
input int    InpEndHour         = 24;     // Hora de fim (hora do servidor)
input int    InpCooldownSeconds = 0;      // Espera apos fechar posicao (segundos)
input int    InpMaxDailyLossPct = 0;      // Perda diaria maxima em % (0 = desligado)

input group "Geral"
input ulong  InpMagic           = 20261121; // Magic number
input string InpComment         = "BreakoutStraddle";

//--- Globais
CTrade   trade;
double   g_point;
int      g_digits;
datetime g_lastClose = 0;
double   g_dayStartBalance = 0;
int      g_day = -1;

//+------------------------------------------------------------------+
int OnInit()
  {
   g_point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(20);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetAsyncMode(false);

   if(InpEntryDistance <= 0 || InpStopLoss <= 0)
     {
      Print("EntryDistance e StopLoss tem de ser > 0");
      return INIT_PARAMETERS_INCORRECT;
     }
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   UpdateDailyBalance();

   ulong posTicket = 0;
   int   posCount  = CountPositions(posTicket);
   ulong buyStop = 0, sellStop = 0;
   CountPendings(buyStop, sellStop);

   //--- Ha posicao: apagar pendentes (OCO) e gerir SL
   if(posCount > 0)
     {
      if(buyStop  > 0) trade.OrderDelete(buyStop);
      if(sellStop > 0) trade.OrderDelete(sellStop);
      ManagePosition(posTicket);
      return;
     }

   //--- Sem posicao
   if(!TradingAllowed())
     {
      if(buyStop  > 0) trade.OrderDelete(buyStop);
      if(sellStop > 0) trade.OrderDelete(sellStop);
      return;
     }

   if(SpreadPoints() > InpMaxSpread)
      return;

   if(InpCooldownSeconds > 0 && TimeCurrent() - g_lastClose < InpCooldownSeconds)
      return;

   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double dist = MathMax(InpEntryDistance, MinStopPoints()) * g_point;

   //--- BUY STOP
   double buyPrice = Norm(ask + dist);
   if(buyStop == 0)
      PlaceStop(ORDER_TYPE_BUY_STOP, buyPrice);
   else
      TrailPending(buyStop, buyPrice, true);

   //--- SELL STOP
   double sellPrice = Norm(bid - dist);
   if(sellStop == 0)
      PlaceStop(ORDER_TYPE_SELL_STOP, sellPrice);
   else
      TrailPending(sellStop, sellPrice, false);
  }

//+------------------------------------------------------------------+
//| Regista o fecho de posicoes para o cooldown                       |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != (long)InpMagic)
      return;
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) == DEAL_ENTRY_OUT)
      g_lastClose = TimeCurrent();
  }

//+------------------------------------------------------------------+
void PlaceStop(ENUM_ORDER_TYPE type, double price)
  {
   double lots = CalcLots();
   if(lots <= 0) return;

   double sl, tp = 0;
   if(type == ORDER_TYPE_BUY_STOP)
     {
      sl = Norm(price - InpStopLoss * g_point);
      if(InpTakeProfit > 0) tp = Norm(price + InpTakeProfit * g_point);
      if(!trade.BuyStop(lots, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, InpComment))
         PrintFormat("BuyStop falhou: %d %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
     }
   else
     {
      sl = Norm(price + InpStopLoss * g_point);
      if(InpTakeProfit > 0) tp = Norm(price - InpTakeProfit * g_point);
      if(!trade.SellStop(lots, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, InpComment))
         PrintFormat("SellStop falhou: %d %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
     }
  }

//+------------------------------------------------------------------+
//| Mantem a ordem pendente a distancia fixa do preco                 |
//+------------------------------------------------------------------+
void TrailPending(ulong ticket, double target, bool isBuy)
  {
   if(InpPendingTrail <= 0 || !OrderSelect(ticket))
      return;

   double cur = OrderGetDouble(ORDER_PRICE_OPEN);
   double gap = MathAbs(cur - target) / g_point;
   if(gap < InpPendingTrail)
      return;

   double sl, tp = 0;
   if(isBuy)
     {
      sl = Norm(target - InpStopLoss * g_point);
      if(InpTakeProfit > 0) tp = Norm(target + InpTakeProfit * g_point);
     }
   else
     {
      sl = Norm(target + InpStopLoss * g_point);
      if(InpTakeProfit > 0) tp = Norm(target - InpTakeProfit * g_point);
     }
   trade.OrderModify(ticket, target, sl, tp, ORDER_TIME_GTC, 0);
  }

//+------------------------------------------------------------------+
//| Break-even + trailing stop                                        |
//+------------------------------------------------------------------+
void ManagePosition(ulong ticket)
  {
   if(!PositionSelectByTicket(ticket))
      return;

   long   type  = PositionGetInteger(POSITION_TYPE);
   double open  = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl    = PositionGetDouble(POSITION_SL);
   double tp    = PositionGetDouble(POSITION_TP);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double minSt = MinStopPoints() * g_point;
   double newSL = sl;

   if(type == POSITION_TYPE_BUY)
     {
      double profitPts = (bid - open) / g_point;

      if(InpBreakEvenStart > 0 && profitPts >= InpBreakEvenStart)
        {
         double be = Norm(open + InpBreakEvenLock * g_point);
         if(be > newSL) newSL = be;
        }
      if(InpTrailStart > 0 && profitPts >= InpTrailStart)
        {
         double tr = Norm(bid - InpTrailDistance * g_point);
         if(tr > newSL) newSL = tr;
        }
      if(newSL > sl + InpTrailStep * g_point && newSL < bid - minSt)
         trade.PositionModify(ticket, newSL, tp);
     }
   else
     {
      double profitPts = (open - ask) / g_point;

      if(InpBreakEvenStart > 0 && profitPts >= InpBreakEvenStart)
        {
         double be = Norm(open - InpBreakEvenLock * g_point);
         if(sl == 0 || be < newSL) newSL = be;
        }
      if(InpTrailStart > 0 && profitPts >= InpTrailStart)
        {
         double tr = Norm(ask + InpTrailDistance * g_point);
         if(newSL == 0 || tr < newSL) newSL = tr;
        }
      if((sl == 0 || newSL < sl - InpTrailStep * g_point) && newSL > ask + minSt)
         trade.PositionModify(ticket, newSL, tp);
     }
  }

//+------------------------------------------------------------------+
int CountPositions(ulong &ticket)
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      ticket = t;
      n++;
     }
   return n;
  }

//+------------------------------------------------------------------+
void CountPendings(ulong &buyStop, ulong &sellStop)
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i);
      if(t == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != InpMagic) continue;

      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(type == ORDER_TYPE_BUY_STOP)
        {
         if(buyStop == 0) buyStop = t; else trade.OrderDelete(t); // remove duplicados
        }
      else if(type == ORDER_TYPE_SELL_STOP)
        {
         if(sellStop == 0) sellStop = t; else trade.OrderDelete(t);
        }
     }
  }

//+------------------------------------------------------------------+
double CalcLots()
  {
   double lots = InpLots;

   if(InpRiskPercent > 0)
     {
      double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickVal > 0 && tickSize > 0)
        {
         double riskMoney   = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
         double lossPerLot  = (InpStopLoss * g_point / tickSize) * tickVal;
         if(lossPerLot > 0) lots = riskMoney / lossPerLot;
        }
     }

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(stepLot > 0) lots = MathFloor(lots / stepLot) * stepLot;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   return NormalizeDouble(lots, 2);
  }

//+------------------------------------------------------------------+
bool TradingAllowed()
  {
   MqlDateTime t;
   TimeCurrent(t);
   bool inHours = (InpStartHour <= InpEndHour)
                  ? (t.hour >= InpStartHour && t.hour < InpEndHour)
                  : (t.hour >= InpStartHour || t.hour < InpEndHour);
   if(!inHours) return false;

   if(InpMaxDailyLossPct > 0 && g_dayStartBalance > 0)
     {
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      if((g_dayStartBalance - eq) / g_dayStartBalance * 100.0 >= InpMaxDailyLossPct)
         return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
void UpdateDailyBalance()
  {
   MqlDateTime t;
   TimeCurrent(t);
   if(t.day_of_year != g_day)
     {
      g_day = t.day_of_year;
      g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
     }
  }

//+------------------------------------------------------------------+
int SpreadPoints()
  {
   return (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
  }

int MinStopPoints()
  {
   int lvl = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   return lvl + 2;
  }

double Norm(double price)
  {
   double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick > 0) price = MathRound(price / tick) * tick;
   return NormalizeDouble(price, g_digits);
  }
//+------------------------------------------------------------------+
