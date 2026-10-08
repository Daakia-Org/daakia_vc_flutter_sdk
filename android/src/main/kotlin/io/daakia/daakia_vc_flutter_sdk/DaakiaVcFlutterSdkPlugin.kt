package io.daakia.daakia_vc_flutter_sdk

import android.content.ContentValues
import android.content.Context
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.Settings
import androidx.annotation.RequiresApi
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class DaakiaVcFlutterSdkPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var context: Context
    private var channel: MethodChannel? = null
    private var audioDevicesChannel: MethodChannel? = null
    private var audioDeviceEvents: EventChannel? = null
    private var audioDeviceCallback: AudioDeviceCallback? = null

    companion object {
        // Channel of the engine that started the meeting service. Notification
        // actions are routed here only — a host app can attach this plugin to
        // several engines (e.g. an FCM background isolate), and the last one to
        // attach isn't necessarily the one running the meeting.
        private var serviceOwnerChannel: MethodChannel? = null
        private val mainHandler = Handler(Looper.getMainLooper())

        /** True while the engine that started the meeting service is still attached. */
        val hasServiceOwner: Boolean
            get() = serviceOwnerChannel != null

        /** Called from the service (background thread safe) to invoke a Dart method. */
        fun invokeOnFlutter(method: String, args: Any?) {
            mainHandler.post {
                serviceOwnerChannel?.invokeMethod(method, args)
            }
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "io.daakia/meeting_service")
        channel!!.setMethodCallHandler(this)

        // LiveKit 2.13 disables flutter_webrtc's audio manager, so its
        // enumerateDevices() no longer reports audio outputs. These channels
        // stand in for it (see lib/rtc/audio_routing.dart).
        audioDevicesChannel = MethodChannel(binding.binaryMessenger, "io.daakia/audio_devices").also {
            it.setMethodCallHandler { call, result ->
                if (call.method == "getAudioOutputs") result.success(audioOutputs())
                else result.notImplemented()
            }
        }
        audioDeviceEvents = EventChannel(binding.binaryMessenger, "io.daakia/audio_devices/events").also {
            it.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    startAudioDeviceWatch(events)
                }

                override fun onCancel(arguments: Any?) {
                    stopAudioDeviceWatch()
                }
            })
        }
    }

    // Diagnostics: where Android is actually sending call audio right now
    // (see DaakiaAudioRouting.diagRoute on the Dart side).
    private fun audioRouteSnapshot(): Map<String, Any?> {
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val mode = when (audioManager.mode) {
            AudioManager.MODE_NORMAL -> "normal"
            AudioManager.MODE_IN_CALL -> "inCall"
            AudioManager.MODE_IN_COMMUNICATION -> "inCommunication"
            AudioManager.MODE_RINGTONE -> "ringtone"
            else -> "other(${audioManager.mode})"
        }
        val snapshot = mutableMapOf<String, Any?>(
            "mode" to mode,
            "outputs" to audioOutputs().map { it["label"] },
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val device = audioManager.communicationDevice
            snapshot["communicationDevice"] =
                device?.let { "${audioDeviceTypeName(it.type)}:${it.productName}" }
        } else {
            @Suppress("DEPRECATION")
            snapshot["speakerphoneOn"] = audioManager.isSpeakerphoneOn
            @Suppress("DEPRECATION")
            snapshot["bluetoothScoOn"] = audioManager.isBluetoothScoOn
        }
        return snapshot
    }

    private fun audioDeviceTypeName(type: Int): String = when (type) {
        AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "Earpiece"
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "Speaker"
        AudioDeviceInfo.TYPE_WIRED_HEADSET -> "WiredHeadset"
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "WiredHeadphones"
        AudioDeviceInfo.TYPE_USB_HEADSET -> "UsbHeadset"
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "BluetoothSco"
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "BluetoothA2dp"
        else -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            type == AudioDeviceInfo.TYPE_BLE_HEADSET) "BleHeadset" else "type$type"
    }

    // Lists audio outputs exactly like the audioswitch AudioDeviceScanner that
    // flutter_webrtc used before LiveKit 2.13: one entry per kind, labelled with
    // the audioswitch device names.
    private fun audioOutputs(): List<Map<String, String>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return emptyList()
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val outputs = LinkedHashMap<String, String>()
        for (device in audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)) {
            when {
                device.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                    device.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
                    (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                        (device.type == AudioDeviceInfo.TYPE_BLE_HEADSET ||
                            device.type == AudioDeviceInfo.TYPE_BLE_SPEAKER)) ->
                    outputs.getOrPut("bluetooth") { device.productName.toString() }

                device.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                    device.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
                    device.type == AudioDeviceInfo.TYPE_USB_HEADSET ->
                    outputs.getOrPut("wired-headset") { "Wired Headset" }

                device.type == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE ->
                    outputs.getOrPut("earpiece") { "Earpiece" }

                device.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER ->
                    outputs.getOrPut("speaker") { "Speakerphone" }
            }
        }
        return outputs.map { (id, label) -> mapOf("deviceId" to id, "label" to label) }
    }

    private fun startAudioDeviceWatch(events: EventChannel.EventSink) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        stopAudioDeviceWatch()
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val callback = object : AudioDeviceCallback() {
            override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>?) {
                events.success(null)
            }

            override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>?) {
                events.success(null)
            }
        }
        audioManager.registerAudioDeviceCallback(callback, mainHandler)
        audioDeviceCallback = callback
    }

    private fun stopAudioDeviceWatch() {
        val callback = audioDeviceCallback ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            audioManager.unregisterAudioDeviceCallback(callback)
        }
        audioDeviceCallback = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startMeetingService" -> {
                val title = call.argument<String>("title") ?: "Meeting"
                val text = call.argument<String>("text") ?: "Tap to return to the meeting"
                val isMuted = call.argument<Boolean>("isMuted") ?: false
                val showMuteButton = call.argument<Boolean>("showMuteButton") ?: false
                serviceOwnerChannel = channel
                DaakiaMeetingService.start(context, title, text, isMuted, showMuteButton)
                result.success(null)
            }
            "stopMeetingService" -> {
                if (serviceOwnerChannel === channel) serviceOwnerChannel = null
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
            "getAudioRoute" -> result.success(audioRouteSnapshot())
            "getDeviceId" -> {
                // ANDROID_ID: unique per device + app signing key + user, and it
                // survives a reinstall. Used only to tell this device's own
                // session apart from another device's; the Dart side hashes it
                // before it ever leaves the app.
                val androidId = try {
                    Settings.Secure.getString(
                        context.contentResolver,
                        Settings.Secure.ANDROID_ID
                    )
                } catch (e: Exception) {
                    null
                }
                result.success(androidId)
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
        stopAudioDeviceWatch()
        audioDevicesChannel?.setMethodCallHandler(null)
        audioDevicesChannel = null
        audioDeviceEvents?.setStreamHandler(null)
        audioDeviceEvents = null
        // The engine that owns the meeting is going away (activity destroyed,
        // app swiped from recents). Its Dart side can never call stop now, so
        // stop the service here instead of leaving an orphaned notification.
        if (channel != null && serviceOwnerChannel === channel) {
            serviceOwnerChannel = null
            DaakiaMeetingService.stop(context)
        }
        channel = null
    }
}
