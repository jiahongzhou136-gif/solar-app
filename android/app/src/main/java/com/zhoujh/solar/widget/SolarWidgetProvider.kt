package com.zhoujh.solar.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews
import com.zhoujh.solar.R
import com.zhoujh.solar.data.Config
import com.zhoujh.solar.data.Prefs
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.util.concurrent.TimeUnit
import kotlin.math.abs

class SolarWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val pending = goAsync()
        Thread {
            try {
                updateAll(context, manager, ids)
            } finally {
                pending.finish()
            }
        }.start()
    }

    companion object {
        private val client = OkHttpClient.Builder()
            .connectTimeout(6, TimeUnit.SECONDS)
            .readTimeout(10, TimeUnit.SECONDS)
            .build()

        /** App 内保存配置后调用，立即刷新小组件 */
        fun refreshNow(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                android.content.ComponentName(context, SolarWidgetProvider::class.java)
            )
            updateAll(context, manager, ids)
        }

        private fun updateAll(context: Context, manager: AppWidgetManager, ids: IntArray) {
            val res = context.resources
            fun rid(name: String) = res.getIdentifier(name, "id", context.packageName)

            val views = RemoteViews(context.packageName, R.layout.widget_solar)
            val cfg = Prefs.load(context)

            if (!cfg.valid) {
                for (i in 1..8) views.setTextViewText(rid("v$i"), "--")
                ids.forEach { manager.updateAppWidget(it, views) }
                return
            }

            val d = fetch(cfg)
            val values = linkedMapOf(
                1 to fmtW(d["pv"]), 2 to fmtK(d["daily"]), 3 to fmtW(d["load"]),
                4 to fmtP(d["soc"]), 5 to fmtW(d["charge"]), 6 to fmtW(d["discharge"]),
                7 to fmtK(d["dailyCharge"]), 8 to fmtW(d["grid"])
            )
            for ((idx, v) in values) views.setTextViewText(rid("v$idx"), v)
            ids.forEach { manager.updateAppWidget(it, views) }
        }

        private fun fetch(cfg: Config): Map<String, Double?> {
            val base = cfg.url.trim().let {
                if (!it.startsWith("http")) "http://$it" else it
            }.trimEnd('/')
            val ids = mapOf(
                "pv" to "sensor.guang_fu_ben_di_wang_guan_pv1_power",
                "load" to "sensor.guang_fu_ben_di_wang_guan_load_power",
                "soc" to "sensor.guang_fu_ben_di_wang_guan_bms_soc",
                "daily" to "sensor.guang_fu_ben_di_wang_guan_daily_pv_energy",
                "charge" to "sensor.guang_fu_ben_di_wang_guan_battery_charge_power",
                "discharge" to "sensor.guang_fu_ben_di_wang_guan_battery_discharge_power",
                "dailyCharge" to "sensor.guang_fu_ben_di_wang_guan_daily_battery_charge_energy",
                "grid" to "sensor.guang_fu_ben_di_wang_guan_grid_power_raw"
            )
            val out = mutableMapOf<String, Double?>()
            for ((key, entity) in ids) {
                try {
                    val req = Request.Builder()
                        .url("$base/api/states/$entity")
                        .addHeader("Authorization", "Bearer ${cfg.token.trim()}")
                        .build()
                    client.newCall(req).execute().use { resp ->
                        if (!resp.isSuccessful) { out[key] = null; return@use }
                        val obj = JSONObject(resp.body?.string() ?: "{}")
                        val v = obj.optString("state", "").toDoubleOrNull()
                        out[key] = when (key) {
                            "soc" -> if (v != null && v in 0.0..100.0) v else null
                            "daily", "dailyCharge" -> if (v != null && v in 0.0..1_000_000.0) v else null
                            else -> if (v != null && abs(v) <= 30000.0) v else null
                        }
                    }
                } catch (_: Exception) {
                    out[key] = null
                }
            }
            return out
        }

        private fun fmtW(v: Double?): String = if (v == null) "--" else "${v.toInt()} W"
        private fun fmtK(v: Double?): String = if (v == null) "--" else "%.2f kWh".format(v)
        private fun fmtP(v: Double?): String = if (v == null) "--" else "${v.toInt()}%"
    }
}
