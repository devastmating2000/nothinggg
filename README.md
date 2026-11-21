# BreakoutStraddle – EA para MetaTrader 5

Um robô de scalping por breakout. Foi pensado para o **XAUUSD em M1**, a mesma configuração que aparece no vídeo de referência.

## Como funciona
1. Sem posição aberta, coloca um **BUY STOP** acima do preço e um **SELL STOP** abaixo, ambos com Stop Loss curto.
2. Enquanto não são acionadas, as ordens pendentes vão seguindo o preço.
3. Quando uma ordem é acionada, a outra é apagada (OCO).
4. A posição é gerida com **break-even** e **trailing stop**.
5. Quando a posição fecha, o ciclo recomeça. Funciona 24 horas por dia ("robots never sleep").

## Instalação
1. No MT5, abre **Ficheiro → Abrir pasta de dados → MQL5 → Experts**.
2. Copia `Experts/BreakoutStraddle.mq5` para essa pasta.
3. Abre o ficheiro no MetaEditor e carrega em **Compilar** (F7).
4. Arrasta o EA para um gráfico XAUUSD M1 e ativa o **Algo Trading**.

## Parâmetros principais (em pontos; no ouro com 2 casas decimais, 100 pontos = 1,00 $)
| Parâmetro | Predefinição | Descrição |
|---|---|---|
| InpLots / InpRiskPercent | 0.10 / 0 | Lote fixo, ou % de risco por trade |
| InpEntryDistance | 100 | Distância das ordens STOP ao preço |
| InpPendingTrail | 30 | Reajusta as pendentes quando o preço se afasta |
| InpStopLoss / InpTakeProfit | 150 / 0 | SL e TP (TP 0 = sai por trailing) |
| InpBreakEvenStart / Lock | 80 / 10 | Break-even |
| InpTrailStart / Distance / Step | 120 / 80 / 10 | Trailing stop |
| InpMaxSpread | 40 | Não abre ordens se o spread for maior |
| InpStartHour / InpEndHour | 0 / 24 | Horário de trading (hora do servidor) |
| InpMaxDailyLossPct | 0 | Para de abrir ordens depois de X % de perda no dia |

## ⚠️ Aviso
Esta estratégia depende muito do **spread, do slippage e da execução da corretora**. Testa sempre primeiro no **Strategy Tester** (modo "Every tick based on real ticks") e depois numa **conta demo**. Os resultados de vídeos de redes sociais não garantem lucro.
