# Playbook 图标设计稿

2026-10-26生成，用户已确认采用。构建脚本将这份母版编译为原生应用图标。

图稿：`playbook-icon-v1.png`。蓝白玻璃书页与回转箭头，表达工作经验沉淀与再次复用。满版方形底稿，便于后续进入原生图标资产流程。

构建时由 `scripts/render-app-icon.swift` 将原图绘入1024像素透明画布，图标主体为824像素并带圆角，再交由actool编译多分辨率资源。运行时加载归一化后的AppIcon资源，避免直接将满版底稿设置为Dock图标。原始设计稿保持不变。

生成方式：内置 imagegen，未使用 API Key 或 CLI 计费路径。原始生成文件保留在 Codex generated_images；本目录为项目内副本。此前透明版本边缘有杂点，未选用。

最终生成提示词：

> Use case: logo-brand. Create a fresh, original, refined native macOS app-icon master for Playbook, a tool for turning work experience into reusable methods. ONE icon, square full-bleed canvas. The entire square canvas is a continuous rich clean blue field, subtly brighter at top left and deeper blue at bottom right; background must reach every edge and every corner, no transparency, no border, no surrounding margin, no rounded-square plaque. At its center, a large optically balanced sculptural white and translucent pale-blue open book emblem. Integrate ONE simple blue returning curved arrow into the right page, returning toward the left page, so the book and reuse motif read as one coherent logo. Very simple at small sizes; use broad clear geometric shapes and an elegant curved book spine, just two main pages, minimal page layers. Restrained premium Apple-platform materials: crisp white glass with subtle bevel highlights, translucent icy blue edge, modest physical depth, perfectly clean contour. Frontal orthographic composition, emblem occupies 65 percent of the square with generous breathing room. Quiet and iconic. No text, letters, numbers, sparkles, tiny details, outer shadows, flecks, particles, distressed texture, haze, device mockup, scenery, presentation board, or watermark. A clean full-bleed app-icon source asset, not a rounded icon shown on a backdrop.
