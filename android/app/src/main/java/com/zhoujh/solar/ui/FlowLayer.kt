package com.zhoujh.solar.ui

import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.clipRect

/**
 * 三条能量流（雷凌 ios 版 1:1 移植）
 * 位置 / 条长 / 条宽全部取自底图实测的青色标识，条带沿电缆平移。
 * nx/ny 为底图归一化坐标（底图 1110×905）。
 */
private data class FlowSeg(
    val ny: Float,
    val nx0: Float,
    val nx1: Float,
    val blen: Float,
    val speed: Float,     // 组件宽/秒
    val active: Boolean,
    val reverse: Boolean
)

@Composable
fun FlowLayer(
    timeSec: Float,
    loadOn: Boolean,
    gridOn: Boolean,
    gridRev: Boolean,
    battOn: Boolean,
    battRev: Boolean,
    modifier: Modifier = Modifier
) {
    val segs = listOf(
        // A 逆变器 → 住宅（离网负载）
        FlowSeg(0.4597f, 0.5523f, 0.7189f, 0.0568f, 0.0605f, loadOn, false),
        // B 市电电表 ↔ 逆变器（取电向右，馈电向左）
        FlowSeg(0.5370f, 0.1847f, 0.4279f, 0.0820f, 0.0995f, gridOn, gridRev),
        // C 逆变器 ↔ 电池（充电向右，放电向左）
        FlowSeg(0.7182f, 0.5126f, 0.6802f, 0.0658f, 0.0788f, battOn, battRev)
    )

    Canvas(modifier) {
        val w = size.width
        val h = size.height
        val th = 0.0078f * w
        for (s in segs) {
            if (!s.active) continue
            val yc = s.ny * h
            val x0 = s.nx0 * w
            val x1 = s.nx1 * w
            val bl = s.blen * w
            val travel = (x1 - x0) + bl
            val period = travel / (s.speed * w)
            var p = (timeSec / period) % 1f
            if (p < 0f) p += 1f
            val off = p * travel - bl
            val bx = if (s.reverse) x1 - off - bl else x0 + off

            // 严格裁剪在电缆范围内
            clipRect(x0, yc - th, x1, yc + th) {
                // 外发光
                drawRoundRect(
                    color = Color(0x2912D4F0),
                    topLeft = Offset(bx - th * 0.40f, yc - th * 0.90f),
                    size = Size(bl + th * 0.80f, th * 1.80f),
                    cornerRadius = CornerRadius(th * 0.90f)
                )
                // 主体
                drawRoundRect(
                    brush = Brush.horizontalGradient(
                        listOf(Color(0xFF0ACBE8), Color(0xFF46E6FA), Color(0xFF10D2EF)),
                        startX = bx,
                        endX = bx + bl
                    ),
                    topLeft = Offset(bx, yc - th / 2f),
                    size = Size(bl, th),
                    cornerRadius = CornerRadius(th / 2f)
                )
            }
        }
    }
}
