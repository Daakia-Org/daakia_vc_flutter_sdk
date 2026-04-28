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
        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"

        fun start(context: Context, title: String, text: String) {
            val intent = Intent(context, DaakiaMeetingService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_TEXT, text)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, DaakiaMeetingService::class.java))
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val title = intent.getStringExtra(EXTRA_TITLE) ?: "Meeting"
                val text = intent.getStringExtra(EXTRA_TEXT) ?: "Tap to return to the meeting"
                startMeetingForeground(title, text)
            }
            ACTION_STOP -> stopSelf()
        }
        return START_STICKY
    }

    private fun startMeetingForeground(title: String, text: String) {
        createNotificationChannel()

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val iconId = resources.getIdentifier("ic_notification", "drawable", packageName)
            .takeIf { it != 0 } ?: android.R.drawable.ic_menu_call

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(iconId)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .build()

        // Use MEDIA_PLAYBACK type — appropriate for live A/V sessions, no runtime
        // permission pre-check required (unlike microphone/camera types on API 34+).
        try {
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                notification,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
                else
                    0
            )
        } catch (e: Exception) {
            Log.w(TAG, "startForeground failed, running without foreground promotion: $e")
        }
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

    override fun onDestroy() {
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }
}
