import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

const ink = Color(0xFF15120F);
const panel = Color(0xFF29231E);
const gold = Color(0xFFD8B071);
const cream = Color(0xFFF0E2C9);
const muted = Color(0xFFB7A18A);
const borderGold = Color(0xFF82633F);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final app = AppState();
  await app.init();
  runApp(AzkarApp(state: app));
}

class Zikr {
  final String id, text;
  final int repeat;
  const Zikr(this.id, this.text, this.repeat);
  factory Zikr.fromJson(Map<String,dynamic> j) => Zikr(
    j['id'].toString(), j['text'].toString(), math.max(1, (j['repeat'] as num?)?.toInt() ?? 1));
}
class AzkarCategory {
  final String id, title, symbol;
  final List<Zikr> items;
  const AzkarCategory(this.id,this.title,this.symbol,this.items);
  factory AzkarCategory.fromJson(Map<String,dynamic> j) => AzkarCategory(
    j['id'].toString(), j['title'].toString(), (j['symbol'] ?? '✦').toString(),
    (j['items'] as List).map((e)=>Zikr.fromJson(e as Map<String,dynamic>)).toList());
}

class AlarmService {
  final plugin = FlutterLocalNotificationsPlugin();
  Future<void> init(void Function(String?) onTap) async {
    tzdata.initializeTimeZones();
    try { tz.setLocalLocation(tz.getLocation(await FlutterTimezone.getLocalTimezone())); } catch (_) {}
    await plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (response) => onTap(response.payload));
    final launch = await plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      onTap(launch?.notificationResponse?.payload);
    }
  }
  Future<bool> permissions() async {
    final android = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final notices = await android?.requestNotificationsPermission() ?? true;
    return notices;
  }
  Future<void> cancelGroup(int base) async {
    for (var i=0;i<7;i++) {await plugin.cancel(base+i);}
  }
  Future<void> scheduleWeek({required int base, required int hour,required int minute,
      required Set<int> days, required bool waking}) async {
    await cancelGroup(base);
    final now = tz.TZDateTime.now(tz.local);
    for (var weekday=1;weekday<=7;weekday++) {
      if (!days.contains(weekday)) continue;
      var t = tz.TZDateTime(tz.local,now.year,now.month,now.day,hour,minute);
      while (t.weekday != weekday || !t.isAfter(now)) {
        t=t.add(const Duration(days:1));
      }
      await plugin.zonedSchedule(base+weekday-1,
        waking?'حان موعد الاستيقاظ':'حان موعد النوم',
        waking?'استيقظت • غفوة — افتح التذكير لاختيار ما يناسبك':'الاستعداد للنوم • تذكيري لاحقًا',
        t,
        NotificationDetails(android: AndroidNotificationDetails(
          waking?'azkar_alarm':'azkar_sleep',waking?'منبّه الاستيقاظ':'تذكير النوم',
          channelDescription: waking?'موعد الاستيقاظ':'تذكير هادئ للنوم',
          importance: waking?Importance.max:Importance.high,
          priority: waking?Priority.max:Priority.high,
          category: waking?AndroidNotificationCategory.alarm:AndroidNotificationCategory.reminder,
          playSound:true, enableVibration:waking)),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        payload:waking?'wake':'sleep');
    }
  }
  Future<void> snooze(bool waking) async {
    final now = tz.TZDateTime.now(tz.local);
    await plugin.zonedSchedule(waking?101:201,
      waking?'حان موعد الاستيقاظ':'حان موعد النوم',
      waking?'اضغط لعرض أذكار الاستيقاظ':'اضغط لعرض أذكار النوم',
      now.add(Duration(minutes:waking?5:15)),
      NotificationDetails(android:AndroidNotificationDetails(
        waking?'azkar_alarm':'azkar_sleep', waking?'منبّه الاستيقاظ':'تذكير النوم',
        importance:Importance.max,priority:Priority.high)),
      androidScheduleMode:AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:UILocalNotificationDateInterpretation.absoluteTime,
      payload:waking?'wake':'sleep');
  }
}

class AppState extends ChangeNotifier {
  late SharedPreferences prefs;
  final alarms=AlarmService();
  final tts=FlutterTts();
  final Map<String,int> counts={};
  final Set<String> favorites={};
  List<AzkarCategory> categories=[];
  String? pendingNotification;
  bool speaking=false;
  bool wakeEnabled=false, sleepEnabled=false;
  TimeOfDay wakeTime=const TimeOfDay(hour:6,minute:30);
  TimeOfDay sleepTime=const TimeOfDay(hour:22,minute:30);
  Set<int> wakeDays={1,2,3,4,5,6,7}, sleepDays={1,2,3,4,5,6,7};
  double fontSize=25;
  Future<void> init() async {
    prefs=await SharedPreferences.getInstance();
    try { final d=jsonDecode(prefs.getString('counts_v1')??'{}') as Map<String,dynamic>;
      for (final e in d.entries) {counts[e.key]=(e.value as num).toInt();} } catch (_) {}
    favorites.addAll(prefs.getStringList('favorites_v1')??[]);
    fontSize=prefs.getDouble('size_v1')??25;
    wakeEnabled=prefs.getBool('wake_enabled')??false;
    sleepEnabled=prefs.getBool('sleep_enabled')??false;
    wakeTime=_readTime('wake_time',const TimeOfDay(hour:6,minute:30));
    sleepTime=_readTime('sleep_time',const TimeOfDay(hour:22,minute:30));
    wakeDays=(prefs.getStringList('wake_days')??['1','2','3','4','5','6','7']).map(int.parse).toSet();
    sleepDays=(prefs.getStringList('sleep_days')??['1','2','3','4','5','6','7']).map(int.parse).toSet();
    final raw=await rootBundle.loadString('assets/data/azkar.json');
    categories=(jsonDecode(raw) as List).map((e)=>AzkarCategory.fromJson(e as Map<String,dynamic>)).toList();
    await alarms.init((payload){pendingNotification=payload;notifyListeners();});
    await tts.setLanguage('ar-SA');
    await tts.setSpeechRate(0.42);
    await tts.setPitch(1.0);
    tts.setCompletionHandler(() {speaking=false;notifyListeners();});
    tts.setCancelHandler(() {speaking=false;notifyListeners();});
    tts.setErrorHandler((_) {speaking=false;notifyListeners();});
  }
  TimeOfDay _readTime(String key,TimeOfDay fallback) {
    final s=prefs.getString(key)?.split(':');
    if(s==null||s.length!=2)return fallback;
    return TimeOfDay(hour:int.tryParse(s[0])??fallback.hour,minute:int.tryParse(s[1])??fallback.minute);
  }
  AzkarCategory? category(String id){
    for(final c in categories){if(c.id==id)return c;}
    return null;
  }
  int count(Zikr z)=>math.min(z.repeat,counts[z.id]??0);
  void increment(Zikr z){if(count(z)>=z.repeat)return;counts[z.id]=count(z)+1;
    prefs.setString('counts_v1',jsonEncode(counts));HapticFeedback.selectionClick();notifyListeners();}
  void reset(Zikr z){counts.remove(z.id);prefs.setString('counts_v1',jsonEncode(counts));notifyListeners();}
  void resetCategory(AzkarCategory c){for(final z in c.items){counts.remove(z.id);}prefs.setString('counts_v1',jsonEncode(counts));notifyListeners();}
  void favorite(Zikr z){if(!favorites.add(z.id)){favorites.remove(z.id);}
    prefs.setStringList('favorites_v1',favorites.toList());notifyListeners();}
  void changeSize(double x){fontSize=x;prefs.setDouble('size_v1',x);notifyListeners();}
  Future<void> readText(String text) async {
    await tts.stop(); speaking=true;notifyListeners();
    try {await tts.setLanguage('ar-SA');await tts.speak(text);}catch(_){speaking=false;notifyListeners();}
  }
  Future<void> stopSpeech() async {await tts.stop();speaking=false;notifyListeners();}
  void clearPending(){pendingNotification=null;notifyListeners();}
  Future<void> changeSchedule({required bool waking,required bool enabled,required TimeOfDay time,required Set<int> days}) async {
    if(waking){wakeEnabled=enabled;wakeTime=time;wakeDays=days;
      await prefs.setBool('wake_enabled',enabled);await prefs.setString('wake_time','${time.hour}:${time.minute}');
      await prefs.setStringList('wake_days',days.map((e)=>'$e').toList());
    } else {sleepEnabled=enabled;sleepTime=time;sleepDays=days;
      await prefs.setBool('sleep_enabled',enabled);await prefs.setString('sleep_time','${time.hour}:${time.minute}');
      await prefs.setStringList('sleep_days',days.map((e)=>'$e').toList());}
    if(enabled){await alarms.permissions();await alarms.scheduleWeek(base:waking?10:30,hour:time.hour,minute:time.minute,days:days,waking:waking);}
    else{await alarms.cancelGroup(waking?10:30);}
    notifyListeners();
  }
}

class AzkarApp extends StatefulWidget {
  final AppState state;
  const AzkarApp({super.key,required this.state});
  @override State<AzkarApp> createState()=>_AzkarAppState();
}
class _AzkarAppState extends State<AzkarApp>{
  final navigatorKey=GlobalKey<NavigatorState>();
  String? handled;
  @override void initState(){super.initState();widget.state.addListener(_checkNotification);WidgetsBinding.instance.addPostFrameCallback((_)=>_checkNotification());}
  @override void dispose(){widget.state.removeListener(_checkNotification);super.dispose();}
  void _checkNotification(){
    final p=widget.state.pendingNotification;
    if(p==null||p==handled)return;
    handled=p;
    WidgetsBinding.instance.addPostFrameCallback((_){
      if(!mounted)return;
      final ctx=navigatorKey.currentContext;
      if(ctx==null)return;
      widget.state.clearPending();
      showDialog<void>(context:ctx,builder:(dialog)=>AlertDialog(
        backgroundColor:panel,
        title:Text(p=='wake'?'حان موعد الاستيقاظ':'حان موعد النوم'),
        content:Text(p=='wake'?'هل استيقظت؟':'هل ترغب في الاستعداد للنوم والاستماع إلى أذكار النوم؟'),
        actions:[
          TextButton(onPressed:() async{Navigator.pop(dialog);await widget.state.alarms.snooze(p=='wake');},
            child:Text(p=='wake'?'غفوة':'تذكيري لاحقًا')),
          FilledButton(onPressed:(){Navigator.pop(dialog);final c=widget.state.category(p=='wake'?'waking':'sleep');
            if(c!=null){navigatorKey.currentState?.push(MaterialPageRoute(builder:(_)=>CategoryScreen(c:c,state:widget.state,autoSpeak:true)));}},
            child:Text(p=='wake'?'استيقظت':'الاستعداد للنوم')),
        ]));
    });
  }
  @override Widget build(BuildContext context)=>MaterialApp(
    navigatorKey:navigatorKey,debugShowCheckedModeBanner:false,title:'أذكاري',locale:const Locale('ar'),
    theme:ThemeData(useMaterial3:true,brightness:Brightness.dark,scaffoldBackgroundColor:ink,
      colorScheme:const ColorScheme.dark(primary:gold,surface:panel,onSurface:cream),
      appBarTheme:const AppBarTheme(backgroundColor:ink,foregroundColor:gold,centerTitle:true),
      textTheme:const TextTheme(bodyMedium:TextStyle(color:cream))),
    home:HomeScreen(state:widget.state));
}

class OrnamentPainter extends CustomPainter {
  @override void paint(Canvas canvas,Size size){
    final paint=Paint()..color=gold.withOpacity(.075)..style=PaintingStyle.stroke..strokeWidth=1;
    for(double y=0;y<size.height+55;y+=58){for(double x=0;x<size.width+55;x+=58){
      final dx=x+((y/58).round().isOdd?29:0);
      final r=Rect.fromCircle(center:Offset(dx,y),radius:28);
      canvas.drawCircle(r.center,28,paint);
      final path=Path();for(var a=0;a<8;a++){
        final theta=math.pi*a/4;
        final pt=Offset(dx+26*math.cos(theta),y+26*math.sin(theta));
        if(a==0){path.moveTo(pt.dx,pt.dy);}else{path.lineTo(pt.dx,pt.dy);}
      }path.close();canvas.drawPath(path,paint);
    }}
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate)=>false;
}
class DecorativeBackground extends StatelessWidget{
  final Widget child; const DecorativeBackground({super.key,required this.child});
  @override Widget build(BuildContext context)=>Stack(children:[
    Positioned.fill(child:CustomPaint(painter:OrnamentPainter())),
    Positioned.fill(child:DecoratedBox(decoration:BoxDecoration(gradient:LinearGradient(
      begin:Alignment.topCenter,end:Alignment.bottomCenter,
      colors:[ink.withOpacity(.10),ink.withOpacity(.55),ink.withOpacity(.15)])))),
    child,
  ]);
}
class ArchCard extends StatelessWidget{
  final AzkarCategory category;final VoidCallback onTap;
  const ArchCard({super.key,required this.category,required this.onTap});
  @override Widget build(BuildContext context)=>InkWell(onTap:onTap,borderRadius:BorderRadius.circular(12),child:
    Container(decoration:BoxDecoration(color:panel.withOpacity(.91),border:Border.all(color:borderGold),
      borderRadius:const BorderRadius.vertical(top:Radius.elliptical(65,70),bottom:Radius.circular(10))),
      padding:const EdgeInsets.fromLTRB(7,17,7,10),
      child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
        Text(category.symbol,style:const TextStyle(fontSize:29)),const SizedBox(height:6),
        Text(category.title,textAlign:TextAlign.center,maxLines:2,
          style:const TextStyle(color:cream,fontSize:14,fontWeight:FontWeight.w700,height:1.35)),
      ])));
}
class HomeScreen extends StatefulWidget{
  final AppState state; const HomeScreen({super.key,required this.state});
  @override State<HomeScreen> createState()=>_HomeScreenState();
}
class _HomeScreenState extends State<HomeScreen>{
  bool navOpen=false,searchOpen=false,favesOnly=false;
  String query='';
  @override Widget build(BuildContext context){
    final state=widget.state;
    final cats=state.categories.where((c)=>c.items.isNotEmpty &&
      (!favesOnly||c.items.any((z)=>state.favorites.contains(z.id))) &&
      (c.title.contains(query)||c.items.any((z)=>z.text.contains(query)))).toList();
    return Directionality(textDirection:TextDirection.rtl,child:Scaffold(
      body:SafeArea(child:DecorativeBackground(child:Column(children:[
        Padding(padding:const EdgeInsets.symmetric(horizontal:14,vertical:8),child:Row(children:[
          IconButton(tooltip:'بحث',icon:const Icon(Icons.search,color:gold),onPressed:()=>setState(()=>searchOpen=!searchOpen)),
          const Text('بحث',style:TextStyle(fontSize:12,color:gold)),
          const Spacer(),
          IconButton(tooltip:'إعدادات التذكير',icon:const Icon(Icons.alarm,color:gold),onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>ScheduleScreen(state:state)))),
        ])),
        if(searchOpen)Padding(padding:const EdgeInsets.symmetric(horizontal:16),child:TextField(
          autofocus:true,onChanged:(x)=>setState(()=>query=x),
          decoration:const InputDecoration(hintText:'ابحث عن ذكر أو قسم',prefixIcon:Icon(Icons.search)))),
        const SizedBox(height:13),
        const Text('۞',style:TextStyle(color:gold,fontSize:37)),
        const Text('وَاذْكُرْ رَبَّكَ كَثِيرًا',textAlign:TextAlign.center,
          style:TextStyle(color:gold,fontSize:28,fontWeight:FontWeight.bold,height:1.8)),
        const Text('أذكار وأدعية من الكتاب والسنة',style:TextStyle(color:muted,fontSize:14)),
        const SizedBox(height:20),
        Expanded(child:cats.isEmpty?const Center(child:Text('لا توجد نتائج أو لم تكتمل بيانات هذا القسم')):
          GridView.builder(padding:const EdgeInsets.symmetric(horizontal:14,vertical:8),
            gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:3,mainAxisSpacing:10,crossAxisSpacing:10,childAspectRatio:.90),
            itemCount:cats.length,itemBuilder:(context,i)=>ArchCard(category:cats[i],onTap:()=>Navigator.push(context,
              MaterialPageRoute(builder:(_)=>CategoryScreen(c:cats[i],state:state,favesOnly:favesOnly)))))),
        // No frame or label around the collapsed bottom handle.
        InkWell(onTap:()=>setState(()=>navOpen=!navOpen),child:Padding(
          padding:const EdgeInsets.symmetric(vertical:10,horizontal:30),
          child:Icon(navOpen?Icons.keyboard_double_arrow_down:Icons.keyboard_double_arrow_up,color:gold,size:33))),
        AnimatedSize(duration:const Duration(milliseconds:230),curve:Curves.easeInOut,
          child:navOpen?Padding(padding:const EdgeInsets.only(bottom:14),child:Row(mainAxisAlignment:MainAxisAlignment.spaceEvenly,children:[
            _nav(Icons.home_outlined,'الرئيسية',()=>setState(()=>favesOnly=false)),
            _nav(Icons.favorite_border,'المفضلة',()=>setState(()=>favesOnly=true)),
            _nav(Icons.alarm_outlined,'المنبّه',()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>ScheduleScreen(state:state)))),
            _nav(Icons.info_outline,'حول التطبيق',()=>showAboutDialog(context:context,applicationName:'أذكاري',children:[const Text('الأذكار تعمل دون إنترنت. التنبيهات تتطلب إذن الهاتف ومحرك صوت عربيًا.')]))
          ])):const SizedBox.shrink()),
      ])))),
    ));
  }
  Widget _nav(IconData icon,String name,VoidCallback tap)=>InkWell(onTap:tap,child:Column(mainAxisSize:MainAxisSize.min,children:[
    Icon(icon,color:gold,size:22),Text(name,style:const TextStyle(color:cream,fontSize:10))]));
}

class CategoryScreen extends StatefulWidget{
  final AzkarCategory c;final AppState state;final bool favesOnly,autoSpeak;
  const CategoryScreen({super.key,required this.c,required this.state,this.favesOnly=false,this.autoSpeak=false});
  @override State<CategoryScreen> createState()=>_CategoryScreenState();
}
class _CategoryScreenState extends State<CategoryScreen>{
  @override void initState(){super.initState();if(widget.autoSpeak){WidgetsBinding.instance.addPostFrameCallback((_)=>_speakAll());}}
  Future<void> _speakAll() async {
    if(widget.c.items.isEmpty)return;
    await widget.state.readText(widget.c.items.map((e)=>e.text).join('، ... '));
  }
  @override void dispose(){widget.state.stopSpeech();super.dispose();}
  @override Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:Scaffold(
    appBar:AppBar(title:Text(widget.c.title),actions:[
      IconButton(tooltip:'قراءة الأذكار',icon:const Icon(Icons.volume_up_outlined),onPressed:_speakAll),
      IconButton(tooltip:'إيقاف القراءة',icon:const Icon(Icons.stop_circle_outlined),onPressed:widget.state.stopSpeech),
      PopupMenuButton<String>(onSelected:(s){if(s=='reset')widget.state.resetCategory(widget.c);},
        itemBuilder:(_)=>[const PopupMenuItem(value:'reset',child:Text('إعادة عدادات القسم'))])]),
    body:DecorativeBackground(child:AnimatedBuilder(animation:widget.state,builder:(context,_) {
      final items=widget.favesOnly?widget.c.items.where((z)=>widget.state.favorites.contains(z.id)).toList():widget.c.items;
      if(items.isEmpty)return const Center(child:Padding(padding:EdgeInsets.all(20),child:Text('لم تُضف أذكار هذا القسم بعد.')));
      return ListView.builder(padding:const EdgeInsets.all(14),itemCount:items.length,itemBuilder:(context,index){
        final z=items[index];final count=widget.state.count(z),done=count>=z.repeat;
        return Container(margin:const EdgeInsets.only(bottom:13),padding:const EdgeInsets.fromLTRB(16,10,16,16),
          decoration:BoxDecoration(color:panel.withOpacity(.95),borderRadius:BorderRadius.circular(18),border:Border.all(color:borderGold,width:.8)),
          child:Column(children:[
            Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
              Text('✦ ${index+1}',style:const TextStyle(color:gold)),
              Row(children:[
                IconButton(tooltip:'استمع',onPressed:()=>widget.state.readText(z.text),icon:const Icon(Icons.volume_up_outlined,size:20,color:gold)),
                IconButton(tooltip:'المفضلة',onPressed:()=>widget.state.favorite(z),icon:Icon(
                  widget.state.favorites.contains(z.id)?Icons.favorite:Icons.favorite_border,color:gold,size:20)),
                IconButton(tooltip:'نسخ',onPressed:()=>Clipboard.setData(ClipboardData(text:z.text)),
                  icon:const Icon(Icons.copy_outlined,color:muted,size:19))
              ])]),
            const SizedBox(height:8),
            SelectableText(z.text,textAlign:TextAlign.center,style:TextStyle(color:cream,fontSize:widget.state.fontSize,height:1.85)),
            const SizedBox(height:16),
            // The counter is a single small tappable circle displaying only the count.
            Tooltip(message:done?'اكتمل، ضغطة مطوّلة لإعادة العداد':'اضغط للعدّ من ${z.repeat}، ضغطة مطوّلة لإعادة التصفير',
              child:GestureDetector(onTap:()=>widget.state.increment(z),onLongPress:()=>widget.state.reset(z),
                child:AnimatedContainer(duration:const Duration(milliseconds:150),height:58,width:58,
                  alignment:Alignment.center,
                  decoration:BoxDecoration(shape:BoxShape.circle,color:done?gold:ink,border:Border.all(color:gold,width:1.5)),
                  child:Text('$count',style:TextStyle(fontWeight:FontWeight.bold,fontSize:23,color:done?ink:gold))))),
          ]));
      });
    })),
  ));
}

class ScheduleScreen extends StatefulWidget{
  final AppState state;const ScheduleScreen({super.key,required this.state});
  @override State<ScheduleScreen> createState()=>_ScheduleScreenState();
}
class _ScheduleScreenState extends State<ScheduleScreen>{
  @override Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:Scaffold(
    appBar:AppBar(title:const Text('المنبّه وتذكير النوم')),
    body:DecorativeBackground(child:ListView(padding:const EdgeInsets.all(16),children:[
      _scheduleCard(waking:true),const SizedBox(height:16),_scheduleCard(waking:false),const SizedBox(height:20),
      const Text('يبدأ الصوت العربي بعد فتح التذكير واختيار «استيقظت» أو «الاستعداد للنوم». يُرجى تثبيت صوت عربي في إعدادات تحويل النص إلى كلام على الهاتف. تذكيرات أندرويد قد تتأخر بحسب وضع البطارية والصلاحيات.',
        style:TextStyle(color:muted,height:1.7)),
    ]))));
  Widget _scheduleCard({required bool waking}) {
    final s=widget.state, enabled=waking?s.wakeEnabled:s.sleepEnabled,
      time=waking?s.wakeTime:s.sleepTime,days=waking?s.wakeDays:s.sleepDays;
    const names=['الإثنين','الثلاثاء','الأربعاء','الخميس','الجمعة','السبت','الأحد'];
    return _ScheduleEditor(waking:waking,initialEnabled:enabled,initialDays:days,initialTime:time,
        onSave:(e,d,t)async{
          try {await s.changeSchedule(waking:waking,enabled:e,time:t,days:d);
            if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تم حفظ إعدادات التذكير')));
          }catch(ex){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('تعذر ضبط التذكير: $ex')));}
        },names:names);
  }
}
class _ScheduleEditor extends StatefulWidget{
  final bool waking,initialEnabled;
  final Set<int> initialDays;
  final TimeOfDay initialTime;
  final List<String> names;
  final Future<void> Function(bool,Set<int>,TimeOfDay) onSave;
  const _ScheduleEditor({required this.waking,required this.initialEnabled,required this.initialDays,required this.initialTime,required this.onSave,required this.names});
  @override State<_ScheduleEditor> createState()=>_ScheduleEditorState();
}
class _ScheduleEditorState extends State<_ScheduleEditor>{
  late bool enabled;late TimeOfDay time;late Set<int> days;
  @override void initState(){super.initState();enabled=widget.initialEnabled;time=widget.initialTime;days={...widget.initialDays};}
  @override Widget build(BuildContext context)=>Container(
    decoration:BoxDecoration(color:panel,borderRadius:BorderRadius.circular(17),border:Border.all(color:borderGold)),
    padding:const EdgeInsets.all(15),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      SwitchListTile(contentPadding:EdgeInsets.zero,activeColor:gold,
        title:Text(widget.waking?'منبّه الاستيقاظ':'تذكير النوم',style:const TextStyle(color:gold,fontSize:20)),
        subtitle:Text(widget.waking?'استيقظت / غفوة':'الاستعداد للنوم / تذكيري لاحقًا'),
        value:enabled,onChanged:(x)=>setState(()=>enabled=x)),
      OutlinedButton.icon(icon:const Icon(Icons.schedule),label:Text('الموعد: ${time.format(context)}'),
        onPressed:()async{final selected=await showTimePicker(context:context,initialTime:time);
          if(selected!=null)setState(()=>time=selected);}),
      const SizedBox(height:8),
      Wrap(spacing:5,runSpacing:2,children:List.generate(7,(i)=>FilterChip(
        label:Text(widget.names[i].substring(0,3)),selected:days.contains(i+1),
        onSelected:(x)=>setState(()=>x?days.add(i+1):days.remove(i+1))))),
      const SizedBox(height:9),
      FilledButton(onPressed:enabled&&days.isEmpty?null:()=>widget.onSave(enabled,days,time),child:const Text('حفظ الموعد')),
    ]));
}
