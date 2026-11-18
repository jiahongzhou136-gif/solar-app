package com.zhoujh.solar.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.zhoujh.solar.data.Config
import com.zhoujh.solar.data.DeviceKind
import com.zhoujh.solar.data.HAClient
import com.zhoujh.solar.data.HAException
import kotlinx.coroutines.delay

private val TextMain = Color(0xFFF7FBFF)
private val TextMuted = Color(0xFFB7CFDF)

@Composable
fun DetailScreen(kind: DeviceKind, config: Config, onBack: () -> Unit) {
    var sections by remember { mutableStateOf<List<com.zhoujh.solar.data.DetailSection>>(emptyList()) }
    var error by remember { mutableStateOf<String?>(null) }
    var loading by remember { mutableStateOf(true) }

    LaunchedEffect(kind, config) {
        while (true) {
            if (config.valid) {
                try {
                    sections = HAClient(config).fetchDetail(kind).sections
                    error = null
                } catch (e: Exception) {
                    error = HAException.describe(e)
                }
            }
            loading = false
            delay(2000)
        }
    }

    Column(
        Modifier
            .fillMaxSize()
            .background(Color(0xFF0B1118))
            .padding(horizontal = 14.dp)
    ) {
        Spacer(Modifier.height(48.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onBack) { Text("← 返回", color = TextMuted) }
            Text(kind.title, color = TextMain, fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
        }
        Text(
            error ?: "数据来自 HA 实体 · 每 2 秒同步",
            color = if (error == null) TextMuted else Color(0xFFFFB4B4),
            fontSize = 11.sp
        )
        Spacer(Modifier.height(14.dp))

        if (loading) {
            CircularProgressIndicator(color = Cyan, modifier = Modifier.align(Alignment.CenterHorizontally))
        }
        sections.forEach { sec ->
            GlassCard(Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
                Text(sec.title, color = TextMain.copy(alpha = 0.92f), fontSize = 11.sp)
                Spacer(Modifier.height(8.dp))
                sec.fields.forEach { f ->
                    Row(Modifier.fillMaxWidth().padding(vertical = 5.dp)) {
                        Text(f.label, color = TextMuted, fontSize = 13.sp, modifier = Modifier.weight(1f))
                        Text(f.value, color = TextMain, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                    }
                }
            }
        }
        Spacer(Modifier.height(24.dp))
    }
}
