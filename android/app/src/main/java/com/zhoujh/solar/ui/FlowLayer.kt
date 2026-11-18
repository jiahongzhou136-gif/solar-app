package com.zhoujh.solar.ui

import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.IntSize

// 能流路径：与 HA 面板 SVG 同源（box 1617×971）
// 正向语义：光伏→中心、中心→住宅、中心→电池(充)、市电→中心(取电)
object FlowPaths {
    const val BOX_W = 1617f
    const val BOX_H = 971f

    private fun scale(size: IntSize): Pair<Float, Float> {
        val w = size.width.toFloat()
        val h = size.height.toFloat()
        return w / BOX_W to h / BOX_H
    }

    fun path(size: IntSize, route: String): Path {
        val (sx, sy) = scale(size)
        fun p(x: Float, y: Float) = Offset(x * sx, y * sy)
        val path = Path()
        when (route) {
            "pv" -> {
                path.moveTo(p(470f, 580f).x, p(470f, 580f).y)
                path.cubicTo(p(625f, 575f).x, p(625f, 575f).y, p(770f, 645f).x, p(770f, 645f).y, p(995f, 640f).x, p(995f, 640f).y)
            }
            "load" -> {
                path.moveTo(p(1010f, 627f).x, p(1010f, 627f).y)
                path.cubicTo(p(978f, 548f).x, p(978f, 548f).y, p(935f, 455f).x, p(935f, 455f).y, p(910f, 365f).x, p(910f, 365f).y)
            }
            "battery" -> {
                path.moveTo(p(995f, 655f).x, p(995f, 655f).y)
                path.cubicTo(p(905f, 690f).x, p(905f, 690f).y, p(820f, 730f).x, p(820f, 730f).y, p(735f, 765f).x, p(735f, 765f).y)
            }
            "grid" -> {
                path.moveTo(p(1390f, 510f).x, p(1390f, 510f).y)
                path.cubicTo(p(1280f, 540f).x, p(1280f, 540f).y, p(1160f, 610f).x, p(1160f, 610f).y, p(1025f, 640f).x, p(1025f, 640f).y)
            }
        }
        return path
    }

    fun hub(size: IntSize): Offset {
        val (sx, sy) = scale(size)
        return Offset(1010f * sx, 640f * sy)
    }
}

/** 能流绘制：底光常显；active 线路推进相位。正向 = -phase（对齐 HA Forward 0→-1000） */
@Composable
fun FlowLayer(
    size: IntSize,
    phase: Float,
    pv: Boolean, load: Boolean,
    battery: Boolean, batteryReverse: Boolean,
    grid: Boolean, gridReverse: Boolean
) {
    Canvas(modifier = androidx.compose.ui.Modifier) {
        val routes = listOf(
            Triple("pv", pv, false),
            Triple("load", load, false),
            Triple("battery", battery, batteryReverse),
            Triple("grid", grid, gridReverse)
        )
        val dash = floatArrayOf(
            maxOf(44f, size.width * 0.30f),
            maxOf(30f, size.width * 0.20f)
        )
        for ((route, active, reverse) in routes) {
            val path = FlowPaths.path(size, route)
            // 底光
            drawPath(
                path,
                color = Cyan.copy(alpha = if (active) 0.24f else 0.07f),
                style = Stroke(width = maxOf(5f, size.width * 0.018f))
            )
            if (active) {
                drawPath(
                    path,
                    brush = Brush.linearGradient(
                        listOf(Color(0xFF78F8FF), Color(0xFFD9FFFF), Color(0xFF44E5FF)),
                        start = Offset.Zero,
                        end = Offset(size.width.toFloat(), size.height.toFloat())
                    ),
                    style = Stroke(
                        width = maxOf(2.4f, size.width * 0.010f),
                        cap = StrokeCap.Round,
                        pathEffect = PathEffect.dashPathEffect(dash, if (reverse) phase else -phase)
                    )
                )
            } else {
                drawPath(
                    path,
                    color = Color(0xFF78F8FF).copy(alpha = 0.28f),
                    style = Stroke(width = maxOf(2.4f, size.width * 0.010f))
                )
            }
        }
        // 中心节点
        val hub = FlowPaths.hub(size)
        drawCircle(Cyan.copy(alpha = 0.9f), radius = maxOf(3f, size.width * 0.006f), center = hub)
    }
}
