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
import android.os.Handler
import android.os.Looper

class MainActivity: FlutterActivity() {
    private val CHANNEL_HOSTNAME = "com.jorin.audio_live_stream/hostname"
    private val CHANNEL_SERVICE = "com.jorin.audio_live_stream/service"
    private val CHANNEL_APP_CONTROL = "com.jorin.audio_live_stream/app_control"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_HOSTNAME).setMethodCallHandler { call, result ->
            print("Method call: ${call.method}")
            when (call.method) {
                "getHostName" -> {
                    GlobalScope.launch(Dispatchers.Main) {
                        val hostname = getHostName()
                        if (hostname != null) {
                            result.success(hostname)
                        } else {
                            result.error("UNAVAILABLE", "Hostname not available.", null)
                        }
                    }
                }
                else -> {
                    result.notImplemented()
                }
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_APP_CONTROL).setMethodCallHandler { call, result ->
            when (call.method) {
                "restartApp" -> {
                    val pm = context.packageManager
                    val intent = pm.getLaunchIntentForPackage(context.packageName)?.apply {
                        addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        addFlags(Intent.FLAG_ACTIVITY_CLEAR_TASK)
                    }
                    
                    Handler(Looper.getMainLooper()).postDelayed({
                        finishAffinity() // Close all activities
                        context.startActivity(intent)
                        android.os.Process.killProcess(android.os.Process.myPid())
                    }, 100)
                    
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
