package com.zhoujh.solar.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.zhoujh.solar.data.Config

@Composable
fun SettingsSheet(initial: Config, onDismiss: () -> Unit, onSave: (String, String) -> Unit) {
    var url by remember { mutableStateOf(initial.url) }
    var token by remember { mutableStateOf(initial.token) }

    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Color(0xFF0E2336),
        title = { Text("HA 连接配置", color = TextMain) },
        text = {
            Column {
                Text("HA 地址", color = TextMuted, fontSize = 12.sp)
                OutlinedTextField(
                    value = url, onValueChange = { url = it },
                    placeholder = { Text("http://your-ha:8123", color = Color(0xFF7E96A8)) },
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedTextColor = TextMain, unfocusedTextColor = TextMain,
                        focusedBorderColor = Cyan, unfocusedBorderColor = Color(0xFF33566E)
                    ),
                    singleLine = true, modifier = Modifier.fillMaxWidth()
                )
                Spacer(Modifier.height(12.dp))
                Text("长期访问令牌", color = TextMuted, fontSize = 12.sp)
                OutlinedTextField(
                    value = token, onValueChange = { token = it },
                    placeholder = { Text("HA 个人资料 → 安全 → 长期访问令牌", color = Color(0xFF7E96A8)) },
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedTextColor = TextMain, unfocusedTextColor = TextMain,
                        focusedBorderColor = Cyan, unfocusedBorderColor = Color(0xFF33566E)
                    ),
                    singleLine = true, modifier = Modifier.fillMaxWidth()
                )
            }
        },
        confirmButton = {
            TextButton(onClick = { onSave(url, token) }) { Text("保存", color = Cyan, fontWeight = FontWeight.SemiBold) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("取消", color = TextMuted) }
        }
    )
}
