package com.proxiplay.proxiplay

import android.content.ContentValues
import android.content.Intent
import android.app.NotificationChannel
import android.app.NotificationManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
	companion object {
		private const val MEDIA_CHANNEL = "proxiplay/media"
	}

	override fun onCreate(savedInstanceState: Bundle?) {
		super.onCreate(savedInstanceState)
		Log.d("PROXIPLAY_DEEPLINK", "onCreate data=" + intent?.dataString)
		createDefaultNotificationChannel()
	}

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		forwardDeepLinkToFlutter(intent)
		MethodChannel(
			flutterEngine.dartExecutor.binaryMessenger,
			MEDIA_CHANNEL,
		).setMethodCallHandler { call, result ->
			when (call.method) {
				"saveImageToGallery" -> {
					val bytes = call.argument<ByteArray>("bytes")
					val fileName = call.argument<String>("fileName")
					if (bytes == null || bytes.isEmpty() || fileName.isNullOrBlank()) {
						result.error("invalid_args", "Missing image bytes or file name.", null)
						return@setMethodCallHandler
					}

					try {
						val savedUri = saveImageToGallery(bytes, fileName)
						if (savedUri == null) {
							result.error("save_failed", "Unable to save image to gallery.", null)
						} else {
							result.success(savedUri.toString())
						}
					} catch (error: Exception) {
						Log.e("PROXIPLAY_MEDIA", "saveImageToGallery failed", error)
						result.error("save_failed", error.message, null)
					}
				}
				else -> result.notImplemented()
			}
		}
	}

	override fun onNewIntent(intent: Intent) {
		super.onNewIntent(intent)
		setIntent(intent)
		Log.d("PROXIPLAY_DEEPLINK", "onNewIntent data=" + intent.dataString)
		forwardDeepLinkToFlutter(intent)
	}

	private fun forwardDeepLinkToFlutter(intent: Intent?) {
		val data = intent?.data ?: return
		val route = when {
			data.scheme == "proxiplay" && data.host == "game" -> {
				val gameId = data.pathSegments.firstOrNull().orEmpty()
				if (gameId.isEmpty()) {
					null
				} else {
					"/game/$gameId"
				}
			}
			else -> {
				val path = data.encodedPath ?: return
				buildString {
					append(path)
					data.encodedQuery?.takeIf { it.isNotEmpty() }?.let {
						append('?')
						append(it)
					}
					data.encodedFragment?.takeIf { it.isNotEmpty() }?.let {
						append('#')
						append(it)
					}
				}
			}
		}

		if (route.isNullOrEmpty()) {
			return
		}

		Log.d("PROXIPLAY_DEEPLINK", "forwardRoute=" + route)
		flutterEngine?.navigationChannel?.pushRouteInformation(route)
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

	private fun saveImageToGallery(bytes: ByteArray, fileName: String): Uri? {
		val resolver = applicationContext.contentResolver
		val contentValues = ContentValues().apply {
			put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
			put(MediaStore.MediaColumns.MIME_TYPE, "image/png")
			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
				put(MediaStore.MediaColumns.RELATIVE_PATH, "Pictures/Proxiplay")
				put(MediaStore.MediaColumns.IS_PENDING, 1)
			}
		}

		val collection = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
		val itemUri = resolver.insert(collection, contentValues) ?: return null

		try {
			resolver.openOutputStream(itemUri)?.use { stream ->
				stream.write(bytes)
				stream.flush()
			} ?: throw IllegalStateException("Unable to open MediaStore output stream.")

			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
				val completedValues = ContentValues().apply {
					put(MediaStore.MediaColumns.IS_PENDING, 0)
				}
				resolver.update(itemUri, completedValues, null, null)
			}

			return itemUri
		} catch (error: Exception) {
			resolver.delete(itemUri, null, null)
			throw error
		}
	}
}
