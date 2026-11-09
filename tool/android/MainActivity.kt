package __PACKAGE__

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * تثبيت الشاشة (Screen pinning) أثناء فضاء التلاميذ، حتى لا يخرج التلميذ من التطبيق.
 * يطلب Android من المستخدم تأكيد التثبيت. لإلغائه يدويًا: الضغط المطول على زرّي «رجوع» و«الأخيرة».
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "maktabati/kiosk").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    try {
                        startLockTask()
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "stop" -> {
                    try {
                        stopLockTask()
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
