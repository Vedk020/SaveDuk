package com.example.saveduk

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class MediaNotificationService : Service() {
    companion object {
        const val CHANNEL_ID = "saveduk_media"
        const val NOTIFICATION_ID = 1002

        const val ACTION_START = "com.example.saveduk.MEDIA_START"
        const val ACTION_UPDATE = "com.example.saveduk.MEDIA_UPDATE"
        const val ACTION_STOP = "com.example.saveduk.MEDIA_STOP"

        const val ACTION_PLAY_PAUSE = "com.example.saveduk.ACTION_PLAY_PAUSE"
        const val ACTION_REWIND = "com.example.saveduk.ACTION_REWIND"
        const val ACTION_FORWARD = "com.example.saveduk.ACTION_FORWARD"

        var onActionCallback: ((String) -> Unit)? = null
    }

    private var currentTitle: String = "SaveDuk Music"
    private var currentArtist: String = "Streaming"
    private var isPlaying: Boolean = false

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START, ACTION_UPDATE -> {
                currentTitle = intent.getStringExtra("title") ?: currentTitle
                currentArtist = intent.getStringExtra("artist") ?: currentArtist
                isPlaying = intent.getBooleanExtra("isPlaying", false)

                val notification = buildNotification()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    startForeground(
                        NOTIFICATION_ID,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
                    )
                } else {
                    startForeground(NOTIFICATION_ID, notification)
                }
            }
            ACTION_PLAY_PAUSE -> {
                onActionCallback?.invoke("play_pause")
            }
            ACTION_REWIND -> {
                onActionCallback?.invoke("rewind")
            }
            ACTION_FORWARD -> {
                onActionCallback?.invoke("forward")
            }
            ACTION_STOP -> {
                onActionCallback?.invoke("stop")
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "SaveDuk Media Playback",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Shows lock screen and notification media controls"
            setShowBadge(false)
        }
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        // Tap to open app
        val contentIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val contentPending = PendingIntent.getActivity(
            this, 0, contentIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Action PendingIntents
        val rewindIntent = Intent(this, MediaNotificationService::class.java).apply { action = ACTION_REWIND }
        val rewindPending = PendingIntent.getService(
            this, 1, rewindIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val playPauseIntent = Intent(this, MediaNotificationService::class.java).apply { action = ACTION_PLAY_PAUSE }
        val playPausePending = PendingIntent.getService(
            this, 2, playPauseIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val forwardIntent = Intent(this, MediaNotificationService::class.java).apply { action = ACTION_FORWARD }
        val forwardPending = PendingIntent.getService(
            this, 3, forwardIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val stopIntent = Intent(this, MediaNotificationService::class.java).apply { action = ACTION_STOP }
        val stopPending = PendingIntent.getService(
            this, 4, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val playPauseIcon = if (isPlaying) {
            android.R.drawable.ic_media_pause
        } else {
            android.R.drawable.ic_media_play
        }
        val playPauseTitle = if (isPlaying) "Pause" else "Play"

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(currentTitle)
            .setContentText(currentArtist)
            .setContentIntent(contentPending)
            .setOngoing(isPlaying)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .addAction(android.R.drawable.ic_media_rew, "-10s", rewindPending)
            .addAction(playPauseIcon, playPauseTitle, playPausePending)
            .addAction(android.R.drawable.ic_media_ff, "+10s", forwardPending)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Close", stopPending)
            .build()
    }
}
