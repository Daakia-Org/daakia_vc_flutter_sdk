package io.daakia.daakia_vc_flutter_sdk

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class DaakiaVcFlutterSdkPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var context: Context
    private var channel: MethodChannel? = null

    companion object {
        private var pluginChannel: MethodChannel? = null
        private val mainHandler = Handler(Looper.getMainLooper())

        /** Called from the service (background thread safe) to invoke a Dart method. */
        fun invokeOnFlutter(method: String, args: Any?) {
            mainHandler.post {
                pluginChannel?.invokeMethod(method, args)
            }
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "io.daakia/meeting_service")
        channel!!.setMethodCallHandler(this)
        pluginChannel = channel
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startMeetingService" -> {
                val title = call.argument<String>("title") ?: "Meeting"
                val text = call.argument<String>("text") ?: "Tap to return to the meeting"
                val isMuted = call.argument<Boolean>("isMuted") ?: false
                val showMuteButton = call.argument<Boolean>("showMuteButton") ?: false
                DaakiaMeetingService.start(context, title, text, isMuted, showMuteButton)
                result.success(null)
            }
            "stopMeetingService" -> {
                DaakiaMeetingService.stop(context)
                result.success(null)
            }
            "startScreenShareService" -> {
                DaakiaMeetingService.instance?.addMediaProjectionType()
                result.success(null)
            }
            "stopScreenShareService" -> {
                DaakiaMeetingService.instance?.removeMediaProjectionType()
                result.success(null)
            }
            "updateMuteState" -> {
                val isMuted = call.argument<Boolean>("isMuted") ?: false
                val showMuteButton = call.argument<Boolean>("showMuteButton") ?: false
                DaakiaMeetingService.update(context, isMuted, showMuteButton)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        pluginChannel = null
        channel = null
    }
}
