package com.zhoujh.solar.data

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit

class HAException(val code: Int, message: String) : Exception(message) {
    companion object {
        fun describe(e: Exception): String = when (e) {
            is HAException -> e.message ?: "请求失败"
            else -> "网络异常，请检查 HA 地址和网络"
        }
    }
}

data class Config(val url: String, val token: String) {
    val valid: Boolean get() = url.isNotBlank() && token.isNotBlank()
}

object Prefs {
    private const val NAME = "solar_config"
    fun load(ctx: Context): Config {
        val sp = ctx.getSharedPreferences(NAME, Context.MODE_PRIVATE)
        return Config(sp.getString("url", "") ?: "", sp.getString("token", "") ?: "")
    }
    fun save(ctx: Context, url: String, token: String) {
        ctx.getSharedPreferences(NAME, Context.MODE_PRIVATE)
            .edit().putString("url", url).putString("token", token).apply()
    }
}

class HAClient(private val cfg: Config) {
    private val client = OkHttpClient.Builder()
        .connectTimeout(6, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .build()

    private fun base(): String {
        var b = cfg.url.trim()
        if (!b.startsWith("http://") && !b.startsWith("https://")) b = "http://$b"
        return b.trimEnd('/')
    }

    private fun post(url: String, body: String): String = withContext(Dispatchers.IO) {
        val req = Request.Builder()
            .url(url)
            .addHeader("Authorization", "Bearer ${cfg.token.trim()}")
            .addHeader("Content-Type", "application/json")
            .post(body.toRequestBody("application/json".toMediaType()))
            .build()
        try {
            client.newCall(req).execute().use { resp ->
                val text = resp.body?.string() ?: ""
                when {
                    resp.code == 401 -> throw HAException(401, "令牌无效或已过期（HTTP 401）")
                    !resp.isSuccessful -> throw HAException(resp.code, "HA 返回 HTTP ${resp.code}")
                    text.isBlank() -> throw HAException(-1, "HA 返回空响应")
                }
                text
            }
        } catch (e: HAException) {
            throw e
        } catch (e: Exception) {
            throw HAException(-2, "无法连接 HA：${e.message ?: "网络异常"}")
        }
    }

    suspend fun fetchSolar(): SolarData {
        val body = JSONObject().put("template", SolarConfig.template()).toString()
        val text = post("${base()}/api/template", body)
        val parsed = SolarData.parse(text)
        if (parsed.isEmptyReading) throw HAException(-3, "读数异常：${text.take(60)}")

        // 降雨预报：天气实体 forecast 属性已废弃，走 get_forecasts 服务，缓存 10 分钟
        if (System.currentTimeMillis() - RainCache.last > 600_000) {
            try {
                RainCache.conditions = fetchHourlyConditions()
                RainCache.last = System.currentTimeMillis()
            } catch (_: Exception) { /* 预报失败不阻塞主数据 */ }
        }
        return parsed.copy(forecastConditions = RainCache.conditions)
    }

    private suspend fun fetchHourlyConditions(): String {
        val body = JSONObject()
            .put("entity_id", "weather.forecast_wo_de_jia")
            .put("type", "hourly")
            .toString()
        val text = post("${base()}/api/services/weather/get_forecasts", body)
        val root = JSONObject(text)
        val arr = root.optJSONObject("service_response")
            ?.optJSONObject("weather.forecast_wo_de_jia")
            ?.optJSONArray("forecast") ?: return ""
        val out = mutableListOf<String>()
        for (i in 0 until minOf(4, arr.length())) {
            out.add(arr.optJSONObject(i)?.optString("condition", "") ?: "")
        }
        return out.filter { it.isNotEmpty() }.joinToString(",")
    }

    suspend fun fetchDetail(kind: DeviceKind): DeviceDetail {
        val fields = SolarConfig.detailIds[kind] ?: return DeviceDetail(emptyList())
        val tpl = fields.joinToString("|") { "{{ states('${it.first}) }}" }
        val body = JSONObject().put("template", tpl).toString()
        val text = post("${base()}/api/template", body)
        val parts = text.split("|").map { it.trim() }
        val sections = mutableListOf<DetailSection>()
        val rows = mutableListOf<DetailField>()
        fields.forEachIndexed { i, (id, label) ->
            val raw = parts.getOrNull(i) ?: "--"
            val v = if (raw.isEmpty() || raw == "unavailable" || raw == "unknown") "--" else fmt(id, raw)
            rows.add(DetailField(label, v))
        }
        sections.add(DetailSection(kind.title, rows.toList()))
        return DeviceDetail(sections)
    }

    private fun fmt(id: String, raw: String): String = when {
        id.contains("temperature") -> "$raw °C"
        id.contains("soc") -> "$raw %"
        id.contains("energy") -> "$raw kWh"
        id.contains("power") || id.contains("current") || id.contains("voltage") -> "$raw ${unitOf(id)}"
        else -> raw
    }

    private fun unitOf(id: String) = when {
        id.contains("current") -> "A"
        id.contains("voltage") -> "V"
        else -> "W"
    }
}

object RainCache {
    var conditions: String = ""
    var last: Long = 0L
}
