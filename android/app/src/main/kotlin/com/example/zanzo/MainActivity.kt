package com.example.zanzo

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "job_alerts",
                "Job Alerts",
                NotificationManager.IMPORTANCE_HIGH,
            )
            channel.description = "New job offers and status updates"
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }
    }
}
