package com.proxiplay.proxiplay

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity: FlutterActivity() {
	override fun onCreate(savedInstanceState: Bundle?) {
		super.onCreate(savedInstanceState)
		createDefaultNotificationChannel()
	}

	private fun createDefaultNotificationChannel() {
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
			val channelId = "default_notification_channel"
			val channelName = "Notifications"
			val channelDescription = "App notifications"
			val importance = NotificationManager.IMPORTANCE_DEFAULT

			val channel = NotificationChannel(channelId, channelName, importance)
			channel.description = channelDescription

			val manager = getSystemService(NotificationManager::class.java)
			manager?.createNotificationChannel(channel)
		}
	}
}
