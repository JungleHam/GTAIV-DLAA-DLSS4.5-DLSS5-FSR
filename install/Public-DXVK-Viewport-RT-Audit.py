#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: Public-DXVK-Viewport-RT-Audit.py <dxvk-root>")

root = Path(sys.argv[1])
source = root / "src" / "d3d9" / "d3d9_device.cpp"
if not source.is_file():
    raise SystemExit(f"missing DXVK source: {source}")

text = source.read_text(encoding="utf-8")
marker = "M3K-VIEWPORT-RT"
if marker in text:
    print("M3K viewport/render-target audit already present")
    raise SystemExit(0)

anchor = """    const D3DVIEWPORT9& vp = m_state.viewport;

    // Correctness Factor for 1/2 texel offset
"""
replacement = """    const D3DVIEWPORT9& vp = m_state.viewport;

    // M3K-VIEWPORT-RT: record the active RT0 alongside the viewport actually
    // submitted to Vulkan. The earlier SetViewport-only probe could not tell
    // whether a 2560x1440 viewport belonged to the 1485x835 backbuffer or to
    // a full-resolution offscreen/UI target. Do not scale anything until this
    // ownership is known.
    D3D9Surface* m3kRt0 = m_state.renderTargets[0].ptr();
    const D3D9_COMMON_TEXTURE_DESC* m3kRtDesc =
      m3kRt0 ? m3kRt0->GetCommonTexture()->Desc() : nullptr;
    const VkExtent2D m3kRtExtent =
      m3kRt0 ? m3kRt0->GetSurfaceExtent() : VkExtent2D { 0u, 0u };
    const D3DPRESENT_PARAMETERS* m3kSwapParams =
      m_implicitSwapchain.ptr() ? m_implicitSwapchain->GetPresentParams() : nullptr;
    static uint32_t m3kViewportRtAuditCount = 0;
    if (m3kViewportRtAuditCount < 128u) {
      ++m3kViewportRtAuditCount;
      const RECT& sr = m_state.scissorRect;
      const bool scissorEnabled = m_state.renderStates[D3DRS_SCISSORTESTENABLE] != FALSE;
      Logger::info(str::format(
        "[M3K-VIEWPORT-RT] #", m3kViewportRtAuditCount,
        " vp=", vp.X, ",", vp.Y, " ", vp.Width, "x", vp.Height,
        " rt=", m3kRtExtent.width, "x", m3kRtExtent.height,
        " backbuffer=", (m3kRtDesc && m3kRtDesc->IsBackBuffer) ? 1 : 0,
        " swap=", m3kSwapParams ? m3kSwapParams->BackBufferWidth : 0u,
        "x", m3kSwapParams ? m3kSwapParams->BackBufferHeight : 0u,
        " scissor=", scissorEnabled ? 1 : 0,
        " [", sr.left, ",", sr.top, ",", sr.right, ",", sr.bottom, "]"));
    }

    // Correctness Factor for 1/2 texel offset
"""
count = text.count(anchor)
if count != 1:
    raise SystemExit(f"BindViewportAndScissor audit anchor count={count}, expected 1")
text = text.replace(anchor, replacement, 1)

if text.count(marker) != 1:
    raise SystemExit("viewport/RT audit marker verification failed")

source.write_text(text, encoding="utf-8", newline="\n")
print("Applied read-only M3K viewport/active-render-target audit")
