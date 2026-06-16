package io.daakia.daakia_vc_flutter_sdk

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import androidx.annotation.RequiresApi
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

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
                val svc = DaakiaMeetingService.instance
                if (svc == null) {
                    result.error("SERVICE_NOT_RUNNING", "DaakiaMeetingService is not running", null)
                    return
                }
                svc.addMediaProjectionType()
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
            "saveFileToDownloads" -> {
                val sourcePath = call.argument<String>("sourcePath")
                    ?: return result.error("INVALID_ARG", "sourcePath is required", null)
                val fileName = call.argument<String>("fileName")
                    ?: return result.error("INVALID_ARG", "fileName is required", null)
                val mimeType = call.argument<String>("mimeType") ?: "*/*"
                try {
                    val savedPath = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        saveViaMediaStore(sourcePath, fileName, mimeType)
                    } else {
                        saveToLegacyDownloads(sourcePath, fileName)
                    }
                    result.success(savedPath)
                } catch (e: Exception) {
                    result.error("SAVE_ERROR", e.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun saveViaMediaStore(sourcePath: String, fileName: String, mimeType: String): String {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, fileName)
            put(MediaStore.Downloads.MIME_TYPE, mimeType)
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw Exception("MediaStore insert failed for $fileName")
        resolver.openOutputStream(uri)?.use { out ->
            File(sourcePath).inputStream().use { it.copyTo(out) }
        } ?: throw Exception("Could not open MediaStore output stream")
        values.clear()
        values.put(MediaStore.Downloads.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
        return uri.toString()
    }

    private fun saveToLegacyDownloads(sourcePath: String, fileName: String): String {
        val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        dir.mkdirs()
        val dest = File(dir, fileName)
        File(sourcePath).copyTo(dest, overwrite = true)
        return dest.absolutePath
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        pluginChannel = null
        channel = null
    }
}
