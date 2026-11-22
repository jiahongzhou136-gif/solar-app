package com.zhoujh.solar.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.zhoujh.solar.R
import com.zhoujh.solar.data.*
import kotlinx.coroutines.delay
import kotlin.math.abs
import kotlin.math.floor

fun fmtW(v: Double?): String = if (v == null) "--" else "${floor(v).toInt()} W"
fun fmtKwh(v: Double?, digits: Int = 2): String =
    if (v == null) "--" else String.format("%.${digits}f kWh", v)
fun fmtPct(v: Double?): String = if (v == null) "--" else "${floor(v).toInt()}%"

/** 全局能流相位（MainScreen 用 withFrameNanos 驱动，120Hz 自适应） */
var heroPhase by mutableFloatStateOf(0f)
var heroSeconds by mutableFloatStateOf(0f)

@Composable
fun MainScreen(
    config: Config,
    onOpenSettings: () -> Unit,
    onOpenDevice: (DeviceKind) -> Unit
) {
    var data by remember { mutableStateOf(SolarData.empty()) }
    var error by remember { mutableStateOf<String?>(null) }
    var failures by remember { mutableIntStateOf(0) }

    // 能流相位：withFrameNanos 按显示器刷新率驱动（S24U 120Hz 自动适配）
    LaunchedEffect(Unit) {
        val start = withFrameNanos { it }
        while (true) {
            withFrameNanos { now ->
                heroPhase = ((now - start) / 1_000_000_000f) * 90f
                heroSeconds = (now - start) / 1_000_000_000f
            }
        }
    }

    suspend fun refresh() {
        if (!config.valid) { error = null; return }
        try {
            data = HAClient(config).fetchSolar()
            error = null
            failures = 0
        } catch (e: Exception) {
            failures++
            error = HAException.describe(e)
            if (failures >= 3 && !data.isEmptyReading) data = SolarData.empty()
        }
    }

    LaunchedEffect(config) {
        while (true) {
            if (config.valid) refresh()
            delay(2000)
        }
    }

    Box(
        Modifier
            .fillMaxSize()
            .background(Color(0xFF0B1118))
    ) {
        WeatherBackdrop(data.weather, data.isNight)

        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 14.dp)
        ) {
            Spacer(Modifier.height(52.dp))
            Header(error, onOpenSettings)
            Spacer(Modifier.height(12.dp))

            LuminaHero(data)

            Spacer(Modifier.height(6.dp))
            ForecastBar(data)
            Spacer(Modifier.height(14.dp))

            Row(horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                DeviceCard(DeviceKind.PV1, data, Modifier.weight(1f)) { onOpenDevice(DeviceKind.PV1) }
                DeviceCard(DeviceKind.INVERTER, data, Modifier.weight(1f)) { onOpenDevice(DeviceKind.INVERTER) }
            }
            Spacer(Modifier.height(9.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                DeviceCard(DeviceKind.GRID, data, Modifier.weight(1f)) { onOpenDevice(DeviceKind.GRID) }
                DeviceCard(DeviceKind.LOAD, data, Modifier.weight(1f)) { onOpenDevice(DeviceKind.LOAD) }
            }
            Spacer(Modifier.height(9.dp))
            BatteryCard(data) { onOpenDevice(DeviceKind.BATTERY) }
            Spacer(Modifier.height(9.dp))
            EnergyCard(data)
            Spacer(Modifier.height(18.dp))
            Spacer(Modifier.navigationBarsPadding())
        }

        if (!config.valid) {
            ConfigHint(Modifier.align(Alignment.Center))
        }
    }
}

@Composable
private fun Header(error: String?, onOpenSettings: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text("光伏监控", color = TextMain, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            Text(
                error ?: "已连接 · 每 2 秒同步",
                color = if (error == null) TextMuted else Color(0xFFFFB4B4),
                fontSize = 10.sp, maxLines = 2, overflow = TextOverflow.Ellipsis
            )
        }
        TextButton(onClick = onOpenSettings) { Text("设置", color = TextMuted) }
    }
}

@Composable
private fun WeatherBackdrop(kind: WeatherKind, isNight: Boolean) {
    val name = if (isNight) "weather_night" else kind.imageName
    val ctx = LocalContext.current
    val resId = remember(name) {
        ctx.resources.getIdentifier(name, "drawable", ctx.packageName)
    }
    Box(Modifier.fillMaxSize()) {
        if (resId != 0) {
            Image(
                painterResource(resId),
                contentDescription = null,
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Crop
            )
        }
        Box(
            Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        listOf(Color(0x1A03182D), Color(0x5203182D), Color(0xDB02101F))
                    )
                )
        )
    }
}

private fun gridText(d: SolarData): String {
    val g = d.grid ?: return "--"
    return if (abs(g) < 50) "0 W" else fmtW(g)
}

private fun batteryText(d: SolarData): String {
    val charging = (d.charge ?: 0.0) > 0 && (d.discharge ?: 0.0) <= 0
    val discharging = (d.discharge ?: 0.0) > 0 && (d.charge ?: 0.0) <= 0
    if (charging) return "+" + fmtW(d.charge)
    if (discharging) return "-" + fmtW(d.discharge)
    return "0 W"
}

@Composable
private fun LuminaHero(data: SolarData) {
    val loadOn = (data.load ?: 0.0) > 20
    val gridOn = abs(data.grid ?: 0.0) > 20
    val gridRev = (data.grid ?: 0.0) < -20
    val battOn = (data.charge ?: 0.0) > 20 || (data.discharge ?: 0.0) > 20
    val battRev = data.discharging

    BoxWithConstraints(
        Modifier
            .fillMaxWidth()
            .aspectRatio(1110f / 905f)
    ) {
        val w = maxWidth
        val h = maxHeight
        Image(
            painterResource(R.drawable.lumina_entities),
            contentDescription = null,
            modifier = Modifier.fillMaxSize(),
            contentScale = ContentScale.FillBounds
        )
        FlowLayer(
            timeSec = heroSeconds,
            loadOn = loadOn, gridOn = gridOn, gridRev = gridRev,
            battOn = battOn, battRev = battRev,
            modifier = Modifier.fillMaxSize()
        )
        BuoyText("电网", gridText(data), w * 0.233f, h * 0.080f)
        BuoyText("光伏板", fmtW(data.pv1), w * 0.807f, h * 0.061f)
        LoadBubble(fmtW(data.load), w * 0.688f, h * 0.378f)
        BuoyText("发电机", "0 W", w * 0.488f, h * 0.934f)
        BuoyText("电池", batteryText(data), w * 0.873f, h * 0.874f)
    }
}

/** 普通浮标：无底色纯文字（白字 + 投影），对齐 iOS 9/12 */
@Composable
private fun BuoyText(title: String, value: String, cx: Dp, cy: Dp) {
    val sh = Shadow(Color(0x8C000000), Offset(0f, 1.5f), 2.5f)
    Column(
        Modifier
            .offset(x = cx - 45.dp, y = cy - 12.dp)
            .width(90.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            title, color = Color.White.copy(alpha = 0.92f), fontSize = 9.sp,
            fontWeight = FontWeight.SemiBold, maxLines = 1,
            style = TextStyle(shadow = sh)
        )
        Text(
            value, color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold,
            maxLines = 1, style = TextStyle(shadow = sh)
        )
    }
}

/** 离网负载：浅底圆角气泡（深色字），对齐 iOS */
@Composable
private fun LoadBubble(value: String, cx: Dp, cy: Dp) {
    Column(
        Modifier
            .offset(x = cx - 42.dp, y = cy - 14.dp)
            .width(84.dp)
            .background(Color(0xEBF1F4F7), RoundedCornerShape(7.dp))
            .padding(vertical = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text("离网负载", color = Color(0xFF4A555F), fontSize = 9.sp, maxLines = 1)
        Text(value, color = Color(0xFF1F2833), fontSize = 12.sp, fontWeight = FontWeight.Bold, maxLines = 1)
    }
}

@Composable
private fun ForecastBar(data: SolarData) {
    val parts = buildList {
        add(data.weather.label)
        data.rainSoonText?.let { add(it) }
        data.forecastTomorrow?.let { add("明日预计 ${fmtKwh(it)}") }
    }
    Column(Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 2.dp)) {
        Text(
            "今日预计 ${fmtKwh(data.forecastToday)} · 剩余 ${fmtKwh(data.forecastRemaining)}",
            color = TextMain, fontSize = 14.sp, fontWeight = FontWeight.Medium
        )
        Text(
            parts.joinToString(" · "),
            color = TextMuted, fontSize = 12.sp, maxLines = 2, overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
fun GlassCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier
            .background(
                Brush.linearGradient(listOf(CardTop, CardBot)),
                RoundedCornerShape(22.dp)
            )
            .border(
                0.8.dp,
                Brush.linearGradient(listOf(Color(0x4DFFFFFF), Color(0x1AFFFFFF))),
                RoundedCornerShape(22.dp)
            )
            .padding(13.dp),
        content = content
    )
}

@Composable
private fun DeviceCard(kind: DeviceKind, data: SolarData, modifier: Modifier, onClick: () -> Unit) {
    val (value, footnote) = summary(kind, data)
    GlassCard(
        modifier
            .height(132.dp)
            .clickable { onClick() }
    ) {
        Text(kind.title, color = TextMain.copy(alpha = 0.92f), fontSize = 11.sp)
        Spacer(Modifier.weight(1f))
        Text(value, color = TextMain, fontSize = 23.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(footnote, color = TextMuted, fontSize = 10.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

private fun summary(kind: DeviceKind, d: SolarData): Pair<String, String> = when (kind) {
    DeviceKind.PV1 -> fmtW(d.pv1) to "PV2 未接入"
    DeviceKind.INVERTER ->
        fmtW(d.load ?: d.pvTotal ?: d.pv1) to
                (d.inverterTemp?.let { "实时 · %.1f °C".format(it) } ?: "实时")
    DeviceKind.BATTERY ->
        if (d.charging) ("充电 ${fmtW(d.charge)}" to "能量流入")
        else if (data_discharging(d)) ("放电 ${fmtW(d.discharge)}" to "能量流出")
        else ("待机 0 W" to "待机")
    DeviceKind.GRID -> {
        val g = d.grid ?: 0.0
        val dir = if (abs(g) < 50) "正常" else if (g > 0) "取电" else "馈电"
        fmtW(d.grid) to "$dir · 市电${if (g > 0) "流入" else if (g < 0) "流出" else "待机"}"
    }
    DeviceKind.LOAD -> fmtW(d.load) to "当前用电"
}

private fun data_discharging(d: SolarData) = d.discharging

@Composable
private fun BatteryCard(data: SolarData, onClick: () -> Unit) {
    GlassCard(Modifier.fillMaxWidth().height(132.dp).clickable { onClick() }) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("储能电池", color = TextMain.copy(alpha = 0.92f), fontSize = 11.sp)
                Spacer(Modifier.height(6.dp))
                val headline =
                    if (data.charging) "充电 ${fmtW(data.charge)}"
                    else if (data.discharging) "放电 ${fmtW(data.discharge)}"
                    else "待机 0 W"
                Text(headline, color = TextMain, fontSize = 23.sp, fontWeight = FontWeight.Bold)
                Text(
                    if (data.charging) "能量流入" else if (data.discharging) "能量流出" else "待机",
                    color = TextMuted, fontSize = 10.sp
                )
            }
            Text(fmtPct(data.soc), color = Cyan, fontSize = 34.sp, fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
private fun EnergyCard(data: SolarData) {
    GlassCard(Modifier.fillMaxWidth()) {
        Text("今日能量", color = TextMain.copy(alpha = 0.92f), fontSize = 11.sp)
        Spacer(Modifier.height(10.dp))
        Row {
            EnergyItem("日充电", fmtKwh(data.dailyCharge), Modifier.weight(1f))
            EnergyItem("日放电", fmtKwh(data.dailyDischarge), Modifier.weight(1f))
        }
        Spacer(Modifier.height(10.dp))
        Row {
            EnergyItem("日发电", fmtKwh(data.dailyPv), Modifier.weight(1f))
            EnergyItem("累计发电", fmtKwh(data.totalPv, 1), Modifier.weight(1f))
        }
    }
}

@Composable
private fun EnergyItem(label: String, value: String, modifier: Modifier) {
    Column(modifier) {
        Text(label, color = TextMuted, fontSize = 10.sp)
        Text(value, color = TextMain, fontSize = 19.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun ConfigHint(modifier: Modifier = Modifier) {
    Card(modifier.padding(32.dp)) {
        Column(Modifier.padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text("还没有配置", color = TextMain, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(6.dp))
            Text("点击右上角「设置」填入 HA 地址和长期令牌", color = TextMuted, fontSize = 12.sp)
        }
    }
}
