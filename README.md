# مشروع أذكاري - جاهز للبناء باستخدام GitHub Actions

البيانات تجريبية وجزئية، وليست نقلًا كاملًا لمحتوى الموقع. يوجد ملف workflow في `.github/workflows/build-apk.yml` لبناء ملف APK على GitHub.

## من موبايل أندرويد فقط
1. أنشئ مستودع GitHub مع README أولي، وافتح Codespaces من زر Code ثم Codespaces ثم Create codespace on main.
2. في Codespaces افتح قائمة Explorer > Upload Files وارفع ZIP الخاص بالمشروع في جذر المستودع.
3. افتح Terminal وشغّل: `unzip -o azkar_mobile_build.zip` ثم `rm azkar_mobile_build.zip`.
4. نفّذ: `git add -A && git commit -m "Add Flutter app and Android APK workflow" && git push`.
5. ارجع لصفحة المستودع > Actions > Build Android APK، وافتح التشغيل الناتج، ثم حمّل artifact باسم azkar-android-apk.
6. فك ضغط artifact ثم اضغط app-release.apk لتثبيته.

قد تظهر خطوات بشكل مختلف قليلًا على نسخة الهاتف من GitHub. قد يلزم تفعيل وضع سطح المكتب في المتصفح.
