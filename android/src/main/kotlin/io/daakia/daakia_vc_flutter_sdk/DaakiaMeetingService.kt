package io.daakia.daakia_vc_flutter_sdk

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

class DaakiaMeetingService : Service() {

    companion object {
        private const val TAG = "DaakiaMeetingService"
        private const val CHANNEL_ID = "daakia_meeting_channel"
        private const val NOTIFICATION_ID = 7331

        const val ACTION_START = "io.daakia.MEETING_START"
        const val ACTION_STOP = "io.daakia.MEETING_STOP"
        const val ACTION_UPDATE = "io.daakia.MEETING_UPDATE"
        const val ACTION_TOGGLE_MUTE = "io.daakia.TOGGLE_MUTE"
        const val ACTION_END_CALL = "io.daakia.END_CALL"

        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"
        const val EXTRA_IS_MUTED = "is_muted"
        const val EXTRA_SHOW_MUTE_BTN = "show_mute_btn"

        // Held so the plugin can call startForeground() synchronously on the
        // main thread without going through an intent round-trip.
        var instance: DaakiaMeetingService? = null

        fun start(context: Context, title: String, text: String, isMuted: Boolean, showMuteButton: Boolean) {
            val intent = Intent(context, DaakiaMeetingService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_TEXT, text)
                putExtra(EXTRA_IS_MUTED, isMuted)
                putExtra(EXTRA_SHOW_MUTE_BTN, showMuteButton)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun update(context: Context, isMuted: Boolean, showMuteButton: Boolean) {
            val intent = Intent(context, DaakiaMeetingService::class.java).apply {
                action = ACTION_UPDATE
                putExtra(EXTRA_IS_MUTED, isMuted)
                putExtra(EXTRA_SHOW_MUTE_BTN, showMuteButton)
            }
            context.startService(intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, DaakiaMeetingService::class.java))
        }
    }

    private var meetingTitle = "Meeting"
    private var meetingText = "Tap to return to the meeting"
    private var isMuted = false
    private var showMuteButton = false

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onDestroy() {
        instance = null
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    // Base FGS type mask used for the meeting. Each startForeground() call
    // replaces the previous mask, so every call must include all active types.
    //
    // FOREGROUND_SERVICE_TYPE_MICROPHONE requires API 30, the manifest permission
    // FOREGROUND_SERVICE_MICROPHONE, AND the RECORD_AUDIO runtime permission to
    // already be granted. Without the runtime grant Android 12+ (targetSdk 32+)
    // throws SecurityException — same crash pattern as the old camera type crash.
    // So we only include it when the permission is actually held.
    private val baseFgsType: Int
        get() {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return 0
            var type = ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                // Only include microphone/camera types when the runtime permission is
                // already granted. Including a type without its runtime grant throws
                // SecurityException on Android 12+ (targetSdk 32+) — same crash
                // pattern as the old IsolateHolderService camera type crash in v4.4.1.
                if (checkSelfPermission(android.Manifest.permission.RECORD_AUDIO)
                        == android.content.pm.PackageManager.PERMISSION_GRANTED) {
                    type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                }
                if (checkSelfPermission(android.Manifest.permission.CAMERA)
                        == android.content.pm.PackageManager.PERMISSION_GRANTED) {
                    type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
                }
            }
            return type
        }

    /** Adds mediaProjection type to the running FGS. Must be called on the main thread,
     *  immediately after the user grants screen capture permission. */
    fun addMediaProjectionType() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                ServiceCompat.startForeground(
                    this,
                    NOTIFICATION_ID,
                    buildNotification(),
                    baseFgsType or ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
                )
            } catch (e: Exception) {
                Log.w(TAG, "addMediaProjectionType failed: $e")
            }
        }
    }

    /** Removes mediaProjection type from the running FGS once screen share ends. */
    fun removeMediaProjectionType() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                ServiceCompat.startForeground(
                    this,
                    NOTIFICATION_ID,
                    buildNotification(),
                    baseFgsType
                )
            } catch (e: Exception) {
                Log.w(TAG, "removeMediaProjectionType failed: $e")
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                meetingTitle = intent.getStringExtra(EXTRA_TITLE) ?: meetingTitle
                meetingText = intent.getStringExtra(EXTRA_TEXT) ?: meetingText
                isMuted = intent.getBooleanExtra(EXTRA_IS_MUTED, isMuted)
                showMuteButton = intent.getBooleanExtra(EXTRA_SHOW_MUTE_BTN, showMuteButton)
                startMeetingForeground()
            }
            ACTION_UPDATE -> {
                isMuted = intent.getBooleanExtra(EXTRA_IS_MUTED, isMuted)
                showMuteButton = intent.getBooleanExtra(EXTRA_SHOW_MUTE_BTN, showMuteButton)
                refreshNotification()
            }
            ACTION_TOGGLE_MUTE -> {
                DaakiaVcFlutterSdkPlugin.invokeOnFlutter("onMuteToggle", null)
            }
            ACTION_END_CALL -> {
                // Bring the Activity to the foreground first. This exits Android PiP mode
                // cleanly so that Flutter's Navigator.pop() doesn't leave the PiP overlay
                // frozen on the previous page.
                val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                }
                if (launchIntent != null) startActivity(launchIntent)

                // Delay Flutter callback so Android has time to finish the PiP→fullscreen
                // transition before navigation happens (~300 ms is reliable in practice).
                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                    DaakiaVcFlutterSdkPlugin.invokeOnFlutter("onEndCall", null)
                }, 300)
            }
            ACTION_STOP -> stopSelf()
        }
        return START_STICKY
    }

    private fun startMeetingForeground() {
        createNotificationChannel()
        val notification = buildNotification()
        try {
            ServiceCompat.startForeground(this, NOTIFICATION_ID, notification, baseFgsType)
        } catch (e: Exception) {
            Log.w(TAG, "startForeground failed, running without foreground promotion: $e")
        }
    }

    private fun refreshNotification() {
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, buildNotification())
    }

    private fun buildNotification(): android.app.Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val openPi = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val iconId = resources.getIdentifier("ic_notification", "drawable", packageName)
            .takeIf { it != 0 } ?: android.R.drawable.ic_menu_call

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(meetingTitle)
            .setContentText(meetingText)
            .setSmallIcon(iconId)
            .setContentIntent(openPi)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_CALL)

        if (showMuteButton) {
            val muteLabel = if (isMuted) "Unmute" else "Mute"
            val muteIcon = if (isMuted)
                android.R.drawable.ic_lock_silent_mode_off
            else
                android.R.drawable.ic_lock_silent_mode

            val mutePi = PendingIntent.getService(
                this,
                1,
                Intent(this, DaakiaMeetingService::class.java).apply { action = ACTION_TOGGLE_MUTE },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            builder.addAction(muteIcon, muteLabel, mutePi)
        }

        // End call — always visible
        val endPi = PendingIntent.getService(
            this,
            2,
            Intent(this, DaakiaMeetingService::class.java).apply { action = ACTION_END_CALL },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        builder.addAction(android.R.drawable.ic_menu_close_clear_cancel, "End Call", endPi)

        return builder.build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Meeting",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Active meeting notification"
                setSound(null, null)
                enableVibration(false)
            }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

}
