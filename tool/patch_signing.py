"""يضبط توقيع نسخة release بمفتاح ثابت (tool/android/maktabati-release.jks)
حتى يمكن تثبيت التحديثات فوق التطبيق دون حذفه (وبالتالي دون ضياع البيانات).
كلمة السر تُقرأ من متغيرات البيئة MAKTABATI_STORE_PASSWORD إن وُجدت، وإلا القيمة الافتراضية أدناه.
"""
import pathlib, re, sys

DEFAULT_PW = "K7g1yDJQfjSCLEpkRqaR"
KTS = pathlib.Path("android/app/build.gradle.kts")
GROOVY = pathlib.Path("android/app/build.gradle")
if not pathlib.Path("tool/android/maktabati-release.jks").exists():
    print(">> لا يوجد مفتاح توقيع، سيُستعمل مفتاح debug")
    sys.exit(0)

if KTS.exists():
    s = KTS.read_text(encoding="utf-8")
    if 'create("release")' not in s:
        block = f'''    signingConfigs {{
        create("release") {{
            storeFile = file("../../tool/android/maktabati-release.jks")
            storePassword = System.getenv("MAKTABATI_STORE_PASSWORD") ?: "{DEFAULT_PW}"
            keyAlias = "maktabati"
            keyPassword = System.getenv("MAKTABATI_STORE_PASSWORD") ?: "{DEFAULT_PW}"
        }}
    }}

    buildTypes {{'''
        s = re.sub(r"    buildTypes \{", block, s, count=1)
        s = s.replace('signingConfig = signingConfigs.getByName("debug")', 'signingConfig = signingConfigs.getByName("release")')
        KTS.write_text(s, encoding="utf-8")
    print(">> توقيع release مضبوط (build.gradle.kts)")
elif GROOVY.exists():
    s = GROOVY.read_text(encoding="utf-8")
    if "signingConfigs {" not in s:
        block = f'''    signingConfigs {{
        release {{
            storeFile file("../../tool/android/maktabati-release.jks")
            storePassword System.getenv("MAKTABATI_STORE_PASSWORD") ?: "{DEFAULT_PW}"
            keyAlias "maktabati"
            keyPassword System.getenv("MAKTABATI_STORE_PASSWORD") ?: "{DEFAULT_PW}"
        }}
    }}

    buildTypes {{'''
        s = re.sub(r"    buildTypes \{", block, s, count=1)
        s = s.replace("signingConfig = signingConfigs.debug", "signingConfig = signingConfigs.release")
        s = s.replace("signingConfig signingConfigs.debug", "signingConfig signingConfigs.release")
        GROOVY.write_text(s, encoding="utf-8")
    print(">> توقيع release مضبوط (build.gradle)")
