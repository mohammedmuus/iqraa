package tz.or.iqraa

import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
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
        adhanChannel()
    }

    // The adhan channel is made here, pointing straight at the sound file, so release builds can never
    // lose the sound and fall back to the phone's default tone. A channel's sound cannot change once
    // made, so the first channel, which some phones made with the default tone, is removed.
    private fun adhanChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = getSystemService(NotificationManager::class.java) ?: return
        manager.deleteNotificationChannel(OLD_ADHAN_CHANNEL)
        if (manager.getNotificationChannel(ADHAN_CHANNEL) != null) {
            return
        }
        val sound = Uri.parse("android.resource://$packageName/${R.raw.adhan_short}")
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val channel = NotificationChannel(ADHAN_CHANNEL, "Adhan", NotificationManager.IMPORTANCE_HIGH)
        channel.setSound(sound, attributes)
        channel.enableVibration(true)
        manager.createNotificationChannel(channel)
    }

    companion object {
        // Also named in lib/core/reminders.dart.
        const val ADHAN_CHANNEL = "tz.or.iqraa.adhan.sound"
        const val OLD_ADHAN_CHANNEL = "tz.or.iqraa.adhan"
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
