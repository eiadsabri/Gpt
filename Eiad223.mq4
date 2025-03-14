//+------------------------------------------------------------------+
//|             EA Entry Conditions with Reinforcement &           |
//|                    Dynamic Money Management                      |
//|                                                                  |
//|  نموذج لدخول الصفقات باستخدام موفنج الشراء/البيع مع دخول معاكسة    |
//|  وتعزيزات (reinforcements) بحجم لوت مخصص وإدارة مالية ديناميكية.   |
//+------------------------------------------------------------------+
#property strict

//=================== الإدخالات العامة ===================

// حجم اللوت الأساسي
input double LotSize = 0.01;

// حجم اللوت المستخدم في الصفقات التعزيزية (reinforcement)
input double ReinforcementLot = 0.02;

// خيار استخدام إدارة مالية ديناميكية لحساب حجم اللوت (إذا كانت true يتم حساب حجم اللوت بناءً على نسبة المخاطرة)
input bool UseDynamicLot = false;
input double RiskPercent = 1.0;   // نسبة المخاطرة لكل صفقة (مثلاً 1%)
input int StopLossPips = 50;        // مسافة وقف الخسارة بالـ pips (يتم استخدامها في حساب حجم اللوت)

// خاصية الانتظار عند التشغيل الأول
input bool WaitForNewEntry = true;  // إذا كانت true، لا يفتح صفقة عند التشغيل الأول حتى يظهر تغيير في الإشارة

// إعدادات المتوسطات المتحركة للدخول
input int BuyMAPeriod = 200;
input int SellMAPeriod = 200;
input int BuyMAShift = 0;
input int SellMAShift = 0;
input int BuyMAMethod = MODE_SMA;
input int SellMAMethod = MODE_SMA;
input double MATolerancePoints = 1.0;  // هامش تقارب السعر مع الموفنج

// خيار الدخول عند إغلاق الشمعة (EnterOnClose)
input bool EnterOnCloseBuy = false;
input bool EnterOnCloseSell = false;

// فترة التبريد لمنع التكرار (بالثواني)
input int OrderCooldownSeconds = 60;

// المسافة المسموح بها بين سعر الصفقة الأساسية وسعر دخول الصفقة المعاكسة
// (مثلاً: يجب أن يكون الفرق 50 نقطة على الأقل)
input double AllowedCounterTradeDistance = 50.0;

// إعدادات التعزيز (reinforcement)
// المسافة المسموح بها لدخول أول تعزيز من سعر الصفقة الأساسية
input double FirstReinforceDistance = 50.0;  // بالـ points
// المسافة المسموح بها لباقي التعزيزات بعد الأول
input double SubsequentReinforceDistance = 30.0;

// باقي الإدخالات الأساسية (يمكن تعديلها لاحقاً)
input double MaxLotSize = 10.0;
input double MaxSpread = 20.0;

//=================== المتغيرات العامة ===================

double InitialBalance = 0.0;
double OverallCycleStart = 0.0;
double DailyStartBalance = 0.0;
datetime LastDailyUpdate = 0;

// نستخدم هذه المتغيرات لتحديد سعر الصفقة الأساسية (للشراء والبيع) حتى نستخدمها كأساس للتعزيز
double baseBuyPrice = 0.0;
double baseSellPrice = 0.0;

// لتخزين آخر وقت فتح صفقة لكل اتجاه (لمنع التكرار)
datetime lastBuyOrderTime = 0;
datetime lastSellOrderTime = 0;

// متغير للتحكم في التشغيل الأول
bool firstRun = true;

//-------------------
// دوال حساب حجم اللوت الديناميكي (إدارة مالية)
//-------------------
double CalculateLotSize()
{
   // نحسب قيمة pip باستخدام tick value و tick size
   double pipValue = MarketInfo(Symbol(), MODE_TICKVALUE) / MarketInfo(Symbol(), MODE_TICKSIZE);
   double riskMoney = AccountBalance() * RiskPercent / 100.0;
   double lot = riskMoney / (StopLossPips * Point * pipValue);
   // تقليل حجم اللوت إلى درجتين عشريتين
   return NormalizeDouble(lot, 2);
}

double GetDynamicLot(double baseLot)
{
   if(UseDynamicLot)
      return CalculateLotSize();
   else
      return baseLot;
}

//-------------------
// دوال مساعدة لحساب عدد الصفقات المفتوحة
int CountBuyOrders()
{
   int count = 0;
   for(int i=0; i<OrdersTotal(); i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         if(OrderSymbol() == Symbol() && OrderType() == OP_BUY) count++;
   }
   return count;
}

int CountSellOrders()
{
   int count = 0;
   for(int i=0; i<OrdersTotal(); i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         if(OrderSymbol() == Symbol() && OrderType() == OP_SELL) count++;
   }
   return count;
}

//-------------------
// دوال العرض على الشارت (يمكنك إبقاؤها كما هي)
void CreateInfoObject(string name, string text, int yOffset)
{
   if(ObjectFind(0, name) == -1)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, 0);
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
      DeleteInfoObject("TradeInfo_Broker");
      DeleteInfoObject("TradeInfo_Account");
      DeleteInfoObject("TradeInfo_Leverage");
      DeleteInfoObject("TradeInfo_InitialBalance");
      DeleteInfoObject("TradeInfo_CurrentBalance");
      DeleteInfoObject("TradeInfo_FreeMargin");
      DeleteInfoObject("TradeInfo_MarginUsed");
      DeleteInfoObject("TradeInfo_BuyOrders");
      DeleteInfoObject("TradeInfo_SellOrders");
      DeleteInfoObject("TradeInfo_OpenPL");
      return;
   }
   
   int lineHeight = FontSize + 4;
   int lineIndex = 0;
   CreateInfoObject("TradeInfo_Symbol", "Symbol: " + Symbol(), lineIndex * lineHeight); lineIndex++;
   CreateInfoObject("TradeInfo_DateTime", "Date/Time: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES), lineIndex * lineHeight); lineIndex++;
   CreateInfoObject("TradeInfo_Spread", "Spread: " + DoubleToString(MarketInfo(Symbol(), MODE_SPREAD),1), lineIndex * lineHeight); lineIndex++;
   // يمكن إضافة المزيد من المعلومات حسب الحاجة...
}

//-------------------
// دوال التداول الأساسية
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

//-------------------
// دالة إغلاق جميع الصفقات المفتوحة
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

//-------------------
// دوال متابعة الربح الإجمالي واليومي (موجودة في الإصدارات السابقة)
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

//-------------------
// دالة التريلنج ستوب (يمكنك إبقاؤها كما هي)
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
                  OrderModify(OrderTicket(), OrderOpenPrice(), newStop, OrderTakeProfit(), 0, clrRed);
            }
            else if(OrderType() == OP_SELL)
            {
               double newStop = Ask + TrailingStopDistance * Point;
               if(OrderStopLoss() > newStop || OrderStopLoss() == 0)
                  OrderModify(OrderTicket(), OrderOpenPrice(), newStop, OrderTakeProfit(), 0, clrRed);
            }
         }
      }
   }
}

//-------------------
// منطق دخول الصفقة باستخدام الموفنج والدخول المعاكس والتعزيز
//-------------------
void OnTick()
{
   ShowTradeInfo();
   
   // تحديث متغيرات بداية اليوم
   if(TimeDay(TimeCurrent()) != TimeDay(LastDailyUpdate))
   {
      DailyStartBalance = AccountEquity();
      LastDailyUpdate = TimeCurrent();
      // يمكنك إعادة ضبط بعض المتغيرات هنا إذا لزم الأمر
   }
   
   // حساب المتوسطات
   double currentBuyMA = iMA(Symbol(), 0, BuyMAPeriod, BuyMAShift, BuyMAMethod, PRICE_HIGH, (EnterOnCloseBuy ? 1 : 0));
   double currentSellMA = iMA(Symbol(), 0, SellMAPeriod, SellMAShift, SellMAMethod, PRICE_LOW, (EnterOnCloseSell ? 1 : 0));
   double spread = MarketInfo(Symbol(), MODE_SPREAD) * Point;
   
   // شروط الدخول
   bool buyEntryCondition = ((Bid + spread) >= currentBuyMA + (MATolerancePoints * Point));
   bool sellEntryCondition = ((Ask - spread) <= currentSellMA - (MATolerancePoints * Point));
   
   // منطق التشغيل الأول
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
   
   // بعد التشغيل الأول:
   // إذا تحقق شرط الدخول للشراء
   if(buyEntryCondition)
   {
      // إذا لا توجد صفقة شراء مفتوحة، نفتح صفقة شراء عادية
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
            // إذا توجد صفقة بيع مفتوحة، نتحقق من شرط الدخول المعاكس للتعزيز
            double sellOpenPrice = 0.0;
            for(int i=0; i<OrdersTotal(); i++)
            {
               if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
               {
                  if(OrderSymbol()==Symbol() && OrderType()==OP_SELL)
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
   
   // إذا تحقق شرط الدخول للبيع
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
            for(int i=0; i<OrdersTotal(); i++)
            {
               if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
               {
                  if(OrderSymbol()==Symbol() && OrderType()==OP_BUY)
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
   
   // هنا يمكن إضافة منطق إدارة التعزيزات (reinforcements) الإضافية إذا كان السعر يتحرك في نفس الاتجاه
   // مثال على التعزيز لصفقات الشراء:
   if(CountBuyOrders() > 0)
   {
      double requiredDistance = (/* أول تعزيز */ CountBuyOrders() == 1) ? FirstReinforceDistance : SubsequentReinforceDistance;
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
   
   // مثال على التعزيز لصفقات البيع:
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
   
   // يمكنك هنا إضافة باقي منطق الإدارة المالية مثل وقف الخسارة وجني الأرباح حسب رغبتك
   ApplyTrailingStop();
}

//-------------------
// دالة التريلنج ستوب (كما في النسخ السابقة)
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
                  OrderModify(OrderTicket(), OrderOpenPrice(), newStop, OrderTakeProfit(), 0, clrRed);
            }
            else if(OrderType() == OP_SELL)
            {
               double newStop = Ask + TrailingStopDistance * Point;
               if(OrderStopLoss() > newStop || OrderStopLoss() == 0)
                  OrderModify(OrderTicket(), OrderOpenPrice(), newStop, OrderTakeProfit(), 0, clrRed);
            }
         }
      }
   }
}

//-------------------
// دالة الهيدج (HedgeTrade)
// تُفتح صفقة بيع كـ Hedge إذا لم تكن موجودة بالفعل بالقرب من السعر الحالي
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
