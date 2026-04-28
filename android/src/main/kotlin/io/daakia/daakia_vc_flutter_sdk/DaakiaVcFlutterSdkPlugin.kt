package io.daakia.daakia_vc_flutter_sdk

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class DaakiaVcFlutterSdkPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "io.daakia/meeting_service")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startMeetingService" -> {
                val title = call.argument<String>("title") ?: "Meeting"
                val text = call.argument<String>("text") ?: "Tap to return to the meeting"
                DaakiaMeetingService.start(context, title, text)
                result.success(null)
            }
            "stopMeetingService" -> {
                DaakiaMeetingService.stop(context)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
