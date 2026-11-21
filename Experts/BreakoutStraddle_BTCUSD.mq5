//+------------------------------------------------------------------+
//|                                     BreakoutStraddle_BTCUSD.mq5  |
//|  Scalper de breakout para MT5 (versao BTCUSD M1).                |
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

//--- Entradas (distancias em DOLARES de preco do BTC, independente dos digitos da corretora)
input group "Lote / Risco"
input double InpLots            = 0.01;   // Lote fixo (usado se RiskPercent = 0)
input double InpRiskPercent     = 0.0;    // Risco por trade em % do saldo (0 = usar lote fixo)

input group "Ordens pendentes (em USD de preco)"
input double InpEntryUsd        = 40.0;   // Distancia das ordens STOP ao preco
input double InpPendingTrailUsd = 10.0;   // Reajustar pendentes se o preco se afastar mais que isto
input double InpStopLossUsd     = 60.0;   // Stop Loss
input double InpTakeProfitUsd   = 0.0;    // Take Profit (0 = sem TP, sai por trailing)

input group "Gestao da posicao (em USD de preco)"
input double InpBreakEvenUsd    = 40.0;   // Lucro para mover SL para break-even (0 = desligado)
input double InpBreakEvenLockUsd= 5.0;    // Garantido no break-even
input double InpTrailStartUsd   = 60.0;   // Lucro para iniciar trailing (0 = desligado)
input double InpTrailDistUsd    = 40.0;   // Distancia do trailing stop
input double InpTrailStepUsd    = 5.0;    // Passo minimo para mover o SL

input group "Filtros"
input double InpMaxSpreadUsd    = 25.0;   // Spread maximo permitido (USD)
input int    InpStartHour       = 0;      // Hora de inicio (hora do servidor)
input int    InpEndHour         = 24;     // Hora de fim (hora do servidor)
input int    InpCooldownSeconds = 0;      // Espera apos fechar posicao (segundos)
input int    InpMaxDailyLossPct = 0;      // Perda diaria maxima em % (0 = desligado)

input group "Geral"
input ulong  InpMagic           = 20261122; // Magic number
input string InpComment         = "BreakoutStraddle BTC";

//--- Distancias convertidas para pontos no OnInit
double P_EntryDistance, P_PendingTrail, P_StopLoss, P_TakeProfit;
double P_BreakEvenStart, P_BreakEvenLock, P_TrailStart, P_TrailDistance, P_TrailStep, P_MaxSpread;

//--- Globais
CTrade   trade;
double   g_point;
int      g_digits;
datetime g_lastClose = 0;
double   g_dayStartBalance = 0;
int      g_day = -1;
string   g_status = "";

//+------------------------------------------------------------------+
int OnInit()
  {
   g_point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if(StringFind(_Symbol, "BTC") < 0)
      PrintFormat("Aviso: este EA foi afinado para BTCUSD, simbolo atual: %s", _Symbol);

   P_EntryDistance  = InpEntryUsd         / g_point;
   P_PendingTrail   = InpPendingTrailUsd  / g_point;
   P_StopLoss       = InpStopLossUsd      / g_point;
   P_TakeProfit     = InpTakeProfitUsd    / g_point;
   P_BreakEvenStart = InpBreakEvenUsd     / g_point;
   P_BreakEvenLock  = InpBreakEvenLockUsd / g_point;
   P_TrailStart     = InpTrailStartUsd    / g_point;
   P_TrailDistance  = InpTrailDistUsd     / g_point;
   P_TrailStep      = InpTrailStepUsd     / g_point;
   P_MaxSpread      = InpMaxSpreadUsd     / g_point;

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints((ulong)MathMax(20, 5.0 / g_point)); // ~5 USD de slippage
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetAsyncMode(false);

   if(P_EntryDistance <= 0 || P_StopLoss <= 0)
     {
      Print("EntryDistance e StopLoss tem de ser > 0");
      return INIT_PARAMETERS_INCORRECT;
     }
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Comment("");
  }

//+------------------------------------------------------------------+
void ShowStatus(string msg)
  {
   g_status = msg;
   Comment(StringFormat("BreakoutStraddle BTCUSD\n"
                        "Estado: %s\n"
                        "Spread: %.2f $ (max %.2f $)\n"
                        "Entrada: +/- %.2f $   SL: %.2f $   Lote: %.2f",
                        msg, SpreadPoints() * g_point, InpMaxSpreadUsd,
                        InpEntryUsd, InpStopLossUsd, CalcLots()));
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
      ShowStatus("POSICAO ABERTA - a gerir SL/trailing");
      return;
     }

   //--- Sem posicao
   if(!TradingAllowed())
     {
      if(buyStop  > 0) trade.OrderDelete(buyStop);
      if(sellStop > 0) trade.OrderDelete(sellStop);
      ShowStatus("PARADO - fora do horario ou limite de perda diaria");
      return;
     }

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
     {
      ShowStatus("SEM PERMISSAO - liga o botao Algo Trading");
      return;
     }

   if(SpreadPoints() > P_MaxSpread)
     {
      ShowStatus("A ESPERA - spread demasiado alto");
      return;
     }

   if(InpCooldownSeconds > 0 && TimeCurrent() - g_lastClose < InpCooldownSeconds)
     {
      ShowStatus("A ESPERA - pausa apos fecho");
      return;
     }

   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double dist = MathMax(P_EntryDistance, MinStopPoints()) * g_point;

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

   ShowStatus("ATIVO - ordens BUY STOP / SELL STOP colocadas");
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
      sl = Norm(price - P_StopLoss * g_point);
      if(P_TakeProfit > 0) tp = Norm(price + P_TakeProfit * g_point);
      if(!trade.BuyStop(lots, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, InpComment))
         PrintFormat("BuyStop falhou: %d %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
     }
   else
     {
      sl = Norm(price + P_StopLoss * g_point);
      if(P_TakeProfit > 0) tp = Norm(price - P_TakeProfit * g_point);
      if(!trade.SellStop(lots, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, InpComment))
         PrintFormat("SellStop falhou: %d %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
     }
  }

//+------------------------------------------------------------------+
//| Mantem a ordem pendente a distancia fixa do preco                 |
//+------------------------------------------------------------------+
void TrailPending(ulong ticket, double target, bool isBuy)
  {
   if(P_PendingTrail <= 0 || !OrderSelect(ticket))
      return;

   double cur = OrderGetDouble(ORDER_PRICE_OPEN);
   double gap = MathAbs(cur - target) / g_point;
   if(gap < P_PendingTrail)
      return;

   double sl, tp = 0;
   if(isBuy)
     {
      sl = Norm(target - P_StopLoss * g_point);
      if(P_TakeProfit > 0) tp = Norm(target + P_TakeProfit * g_point);
     }
   else
     {
      sl = Norm(target + P_StopLoss * g_point);
      if(P_TakeProfit > 0) tp = Norm(target - P_TakeProfit * g_point);
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

      if(P_BreakEvenStart > 0 && profitPts >= P_BreakEvenStart)
        {
         double be = Norm(open + P_BreakEvenLock * g_point);
         if(be > newSL) newSL = be;
        }
      if(P_TrailStart > 0 && profitPts >= P_TrailStart)
        {
         double tr = Norm(bid - P_TrailDistance * g_point);
         if(tr > newSL) newSL = tr;
        }
      if(newSL > sl + P_TrailStep * g_point && newSL < bid - minSt)
         trade.PositionModify(ticket, newSL, tp);
     }
   else
     {
      double profitPts = (open - ask) / g_point;

      if(P_BreakEvenStart > 0 && profitPts >= P_BreakEvenStart)
        {
         double be = Norm(open - P_BreakEvenLock * g_point);
         if(sl == 0 || be < newSL) newSL = be;
        }
      if(P_TrailStart > 0 && profitPts >= P_TrailStart)
        {
         double tr = Norm(ask + P_TrailDistance * g_point);
         if(newSL == 0 || tr < newSL) newSL = tr;
        }
      if((sl == 0 || newSL < sl - P_TrailStep * g_point) && newSL > ask + minSt)
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
         double lossPerLot  = (P_StopLoss * g_point / tickSize) * tickVal;
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
