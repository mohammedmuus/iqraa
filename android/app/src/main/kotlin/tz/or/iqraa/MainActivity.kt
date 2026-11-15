package tz.or.iqraa

import android.os.Bundle
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.IntegrityTokenRequest
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// Fragment activity for fingerprint and face unlock, with the audio service hook for narration in the background.
class MainActivity : AudioServiceFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Ignore taps while another app draws over this one, so a hidden overlay cannot press buttons.
        window.decorView.filterTouchesWhenObscured = true
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "tz.or.iqraa/heading").setStreamHandler(Heading(this))
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tz.or.iqraa/widget").setMethodCallHandler { call, result ->
            val json = call.arguments as? String
            if (call.method != "update" || json == null) {
                result.notImplemented()
                return@setMethodCallHandler
            }
            LampWidget.save(applicationContext, json)
            result.success(null)
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tz.or.iqraa/integrity").setMethodCallHandler { call, result ->
            if (call.method != "token") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val nonce = call.argument<String>("nonce")
            val project = call.argument<String>("project")?.toLongOrNull()
            if (nonce.isNullOrEmpty() || project == null) {
                result.error("arguments", "Missing nonce or cloud project number", null)
                return@setMethodCallHandler
            }
            val request = IntegrityTokenRequest.builder().setNonce(nonce).setCloudProjectNumber(project).build()
            IntegrityManagerFactory.create(applicationContext)
                .requestIntegrityToken(request)
                .addOnSuccessListener { response -> result.success(response.token()) }
                .addOnFailureListener { error -> result.error("integrity", error.message, null) }
        }
    }
}
