# 开发与验收

数据源由 Computer History 状态工具定位：事件为 `segments/*/events.jsonl`，摘要为 `~/.codex/memories/extensions/skysight/resources/*.md`。不改源文件和观察设置。

核对时间窗口、完整行快照、坏行/尾半行、未知字段保留、路径越界、摘要范围与重叠、导出哈希与源不变、无数据拒绝分析、未知证据拒绝、订阅身份、超时取消与认证清理、原子持久化和真实 GUI 控件。

模型验证先用合成工作样本，实际源读取与导出另测；下一次真实复用效果保留为未验，不以机器测试代替。

## 可移植运行入口

`backend/codex_runner.py` 随应用打包，支持无本机私有脚本的安装。测试用 fake CLI 验证完整候选持久化、独立认证副本、原配置不复制、API 环境隔离、失败退出和超时清理。真实云端端到端记录与工作内容属于用户本机资料，不随公开仓库分发。

打包使用 SDK 的实际版本填入 Mach-O linked SDK，以启用对应系统的原生外观；最低部署目标独立保留为 macOS 14。Logo 母版由 `actool` 编译为 AppIcon.icns 与 Assets.car，并在签名前写入图标元数据。
