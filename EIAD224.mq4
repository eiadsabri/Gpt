//+------------------------------------------------------------------+
//|      EA Entry Conditions with Reinforcement & Dynamic            |
//|              Money Management Example                          |
//|                                                                  |
//| يستخدم هذا الإكسبرت موفنج الشراء/البيع للدخول في صفقة أساسية،    |
//| ثم إذا ظهر شرط دخول معاكسة يتم فتح صفقة معاكسة، وتدخل أوامر        |
//| تعزيز (reinforcements) بحجم لوت مخصص وإدارة مالية ديناميكية.       |
//+------------------------------------------------------------------+
#property strict

//-----------------------------------------
// الإدخالات (Input Parameters)
//-----------------------------------------
input double LotSize              = 0.01;          // حجم اللوت الأساسي
input double ReinforcementLot     = 0.02;          // حجم اللوت المستخدم في صفقات التعزيز

// إعدادات إدارة المال الديناميكية
input bool   UseDynamicLot        = false;         // إذا كانت true يتم حساب حجم اللوت بناءً على نسبة المخاطرة
input double RiskPercent          = 1.0;           // نسبة المخاطرة لكل صفقة (مثلاً 1%)
input int    StopLossPips         = 50;            // مسافة وقف الخسارة بالـ pips

// خاصية الانتظار عند التشغيل الأول (عدم دخول صفقة مباشرة عند تشغيل الإكسبرت)
input bool   WaitForNewEntry      = true;          
input int    OrderCooldownSeconds = 60;            // فترة التبريد بين دخول الصفقات (بالثواني)

// إعدادات المتوسطات المتحركة للدخول
input int    BuyMAPeriod          = 200;
input int    SellMAPeriod         = 200;
input int    BuyMAShift           = 0;
input int    SellMAShift          = 0;
input int    BuyMAMethod          = MODE_SMA;
input int    SellMAMethod         = MODE_SMA;
input double MATolerancePoints    = 1.0;           // هامش تقارب السعر مع المتوسط

// خيار الدخول عند إغلاق الشمعة (EnterOnClose)
input bool   EnterOnCloseBuy      = false;
input bool   EnterOnCloseSell     = false;

// المسافة بين سعر الصفقة الأساسية وسعر دخول الصفقة المعاكسة
input double AllowedCounterTradeDistance = 50.0;   // بالـ points

// إعدادات التعزيز (reinforcement)
// المسافة لدخول أول تعزيز من سعر الصفقة الأساسية
input double FirstReinforceDistance = 50.0;          // بالـ points
// المسافة لباقي التعزيزات بعد الأول
input double SubsequentReinforceDistance = 30.0;       // بالـ points

// إعدادات إضافية
input double MaxLotSize           = 10.0;
input double MaxSpread            = 20.0;

// إعدادات الأهداف الربحية
input bool   EnableOverallProfitTarget = true;
input double OverallProfitTarget       = 30.0;
input bool   EnableProfitStop          = true;
input double ProfitStopTarget          = 10.0;

// إعدادات فترة التداول
input bool   UseTradingTime       = false;
input string TradingStartTime     = "09:00";
input string TradingEndTime       = "17:00";

// إعدادات التريلنج ستوب
input bool   EnableTrailingStop   = false;
input double TrailingStopDistance = 15.0;

// إعدادات المضاعفات وعكس الصفقات
input bool   EnableMultiplying    = false;
input bool   MultiplyByAddition   = false;
input double MultiplyingFactor    = 2.0;
input bool   EnableReverseTrade   = true;
input bool   CloseOppositeTrades  = true;

// إعدادات الهيدج (Hedge)
input bool   EnableHedge          = false;
input double HedgeDistance        = 5.0;
input bool   HedgeWithMultiplication = false;

// إعدادات العرض على الشارت
input bool   ShowInfo             = true;
input int    FontSize             = 12;
input int    Corner               = 0;           // 0: أعلى يسار، 1: أعلى يمين، 2: أسفل يسار، 3: أسفل يمين
input color  InfoColor            = clrWhite;

//-----------------------------------------
// المتغيرات العامة (Global Variables)
//-----------------------------------------
double InitialBalance       = 0.0;
double OverallCycleStart    = 0.0;
double DailyStartBalance    = 0.0;
datetime LastDailyUpdate    = 0;

// لتخزين سعر الصفقة الأساسية كأساس للتعزيز
double baseBuyPrice         = 0.0;
double baseSellPrice        = 0.0;

// لتسجيل أوقات آخر دخول لكل اتجاه (لمنع التكرار)
datetime lastBuyOrderTime   = 0;
datetime lastSellOrderTime  = 0;

// متغير للتحكم في التشغيل الأول
bool firstRun               = true;
bool tradingStopped         = false;

//-----------------------------------------
// دوال الإدارة المالية (Money Management)
//-----------------------------------------
double CalculateLotSize()
{
   // نحسب قيمة pip باستخدام tick value و tick size
   double pipValue = MarketInfo(Symbol(), MODE_TICKVALUE) / MarketInfo(Symbol(), MODE_TICKSIZE);
   double riskMoney = AccountBalance() * RiskPercent / 100.0;
   double lot = riskMoney / (StopLossPips * Point * pipValue);
   return NormalizeDouble(lot, 2);
}

double GetDynamicLot(double baseLot)
{
   return UseDynamicLot ? CalculateLotSize() : baseLot;
}

//-----------------------------------------
// دوال حساب عدد الصفقات المفتوحة
//-----------------------------------------
int CountBuyOrders()
{
   int count = 0;
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         if(OrderSymbol() == Symbol() && OrderType() == OP_BUY)
            count++;
   }
   return count;
}

int CountSellOrders()
{
   int count = 0;
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         if(OrderSymbol() == Symbol() && OrderType() == OP_SELL)
            count++;
   }
   return count;
}

//-----------------------------------------
// دوال العرض على الشارت (Display Info)
//-----------------------------------------
void CreateInfoObject(string name, string text, int yOffset)
{
   if(ObjectFind(0, name) == -1)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, Corner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 10 + yOffset);
   ObjectSetText(name, text, FontSize, "Arial", InfoColor);
}

void DeleteInfoObject(string name)
{
   if(ObjectFind(0, name) != -1)
      ObjectDelete(0, name);
}

void ShowTradeInfo()
{
   if(!ShowInfo)
   {
      DeleteInfoObject("TradeInfo_Symbol");
      DeleteInfoObject("TradeInfo_DateTime");
      DeleteInfoObject("TradeInfo_Spread");
      return;
   }
   int lineHeight = FontSize + 4;
   int lineIndex = 0;
   CreateInfoObject("TradeInfo_Symbol", "Symbol: " + Symbol(), lineIndex * lineHeight); lineIndex++;
   CreateInfoObject("TradeInfo_DateTime", "Date/Time: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES), lineIndex * lineHeight); lineIndex++;
   CreateInfoObject("TradeInfo_Spread", "Spread: " + DoubleToString(MarketInfo(Symbol(), MODE_SPREAD), 1), lineIndex * lineHeight); lineIndex++;
}

//-----------------------------------------
// دوال التداول الأساسية
//-----------------------------------------
bool CanOpenTrade()
{
   double currentSpread = MarketInfo(Symbol(), MODE_SPREAD);
   if(LotSize > MaxLotSize)
   {
      Print("LotSize (", LotSize, ") exceeds MaxLotSize (", MaxLotSize, ")");
      return false;
   }
   if(currentSpread > MaxSpread)
   {
      Print("Spread (", currentSpread, ") exceeds MaxSpread (", MaxSpread, ")");
      return false;
   }
   return true;
}

bool CheckTradingTime()
{
   if(!UseTradingTime)
      return true;
   datetime currentTime = TimeCurrent();
   string currentHM = StringSubstr(TimeToString(currentTime, TIME_SECONDS), 11, 5);
   int currentMinutes = ((int)StringToInteger(StringSubstr(currentHM, 0, 2)) * 60) +
                        (int)StringToInteger(StringSubstr(currentHM, 3, 2));
   int startMinutes = ((int)StringToInteger(StringSubstr(TradingStartTime, 0, 2)) * 60) +
                      (int)StringToInteger(StringSubstr(TradingStartTime, 3, 2));
   int endMinutes = ((int)StringToInteger(StringSubstr(TradingEndTime, 0, 2)) * 60) +
                    (int)StringToInteger(StringSubstr(TradingEndTime, 3, 2));
   return (currentMinutes >= startMinutes && currentMinutes <= endMinutes);
}

void CloseAllPositions()
{
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderSymbol() == Symbol())
         {
            if(OrderType() == OP_BUY)
            {
               if(!OrderClose(OrderTicket(), OrderLots(), Bid, 3, clrYellow))
                  Print("Failed to close BUY order ", OrderTicket(), " Error: ", GetLastError());
            }
            else if(OrderType() == OP_SELL)
            {
               if(!OrderClose(OrderTicket(), OrderLots(), Ask, 3, clrYellow))
                  Print("Failed to close SELL order ", OrderTicket(), " Error: ", GetLastError());
            }
         }
      }
   }
}

//-----------------------------------------
// دوال متابعة الربح
//-----------------------------------------
bool CheckOverallProfitTarget()
{
   double overallProfit = AccountEquity() - OverallCycleStart;
   return (EnableOverallProfitTarget && overallProfit >= OverallProfitTarget);
}

bool CheckDailyProfitTarget()
{
   double dailyProfit = AccountEquity() - DailyStartBalance;
   return (EnableProfitStop && dailyProfit >= ProfitStopTarget);
}

//-----------------------------------------
// دالة التريلنج ستوب (تعريف واحد فقط)
//-----------------------------------------
void ApplyTrailingStop()
{
   if(!EnableTrailingStop) return;
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderSymbol() == Symbol())
         {
            if(OrderType() == OP_BUY)
            {
               double newStop = Bid - TrailingStopDistance * Point;
               if(OrderStopLoss() < newStop)
                  if(!OrderModify(OrderTicket(), OrderOpenPrice(), newStop, OrderTakeProfit(), 0, clrRed))
                     Print("Trailing Stop Modify (Buy) failed. Error: ", GetLastError());
            }
            else if(OrderType() == OP_SELL)
            {
               double newStop = Ask + TrailingStopDistance * Point;
               if(OrderStopLoss() > newStop || OrderStopLoss() == 0)
                  if(!OrderModify(OrderTicket(), OrderOpenPrice(), newStop, OrderTakeProfit(), 0, clrRed))
                     Print("Trailing Stop Modify (Sell) failed. Error: ", GetLastError());
            }
         }
      }
   }
}

//-----------------------------------------
// دالة الهيدج (HedgeTrade) (تعريف واحد فقط)
//-----------------------------------------
void HedgeTrade()
{
   if(!EnableHedge) return;
   double price = Bid;
   bool hedgeExists = false;
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderSymbol() == Symbol() && OrderType() == OP_SELL &&
            MathAbs(OrderOpenPrice() - price) <= HedgeDistance * Point)
         {
            hedgeExists = true;
            break;
         }
      }
   }
   if(!hedgeExists)
   {
      int hedgeTicket = OrderSend(Symbol(), OP_SELL, GetDynamicLot(LotSize), Bid, 3, 0, 0, "Hedge Trade", 0, 0, clrBlue);
      if(hedgeTicket < 0)
         Print("Error opening Hedge SELL: ", GetLastError());
   }
}

//-----------------------------------------
// OnInit and OnDeinit
//-----------------------------------------
int OnInit()
{
   InitialBalance = AccountBalance();
   OverallCycleStart = AccountEquity();
   DailyStartBalance = AccountEquity();
   LastDailyUpdate = TimeCurrent();
   firstRun = true;
   lastBuyOrderTime = 0;
   lastSellOrderTime = 0;
   baseBuyPrice = 0.0;
   baseSellPrice = 0.0;
   tradingStopped = false;
   Print("EA Initialized.");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   DeleteInfoObject("TradeInfo_Symbol");
   DeleteInfoObject("TradeInfo_DateTime");
   DeleteInfoObject("TradeInfo_Spread");
   Print("EA Deinitialized.");
}

//-----------------------------------------
// OnTick: منطق الدخول والتعزيز
//-----------------------------------------
void OnTick()
{
   ShowTradeInfo();
   
   // تحديث بداية اليوم عند تغيير اليوم
   if(TimeDay(TimeCurrent()) != TimeDay(LastDailyUpdate))
   {
      DailyStartBalance = AccountEquity();
      LastDailyUpdate = TimeCurrent();
   }
   
   // حساب المتوسطات
   double currentBuyMA = iMA(Symbol(), 0, BuyMAPeriod, BuyMAShift, BuyMAMethod, PRICE_HIGH, (EnterOnCloseBuy ? 1 : 0));
   double currentSellMA = iMA(Symbol(), 0, SellMAPeriod, SellMAShift, SellMAMethod, PRICE_LOW, (EnterOnCloseSell ? 1 : 0));
   double spread = MarketInfo(Symbol(), MODE_SPREAD) * Point;
   
   // شروط الدخول:
   bool buyEntryCondition = ((Bid + spread) >= currentBuyMA + (MATolerancePoints * Point));
   bool sellEntryCondition = ((Ask - spread) <= currentSellMA - (MATolerancePoints * Point));
   
   // منطق التشغيل الأول:
   if(firstRun && OrdersTotal() == 0)
   {
      if(buyEntryCondition)
      {
         Print("First run: Buy condition met; waiting for sell signal to open the first trade.");
         return;
      }
      if(sellEntryCondition)
      {
         if(TimeCurrent() - lastSellOrderTime >= OrderCooldownSeconds && CanOpenTrade())
         {
            int ticket = OrderSend(Symbol(), OP_SELL, GetDynamicLot(LotSize), Bid, 3, 0, 0, "First Trade Sell", 0, 0, clrRed);
            if(ticket < 0)
               Print("Error opening first SELL: ", GetLastError());
            else
            {
               Print("First SELL trade opened. Ticket: ", ticket);
               baseSellPrice = Bid; // حفظ سعر الصفقة الأساسية للبيع
               lastSellOrderTime = TimeCurrent();
            }
         }
         firstRun = false;
         return;
      }
      return;
   }
   
   // الدخول الاعتيادي:
   // شرط دخول صفقة شراء
   if(buyEntryCondition)
   {
      if(CountBuyOrders() == 0)
      {
         if(CountSellOrders() == 0)
         {
            if(TimeCurrent() - lastBuyOrderTime >= OrderCooldownSeconds && CanOpenTrade())
            {
               int ticket = OrderSend(Symbol(), OP_BUY, GetDynamicLot(LotSize), Ask, 3, 0, 0, "Buy Order", 0, 0, clrGreen);
               if(ticket < 0)
                  Print("Error opening BUY: ", GetLastError());
               else
               {
                  Print("BUY trade opened. Ticket: ", ticket);
                  baseBuyPrice = Ask; // حفظ سعر الصفقة الأساسية للشراء
                  lastBuyOrderTime = TimeCurrent();
               }
            }
         }
         else
         {
            // إذا توجد صفقة بيع مفتوحة، نتحقق من شرط الدخول المعاكس (Counter Trade)
            double sellOpenPrice = 0.0;
            for(int i = 0; i < OrdersTotal(); i++)
            {
               if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
               {
                  if(OrderSymbol() == Symbol() && OrderType() == OP_SELL)
                  {
                     sellOpenPrice = OrderOpenPrice();
                     break;
                  }
               }
            }
            if(sellOpenPrice > 0 && (Bid >= sellOpenPrice + AllowedCounterTradeDistance * Point))
            {
               if(TimeCurrent() - lastBuyOrderTime >= OrderCooldownSeconds && CanOpenTrade())
               {
                  int ticket = OrderSend(Symbol(), OP_BUY, GetDynamicLot(ReinforcementLot), Ask, 3, 0, 0, "Counter Buy", 0, 0, clrGreen);
                  if(ticket < 0)
                     Print("Error opening Counter BUY: ", GetLastError());
                  else
                  {
                     Print("Counter BUY trade opened. Ticket: ", ticket);
                     lastBuyOrderTime = TimeCurrent();
                  }
               }
            }
         }
      }
   }
   
   // شرط دخول صفقة بيع
   if(sellEntryCondition)
   {
      if(CountSellOrders() == 0)
      {
         if(CountBuyOrders() == 0)
         {
            if(TimeCurrent() - lastSellOrderTime >= OrderCooldownSeconds && CanOpenTrade())
            {
               int ticket = OrderSend(Symbol(), OP_SELL, GetDynamicLot(LotSize), Bid, 3, 0, 0, "Sell Order", 0, 0, clrRed);
               if(ticket < 0)
                  Print("Error opening SELL: ", GetLastError());
               else
               {
                  Print("SELL trade opened. Ticket: ", ticket);
                  baseSellPrice = Bid; // حفظ سعر الصفقة الأساسية للبيع
                  lastSellOrderTime = TimeCurrent();
               }
            }
         }
         else
         {
            double buyOpenPrice = 0.0;
            for(int i = 0; i < OrdersTotal(); i++)
            {
               if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
               {
                  if(OrderSymbol() == Symbol() && OrderType() == OP_BUY)
                  {
                     buyOpenPrice = OrderOpenPrice();
                     break;
                  }
               }
            }
            if(buyOpenPrice > 0 && (Ask <= buyOpenPrice - AllowedCounterTradeDistance * Point))
            {
               if(TimeCurrent() - lastSellOrderTime >= OrderCooldownSeconds && CanOpenTrade())
               {
                  int ticket = OrderSend(Symbol(), OP_SELL, GetDynamicLot(ReinforcementLot), Bid, 3, 0, 0, "Counter Sell", 0, 0, clrRed);
                  if(ticket < 0)
                     Print("Error opening Counter SELL: ", GetLastError());
                  else
                  {
                     Print("Counter SELL trade opened. Ticket: ", ticket);
                     lastSellOrderTime = TimeCurrent();
                  }
               }
            }
         }
      }
   }
   
   // منطق التعزيزات:
   // تعزيز صفقات الشراء
   if(CountBuyOrders() > 0)
   {
      double requiredDistance = (CountBuyOrders() == 1) ? FirstReinforceDistance : SubsequentReinforceDistance;
      if((Bid - baseBuyPrice) >= requiredDistance * Point)
      {
         if(TimeCurrent() - lastBuyOrderTime >= OrderCooldownSeconds && CanOpenTrade())
         {
            int ticket = OrderSend(Symbol(), OP_BUY, GetDynamicLot(ReinforcementLot), Ask, 3, 0, 0, "Reinforcement Buy", 0, 0, clrGreen);
            if(ticket < 0)
               Print("Error opening Reinforcement BUY: ", GetLastError());
            else
            {
               Print("Reinforcement BUY trade opened. Ticket: ", ticket);
               lastBuyOrderTime = TimeCurrent();
               baseBuyPrice = Ask; // تحديث السعر الأساسي لتعزيزات لاحقة
            }
         }
      }
   }
   
   // تعزيز صفقات البيع
   if(CountSellOrders() > 0)
   {
      double requiredDistance = (CountSellOrders() == 1) ? FirstReinforceDistance : SubsequentReinforceDistance;
      if((baseSellPrice - Ask) >= requiredDistance * Point)
      {
         if(TimeCurrent() - lastSellOrderTime >= OrderCooldownSeconds && CanOpenTrade())
         {
            int ticket = OrderSend(Symbol(), OP_SELL, GetDynamicLot(ReinforcementLot), Bid, 3, 0, 0, "Reinforcement Sell", 0, 0, clrRed);
            if(ticket < 0)
               Print("Error opening Reinforcement SELL: ", GetLastError());
            else
            {
               Print("Reinforcement SELL trade opened. Ticket: ", ticket);
               lastSellOrderTime = TimeCurrent();
               baseSellPrice = Bid;
            }
         }
      }
   }
   
   // تطبيق التريلنج ستوب والهيدج
   ApplyTrailingStop();
   HedgeTrade();
}

//-----------------------------------------

//-----------------------------------------

