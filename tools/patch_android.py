"""Patch a Flutter-generated Android project for scheduled local notifications."""
from pathlib import Path
import re
root = Path('android/app')
manifest = root / 'src/main/AndroidManifest.xml'
text = manifest.read_text()
for p in ['android.permission.POST_NOTIFICATIONS', 'android.permission.RECEIVE_BOOT_COMPLETED']:
    entry=f'    <uses-permission android:name="{p}" />\n'
    if p not in text:
        text=text.replace('<application', entry+'    <application',1)
receiver='''
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
          <intent-filter>
            <action android:name="android.intent.action.BOOT_COMPLETED" />
            <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
            <action android:name="android.intent.action.QUICKBOOT_POWERON" />
            <action android:name="com.htc.intent.action.QUICKBOOT_POWERON" />
          </intent-filter>
        </receiver>
'''
if 'ScheduledNotificationReceiver' not in text:
    text=text.replace('</application>',receiver+'    </application>')
manifest.write_text(text)
# Enable Android desugaring required by flutter_local_notifications 17.x
kts=root/'build.gradle.kts'
groovy=root/'build.gradle'
if kts.exists():
    s=kts.read_text()
    if 'isCoreLibraryDesugaringEnabled' not in s:
        if 'compileOptions {' in s:
            s=s.replace('compileOptions {','compileOptions {\n        isCoreLibraryDesugaringEnabled = true',1)
        else:
            s=s.replace('android {','android {\n    compileOptions { isCoreLibraryDesugaringEnabled = true }',1)
    if 'coreLibraryDesugaring(' not in s:
        s+='\n\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    kts.write_text(s)
elif groovy.exists():
    s=groovy.read_text()
    if 'coreLibraryDesugaringEnabled true' not in s:
        s=s.replace('compileOptions {','compileOptions {\n        coreLibraryDesugaringEnabled true',1) if 'compileOptions {' in s else s.replace('android {','android {\n  compileOptions { coreLibraryDesugaringEnabled true }',1)
    if "coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'" not in s:
        s+="\n\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"
    groovy.write_text(s)
print('Android notification configuration applied')
