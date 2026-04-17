package com.yueto.yuelink

import android.util.Log
import io.flutter.app.FlutterApplication
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Pre-warm a single shared FlutterEngine at process start so the Quick
 * Settings tile can toggle the VPN headlessly — without launching
 * MainActivity. The same engine is reused by:
 *
 *   - MainActivity (provideFlutterEngine override) — UI attaches to it
 *   - ProxyTileService — invokes a MethodChannel directly on it
 *
 * Only one engine in the process means only one CoreManager instance and
 * one set of FFI bindings on libclash.so. Two engines would race on the
 * Go core's single mutex and on the shared homeDir / config.yaml path.
 *
 * The engine survives MainActivity destruction because Application holds
 * a strong reference via FlutterEngineCache. It only goes away when the
 * OS kills the process (which also stops the VPN cleanly via the
 * lifecycle observer in main.dart).
 *
 * On first cold start triggered by the tile, the engine takes ~500ms to
 * 1s to initialize Dart. ProxyTileService writes a `pending_toggle` flag
 * to SharedPreferences; Dart checks it after registering the MethodChannel
 * handler and applies the queued toggle, so the click is never lost.
 */
class MainApplication : FlutterApplication() {

    companion object {
        const val SHARED_ENGINE_ID = "yuelink_shared_engine"
        private const val TAG = "YueLinkApp"
    }

    override fun onCreate() {
        super.onCreate()
        installCrashHandler()
        prewarmSharedEngine()
    }

    /**
     * Install a process-wide uncaught-exception handler. Without this, any
     * Kotlin exception on a non-main thread (e.g. a callback in
     * YueLinkVpnService, a PackageManager query, a SharedPreferences commit
     * race) kills the app process with no trace beyond logcat — which most
     * users can't capture.
     *
     * We append the stack trace to `filesDir/crash.log` (the same file the
     * Dart-side ErrorLogger writes to, so `LogExportService` and the
     * Settings → Export Diagnostics flow pick it up automatically), then
     * chain to the system's default handler so Android still shows its
     * "YueLink has stopped" dialog and the process dies normally.
     */
    private fun installCrashHandler() {
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                val sw = StringWriter()
                throwable.printStackTrace(PrintWriter(sw))
                val timestamp = SimpleDateFormat(
                    "yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.US
                ).format(Date())
                val entry = buildString {
                    append("[$timestamp]\n")
                    append("[Android/${thread.name}] ")
                    append(throwable.javaClass.name)
                    append(": ").append(throwable.message ?: "").append("\n")
                    append(sw.toString()).append("\n\n")
                }
                File(filesDir, "crash.log").appendText(entry)
            } catch (_: Throwable) {
                // If logging itself fails, let the original crash propagate
                // unadorned — don't mask the root cause.
            }
            // Preserve the system's crash dialog behaviour.
            previous?.uncaughtException(thread, throwable)
        }
    }

    private fun prewarmSharedEngine() {
        try {
            val cache = FlutterEngineCache.getInstance()
            if (cache.get(SHARED_ENGINE_ID) != null) return
            val engine = FlutterEngine(this)
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault()
            )
            cache.put(SHARED_ENGINE_ID, engine)
            Log.i(TAG, "shared FlutterEngine pre-warmed")
        } catch (e: Throwable) {
            // Don't crash the app — if pre-warm fails, MainActivity will
            // create its own engine on first launch as the fallback path.
            Log.e(TAG, "shared FlutterEngine pre-warm failed", e)
        }
    }
}
