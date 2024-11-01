package com.jorin.audio_live_stream

import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.InetAddress
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import android.content.Intent
import android.os.Build

class MainActivity: FlutterActivity() {
    private val CHANNEL_HOSTNAME = "com.jorin.audio_live_stream/hostname"
    private val CHANNEL_SERVICE = "com.jorin.audio_live_stream/service"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_HOSTNAME).setMethodCallHandler { call, result ->
            if (call.method == "getHostName") {
                GlobalScope.launch(Dispatchers.Main) {
                    val hostname = getHostName()
                    if (hostname != null) {
                        result.success(hostname)
                    } else {
                        result.error("UNAVAILABLE", "Hostname not available.", null)
                    }
                }
            } else {
                result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_SERVICE).setMethodCallHandler { call, result ->
            when (call.method) {
                "startAudioStreamingService" -> {
                    startAudioStreamingService()
                    result.success(null)
                }
                "stopAudioStreamingService" -> {
                    stopAudioStreamingService()
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private suspend fun getHostName(): String? = withContext(Dispatchers.IO) {
        return@withContext try {
            InetAddress.getLocalHost().hostName
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    private fun startAudioStreamingService() {
        val serviceIntent = Intent(this, AudioStreamingService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }
    }

    private fun stopAudioStreamingService() {
        val serviceIntent = Intent(this, AudioStreamingService::class.java)
        stopService(serviceIntent)
    }
}
