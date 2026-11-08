import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AzkarApp());
}

class Zikr {
  final String id, text, reference, benefit;
  final int repeat;
  const Zikr(this.id, this.text, this.reference, this.benefit, this.repeat);
  factory Zikr.fromJson(Map<String, dynamic> j) => Zikr(
    j['id'] as String,
    j['text'] as String,
    (j['reference'] ?? '') as String,
    (j['benefit'] ?? '') as String,
    (j['repeat'] as num?)?.toInt() ?? 1,
  );
}

class AzkarCategory {
  final String id, title, symbol;
  final List<Zikr> items;
  const AzkarCategory(this.id, this.title, this.symbol, this.items);
  factory AzkarCategory.fromJson(Map<String, dynamic> j) => AzkarCategory(
    j['id'] as String,
    j['title'] as String,
    (j['symbol'] ?? '✦') as String,
    ((j['items'] ?? []) as List).map((e) => Zikr.fromJson(e as Map<String, dynamic>)).toList(),
  );
}

class Store extends ChangeNotifier {
  final Map<String, int> counts = {};
  final Set<String> favorites = {};
  late SharedPreferences prefs;
  bool dark = false;
  double fontSize = 25;

  Future<void> load() async {
    prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('counts_v1');
    if (saved != null) {
      try {
        final data = jsonDecode(saved) as Map<String, dynamic>;
        for (final entry in data.entries) {
          counts[entry.key] = (entry.value as num).toInt();
        }
      } catch (_) { /* ignore corrupted local cache */ }
    }
    favorites.addAll(prefs.getStringList('favorites_v1') ?? []);
    dark = prefs.getBool('dark_v1') ?? false;
    fontSize = prefs.getDouble('size_v1') ?? 25;
    notifyListeners();
  }

  int count(Zikr z) => (counts[z.id] ?? 0).clamp(0, z.repeat);
  void increment(Zikr z) {
    if (count(z) >= z.repeat) return;
    counts[z.id] = count(z) + 1;
    _saveCounts();
    HapticFeedback.selectionClick();
    notifyListeners();
  }
  void decrement(Zikr z) {
    if (count(z) == 0) return;
    counts[z.id] = count(z) - 1;
    _saveCounts();
    notifyListeners();
  }
  void resetCategory(AzkarCategory category) {
    for (final z in category.items) { counts.remove(z.id); }
    _saveCounts();
    notifyListeners();
  }
  void toggleFavorite(Zikr z) {
    if (!favorites.add(z.id)) favorites.remove(z.id);
    prefs.setStringList('favorites_v1', favorites.toList());
    notifyListeners();
  }
  void setDark(bool value) {
    dark = value;
    prefs.setBool('dark_v1', value);
    notifyListeners();
  }
  void setFontSize(double value) {
    fontSize = value;
    prefs.setDouble('size_v1', value);
    notifyListeners();
  }
  void _saveCounts() => prefs.setString('counts_v1', jsonEncode(counts));
}

class AzkarApp extends StatefulWidget {
  const AzkarApp({super.key});
  @override
  State<AzkarApp> createState() => _AzkarAppState();
}

class _AzkarAppState extends State<AzkarApp> {
  final Store store = Store();
  late final Future<List<AzkarCategory>> categories = _load();
  Future<List<AzkarCategory>> _load() async {
    await store.load();
    final raw = await rootBundle.loadString('assets/data/azkar.json');
    return (jsonDecode(raw) as List)
        .map((e) => AzkarCategory.fromJson(e as Map<String, dynamic>)).toList();
  }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) => MaterialApp(
      title: 'أذكاري',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: store.dark ? ThemeMode.dark : ThemeMode.light,
      home: FutureBuilder<List<AzkarCategory>>(
        future: categories,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Scaffold(body: Center(child: Text('تعذّر تحميل الأذكار: ${snapshot.error}')));
          }
          if (!snapshot.hasData) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return HomePage(categories: snapshot.data!, store: store);
        },
      ),
    ),
  );
  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF11735D), brightness: brightness);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: brightness == Brightness.light
          ? const Color(0xFFF5F8F5) : const Color(0xFF101917),
      appBarTheme: const AppBarTheme(centerTitle: true),
    );
  }
}

class HomePage extends StatefulWidget {
  final List<AzkarCategory> categories;
  final Store store;
  const HomePage({super.key, required this.categories, required this.store});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String query = '';
  bool onlyFavorites = false;

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final all = widget.categories;
    final filtered = all.where((c) {
      if (onlyFavorites && !c.items.any((z) => store.favorites.contains(z.id))) return false;
      return c.title.contains(query.trim()) || c.items.any((z) => z.text.contains(query.trim()));
    }).toList();
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('أذكاري'),
          actions: [
            IconButton(
              tooltip: 'الوضع الليلي',
              onPressed: () => store.setDark(!store.dark),
              icon: Icon(store.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            ),
          ],
        ),
        body: Column(children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('وَاذْكُرْ رَبَّكَ كَثِيرًا',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
              const SizedBox(height: 7),
              Text('أذكار وأدعية • ${all.length} قسمًا • يعمل دون إنترنت'),
              const SizedBox(height: 12),
              Text('المحتوى الموجود حاليًا نسخة تأسيسية، ويحتاج استكمالًا ومراجعة قبل النشر.',
                  style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              onChanged: (s) => setState(() => query = s),
              decoration: InputDecoration(
                hintText: 'ابحث في الأقسام أو نصوص الأذكار',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              FilterChip(
                label: const Text('المفضلة'),
                avatar: const Icon(Icons.favorite_outline, size: 18),
                selected: onlyFavorites,
                onSelected: (v) => setState(() => onlyFavorites = v),
              ),
              const Spacer(),
              Text('${filtered.length} قسم', style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
          Expanded(child: filtered.isEmpty
              ? const Center(child: Text('لا توجد نتائج'))
              : ListView.builder(
                  itemCount: filtered.length,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 22),
                  itemBuilder: (context, index) {
                    final cat = filtered[index];
                    final items = onlyFavorites
                        ? cat.items.where((z) => store.favorites.contains(z.id)).toList()
                        : cat.items;
                    final done = items.where((z) => store.count(z) >= z.repeat).length;
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 5),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(12),
                        leading: CircleAvatar(child: Text(cat.symbol, style: const TextStyle(fontSize: 23))),
                        title: Text(cat.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(cat.items.isEmpty
                            ? 'بانتظار إضافة أذكار مراجَعة'
                            : '${items.length} ذكر • المكتمل $done'),
                        trailing: const Icon(Icons.chevron_left),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => CategoryPage(category: cat, store: store, favoritesOnly: onlyFavorites))),
                      ),
                    );
                  },
                )),
        ]),
      ),
    );
  }
}

class CategoryPage extends StatefulWidget {
  final AzkarCategory category;
  final Store store;
  final bool favoritesOnly;
  const CategoryPage({super.key, required this.category, required this.store, this.favoritesOnly = false});
  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage> {
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      final store = widget.store;
      final category = widget.category;
      final items = widget.favoritesOnly
          ? category.items.where((z) => store.favorites.contains(z.id)).toList()
          : category.items;
      final completed = items.where((z) => store.count(z) >= z.repeat).length;
      final progress = items.isEmpty ? 0.0 : completed / items.length;
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: Text(category.title), actions: [
            IconButton(
              tooltip: 'إعادة العدادات للصفر', icon: const Icon(Icons.restart_alt),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('إعادة العدّادات؟'),
                  content: const Text('سيتم تصفير تقدم هذا القسم فقط.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
                    FilledButton(onPressed: () {
                      store.resetCategory(category);
                      Navigator.pop(dialogContext);
                    }, child: const Text('تصفير')),
                  ],
                ),
              ),
            ),
          ]),
          body: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
              child: Column(children: [
                Row(children: [
                  Text('أنجزت $completed من ${items.length}'),
                  const Spacer(),
                  Text('${(progress * 100).round()}%'),
                ]),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: progress, minHeight: 7, borderRadius: BorderRadius.circular(10)),
                Row(children: [
                  const Text('حجم الخط', style: TextStyle(fontSize: 12)),
                  Expanded(child: Slider(
                    min: 19, max: 37,
                    value: store.fontSize,
                    onChanged: store.setFontSize,
                  )),
                ]),
              ]),
            ),
            Expanded(child: items.isEmpty
                ? const Center(child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('لم تُضَف نصوص مراجَعة إلى هذا القسم بعد.', textAlign: TextAlign.center)))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 30),
                    itemCount: items.length,
                    itemBuilder: (context, i) => ZikrCard(
                      key: ValueKey(items[i].id),
                      zikr: items[i], store: store, index: i + 1,
                    ),
                  )),
          ]),
        ),
      );
    },
  );
}

class ZikrCard extends StatelessWidget {
  final Zikr zikr;
  final Store store;
  final int index;
  const ZikrCard({super.key, required this.zikr, required this.store, required this.index});
  @override
  Widget build(BuildContext context) {
    final count = store.count(zikr);
    final isDone = count >= zikr.repeat;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text('الذكر $index', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(
              tooltip: 'المفضلة',
              onPressed: () => store.toggleFavorite(zikr),
              icon: Icon(store.favorites.contains(zikr.id) ? Icons.favorite : Icons.favorite_border,
                  color: store.favorites.contains(zikr.id) ? Colors.red : null),
            ),
            IconButton(
              tooltip: 'نسخ',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: zikr.text));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ الذكر')));
              },
              icon: const Icon(Icons.copy_outlined),
            ),
          ]),
          SelectableText(zikr.text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: store.fontSize, height: 1.85, fontWeight: FontWeight.w500)),
          if (zikr.reference.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('المصدر: ${zikr.reference}', style: Theme.of(context).textTheme.bodySmall),
          ],
          if (zikr.benefit.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(zikr.benefit, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 20),
          LinearProgressIndicator(
              value: zikr.repeat == 0 ? 0 : count / zikr.repeat,
              minHeight: 5, borderRadius: BorderRadius.circular(5)),
          const SizedBox(height: 12),
          Row(children: [
            IconButton(onPressed: count > 0 ? () => store.decrement(zikr) : null,
                tooltip: 'تراجع', icon: const Icon(Icons.remove_circle_outline)),
            Expanded(child: FilledButton.icon(
              onPressed: isDone ? null : () => store.increment(zikr),
              icon: Icon(isDone ? Icons.check_circle : Icons.touch_app),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(isDone ? 'مكتمل ✓ ($count / ${zikr.repeat})' : 'اضغط للعدّ  $count / ${zikr.repeat}',
                    style: const TextStyle(fontSize: 16)),
              ),
            )),
            IconButton(
              tooltip: 'إعادة هذا الذكر',
              onPressed: count == 0 ? null : () {
                while (store.count(zikr) > 0) { store.decrement(zikr); }
              },
              icon: const Icon(Icons.refresh),
            ),
          ]),
        ]),
      ),
    );
  }
}
