package com.example.starttooler_mobile

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * D04 §3.1.1 + D06 §六：局域网 UDP 发现需要 MulticastLock。
 *
 * Android 9+（API 28+）普通 [java.net.DatagramSocket] 在前台监听时也经常
 * 收不到 255.255.255.255 广播包——必须先 acquire 一个 MulticastLock。
 *
 * MethodChannel: "starttooler/multicast_lock"
 *   acquire() -> Boolean  是否拿到锁
 *   release() -> Unit
 */
class MainActivity : FlutterActivity() {
    private val channelName = "starttooler/multicast_lock"

    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "acquire" -> {
                    try {
                        val lock = ensureLock()
                        if (!lock.isHeld) lock.acquire()
                        result.success(lock.isHeld)
                    } catch (e: Exception) {
                        result.error("MULTICAST_LOCK_ACQUIRE_FAILED", e.message, null)
                    }
                }
                "release" -> {
                    try {
                        multicastLock?.let {
                            if (it.isHeld) it.release()
                        }
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("MULTICAST_LOCK_RELEASE_FAILED", e.message, null)
                    }
                }
                else -> result.error("UNKNOWN_METHOD", "Unknown ${call.method}", null)
            }
        }
    }

    private fun ensureLock(): WifiManager.MulticastLock {
        if (multicastLock == null) {
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE)
                as WifiManager
            multicastLock = wifi.createMulticastLock("starttooler_udp")
                .apply { setReferenceCounted(true) }
        }
        return multicastLock!!
    }

    override fun onDestroy() {
        multicastLock?.let {
            if (it.isHeld) it.release()
        }
        multicastLock = null
        super.onDestroy()
    }
}