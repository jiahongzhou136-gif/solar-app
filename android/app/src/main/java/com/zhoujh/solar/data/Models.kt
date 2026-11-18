package com.zhoujh.solar.data

// 与 iOS SolarData 1:1 对齐的模型与解析
object Sanity {
    fun watt(v: Double): Double? = if (Math.abs(v) <= 30000.0) v else null
    fun volt(v: Double): Double? = if (v in 0.0..1000.0) v else null
    fun amp(v: Double): Double? = if (Math.abs(v) <= 500.0) v else null
    fun pct(v: Double): Double? = if (v in 0.0..100.0) v else null
    fun kwh(v: Double): Double? = if (v in 0.0..1_000_000.0) v else null
}

enum class WeatherKind(val label: String, val imageName: String) {
    SUNNY("晴", "weather_sunny"),
    CLOUDY("多云", "weather_cloudy"),
    RAIN("雨", "weather_rain");

    companion object {
        fun from(raw: String): WeatherKind = when {
            raw.contains("rain") -> RAIN
            raw.contains("cloudy") || raw.contains("partly") || raw.contains("overcast") -> CLOUDY
            else -> SUNNY
        }
    }
}

enum class DeviceKind(val key: String, val title: String) {
    PV1("pv1", "PV1"),
    INVERTER("inverter", "逆变器"),
    BATTERY("battery", "储能电池"),
    GRID("grid", "市电"),
    LOAD("load", "住宅负载");

    companion object {
        fun byKey(k: String) = entries.firstOrNull { it.key == k }
    }
}

data class SolarData(
    val pv1: Double?, val pv1Voltage: Double?, val pv1Current: Double?,
    val pvTotal: Double?, val load: Double?,
    val soc: Double?, val charge: Double?, val discharge: Double?, val grid: Double?,
    val dailyCharge: Double?, val dailyDischarge: Double?, val dailyPv: Double?, val totalPv: Double?,
    val forecastToday: Double?, val forecastRemaining: Double?, val forecastTomorrow: Double?,
    val weatherRaw: String, val inverterTemp: Double?, val inverterStatus: String,
    val warningCode: String, val sunState: String, val forecastConditions: String,
    val rawPreview: String, val updatedAt: Long
) {
    val isNight: Boolean get() = sunState.contains("below", true) || sunState.contains("night", true)
    val weather: WeatherKind get() = WeatherKind.from(weatherRaw)
    val batteryPower: Double? get() = charge?.let { c -> discharge?.let { d -> c - d } } ?: charge ?: discharge?.let { -it }

    // 与 HA _derivedState 一致：互斥正值判定
    val charging: Boolean get() = (charge ?: 0.0) > 0 && (discharge ?: 0.0) <= 0
    val discharging: Boolean get() = (discharge ?: 0.0) > 0 && (charge ?: 0.0) <= 0

    // 「预计多久有雨」：未来 4 小时 condition 串
    val rainSoonText: String? get() {
        val items = forecastConditions.split(",").map { it.trim().lowercase() }.filter { it.isNotEmpty() }
        if (items.isEmpty()) return null
        val rainy = setOf("rain", "rainy", "pouring", "hail", "thunder", "lightning")
        val first = items.indexOfFirst { it in rainy }
        if (first < 0) {
            return if (items.all { it.contains("clear") || it.contains("sunny") })
                "${items.size} 小时内无降雨" else null
        }
        return if (first == 0) "即将有雨" else "约 $first 小时后有雨"
    }

    val isEmptyReading: Boolean
        get() = pv1 == null && pvTotal == null && load == null && soc == null &&
                charge == null && discharge == null && grid == null

    companion object {
        fun empty() = SolarData(
            null, null, null, null, null, null, null, null, null,
            null, null, null, null, null, null, null,
            "", null, "", "", "", "", "", 0L
        )

        fun parse(raw: String): SolarData {
            val p = raw.split("|").map { it.trim() }
            fun s(i: Int) = p.getOrNull(i) ?: ""
            fun d(i: Int): Double? = s(i).toDoubleOrNull()
            fun meter(i: Int, kind: String): Double? {
                val v = d(i) ?: return null
                return when (kind) {
                    "W" -> Sanity.watt(v); "V" -> Sanity.volt(v); "A" -> Sanity.amp(v)
                    "%" -> Sanity.pct(v); "°C" -> if (v in -40.0..150.0) v else null
                    "kWh" -> Sanity.kwh(v); else -> v
                }
            }
            val dt = System.currentTimeMillis()
            return SolarData(
                pv1 = meter(0, "W"), pv1Voltage = meter(1, "V"), pv1Current = meter(2, "A"),
                pvTotal = meter(3, "W"), load = meter(4, "W"),
                soc = meter(5, "%"), charge = meter(6, "W"), discharge = meter(7, "W"),
                grid = meter(8, "W"),
                dailyCharge = meter(9, "kWh"), dailyDischarge = meter(10, "kWh"),
                dailyPv = meter(11, "kWh"), totalPv = meter(12, "kWh"),
                forecastToday = meter(13, "kWh"), forecastRemaining = meter(14, "kWh"),
                forecastTomorrow = meter(15, "kWh"),
                weatherRaw = s(16), inverterTemp = meter(17, "°C"),
                inverterStatus = s(18), warningCode = s(19), sunState = s(20),
                forecastConditions = s(21),
                rawPreview = if (raw.length > 160) raw.substring(0, 160) else raw,
                updatedAt = dt
            )
        }
    }
}

data class DetailField(val label: String, val value: String)
data class DetailSection(val title: String, val fields: List<DetailField>)
data class DeviceDetail(val sections: List<DetailSection>)

object SolarConfig {
    // 实体 id 与 iOS mainEntities 一致；第 22 项为降雨预报（Android 端走 get_forecasts 服务，不占模板位）
    val ids = listOf(
        "sensor.guang_fu_ben_di_wang_guan_pv1_power",
        "sensor.guang_fu_ben_di_wang_guan_pv1_voltage",
        "sensor.guang_fu_ben_di_wang_guan_pv1_current",
        "sensor.guang_fu_ben_di_wang_guan_pv_total_power",
        "sensor.guang_fu_ben_di_wang_guan_load_power",
        "sensor.guang_fu_ben_di_wang_guan_bms_soc",
        "sensor.guang_fu_ben_di_wang_guan_battery_charge_power",
        "sensor.guang_fu_ben_di_wang_guan_battery_discharge_power",
        "sensor.guang_fu_ben_di_wang_guan_grid_power_raw",
        "sensor.guang_fu_ben_di_wang_guan_daily_battery_charge_energy",
        "sensor.guang_fu_ben_di_wang_guan_daily_battery_discharge_energy",
        "sensor.guang_fu_ben_di_wang_guan_daily_pv_energy",
        "sensor.guang_fu_ben_di_wang_guan_total_pv_energy",
        "sensor.solcast_pv_forecast_forecast_today",
        "sensor.solcast_pv_forecast_forecast_remaining_today",
        "sensor.solcast_pv_forecast_forecast_tomorrow",
        "weather.forecast_wo_de_jia",
        "sensor.guang_fu_ben_di_wang_guan_inverter_temperature",
        "sensor.guang_fu_ben_di_wang_guan_inverter_status_raw",
        "sensor.guang_fu_ben_di_wang_guan_inverter_warning_code_raw",
        "sun.sun"
    )

    fun template() = ids.joinToString("|") { "{{ states('$it') }}" }

    // 详情页字段（精简自 iOS groups）
    val detailIds: Map<DeviceKind, List<Pair<String, String>>> = mapOf(
        DeviceKind.PV1 to listOf(
            "sensor.guang_fu_ben_di_wang_guan_pv1_power" to "输出功率",
            "sensor.guang_fu_ben_di_wang_guan_pv1_voltage" to "PV1 电压",
            "sensor.guang_fu_ben_di_wang_guan_pv1_current" to "PV1 电流",
            "sensor.guang_fu_ben_di_wang_guan_daily_pv_energy" to "今日发电",
            "sensor.guang_fu_ben_di_wang_guan_total_pv_energy" to "累计发电"
        ),
        DeviceKind.INVERTER to listOf(
            "sensor.guang_fu_ben_di_wang_guan_inverter_temperature" to "机内温度",
            "sensor.guang_fu_ben_di_wang_guan_inverter_status_raw" to "运行状态",
            "sensor.guang_fu_ben_di_wang_guan_inverter_warning_code_raw" to "告警码",
            "sensor.guang_fu_ben_di_wang_guan_load_power" to "输出功率"
        ),
        DeviceKind.BATTERY to listOf(
            "sensor.guang_fu_ben_di_wang_guan_bms_soc" to "SOC",
            "sensor.guang_fu_ben_di_wang_guan_battery_charge_power" to "充电功率",
            "sensor.guang_fu_ben_di_wang_guan_battery_discharge_power" to "放电功率",
            "sensor.guang_fu_ben_di_wang_guan_daily_battery_charge_energy" to "日充电",
            "sensor.guang_fu_ben_di_wang_guan_daily_battery_discharge_energy" to "日放电"
        ),
        DeviceKind.GRID to listOf(
            "sensor.guang_fu_ben_di_wang_guan_grid_power_raw" to "电网功率"
        ),
        DeviceKind.LOAD to listOf(
            "sensor.guang_fu_ben_di_wang_guan_load_power" to "负载功率"
        )
    )
}
