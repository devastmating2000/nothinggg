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

---

# Versão BTCUSD – `Experts/BreakoutStraddle_BTCUSD.mq5`

A lógica é a mesma, mas afinada para Bitcoin (gráfico M1, mercado aberto 24/7):

- As distâncias estão em **dólares de preço do BTC** e não em pontos. Assim funciona da mesma forma em qualquer corretora, tenha o BTCUSD 1 ou 2 casas decimais. O EA converte-as sozinho para pontos.
- Usa um magic number diferente (`20261122`), por isso pode correr ao mesmo tempo que a versão do ouro.

| Parâmetro | Predefinição | Descrição |
|---|---|---|
| InpLots / InpRiskPercent | 0.01 / 0 | Lote fixo, ou % de risco por trade |
| InpEntryUsd | 40 $ | Distância das ordens STOP ao preço |
| InpPendingTrailUsd | 10 $ | Reajusta as pendentes quando o preço se afasta |
| InpStopLossUsd / InpTakeProfitUsd | 60 $ / 0 | SL e TP (TP 0 = sai por trailing) |
| InpBreakEvenUsd / LockUsd | 40 $ / 5 $ | Break-even |
| InpTrailStartUsd / DistUsd / StepUsd | 60 $ / 40 $ / 5 $ | Trailing stop |
| InpMaxSpreadUsd | 25 $ | Não abre ordens se o spread for maior |

Com 1 lote = 1 BTC (o mais comum), 0.01 lote perde cerca de **0,60 $** se bater no SL de 60 $.
Confirma o tamanho do contrato na tua corretora, em *Especificação do símbolo*.

**Dica:** o spread do BTC varia muito de corretora para corretora (5 a 50 $). A distância de entrada e o SL devem ficar pelo menos 2 a 3 vezes acima do spread típico. Caso contrário, o spread come o lucro.
