#!/usr/bin/env bash
# يُنشئ مجلد android/ بأدوات Flutter نفسها (المتوافقة مع إصدار Flutter المثبت)،
# ثم يطبق إعدادات التطبيق: الاسم، الأذونات، الأيقونة، تثبيت الشاشة، الحد الأدنى لإصدار Android.
# الاستعمال (من جذر المشروع):  bash tool/prepare_android.sh
set -euo pipefail

ORG="ma.riyada.mediouna"
APP_LABEL="مكتبتي الصفية"

if [ ! -d android/app ]; then
  echo ">> إنشاء مجلد android/ ..."
  flutter create --platforms=android --org "$ORG" --project-name maktabati .
fi

MANIFEST=android/app/src/main/AndroidManifest.xml

# 1) اسم التطبيق
sed -i "s/android:label=\"[^\"]*\"/android:label=\"$APP_LABEL\"/" "$MANIFEST"

# 2) الأذونات: الإنترنت (للذكاء الاصطناعي فقط)، الميكروفون (تسجيل صوت الأستاذ)، الكاميرا (رموز QR)
add_perm() {
  if ! grep -q "$1" "$MANIFEST"; then
    sed -i "0,/<application/s//<uses-permission android:name=\"$1\" \/>\n    <application/" "$MANIFEST"
  fi
}
add_perm android.permission.INTERNET
add_perm android.permission.RECORD_AUDIO
add_perm android.permission.CAMERA

# 3) MainActivity مع قناة تثبيت الشاشة
MAIN=$(find android/app/src/main -name 'MainActivity.kt' | head -1)
if [ -n "$MAIN" ]; then
  PKG=$(grep -m1 '^package ' "$MAIN" | awk '{print $2}')
  sed "s/__PACKAGE__/$PKG/" tool/android/MainActivity.kt > "$MAIN"
  echo ">> MainActivity: $PKG"
fi

# 4) الأيقونة
for d in mdpi hdpi xhdpi xxhdpi xxxhdpi; do
  if [ -d "android/app/src/main/res/mipmap-$d" ]; then
    cp "tool/android/res/mipmap-$d/ic_launcher.png" "android/app/src/main/res/mipmap-$d/ic_launcher.png"
  fi
done

# 5) الحد الأدنى: Android 7.0 (API 24) — مطلوب لبعض المكتبات (الكاميرا، التسجيل)
GRADLE_KTS=android/app/build.gradle.kts
GRADLE=android/app/build.gradle
if [ -f "$GRADLE_KTS" ]; then
  sed -i 's/minSdk = flutter.minSdkVersion/minSdk = 24/' "$GRADLE_KTS"
elif [ -f "$GRADLE" ]; then
  sed -i 's/minSdkVersion flutter.minSdkVersion/minSdkVersion 24/; s/minSdk = flutter.minSdkVersion/minSdk = 24/' "$GRADLE"
fi

# 6) توقيع ثابت للنسخ (لتثبيت التحديثات دون حذف التطبيق وبياناته)
python3 tool/patch_signing.py

echo ">> تم تجهيز android/"
grep -n "uses-permission\|android:label" "$MANIFEST" || true
