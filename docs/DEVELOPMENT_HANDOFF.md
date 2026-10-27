# 开发与验收

数据源由 Computer History 状态工具定位：事件为 `segments/*/events.jsonl`，摘要为 `~/.codex/memories/extensions/skysight/resources/*.md`。不改源文件和观察设置。

核对时间窗口、完整行快照、坏行/尾半行、未知字段保留、路径越界、摘要范围与重叠、导出哈希与源不变、无数据拒绝分析、未知证据拒绝、订阅身份、超时取消与认证清理、原子持久化和真实 GUI 控件。

模型验证先用合成工作样本，实际源读取与导出另测；下一次真实复用效果保留为未验，不以机器测试代替。

## 可移植运行入口

`backend/codex_runner.py` 随应用打包，支持无本机私有脚本的安装。测试用 fake CLI 验证完整候选持久化、独立认证副本、原配置不复制、API 环境隔离、失败退出和超时清理。真实云端端到端记录与工作内容属于用户本机资料，不随公开仓库分发。

打包使用 SDK 的实际版本填入 Mach-O linked SDK，以启用对应系统的原生外观；最低部署目标独立保留为 macOS 14。Logo 母版由 `actool` 编译为 AppIcon.icns 与 Assets.car，并在签名前写入图标元数据。

## 本机阅读样稿

可选的 `presentations.json` 保存在应用自己的 Application Support 数据目录。它仅为指定候选提供阅读投影，不覆盖原分析、来源或反馈；通过候选ID、原始标题和完整来源ID集合校验绑定。缺失或无效时继续显示原始候选。只有有样稿的候选使用新概览与来源卡，其他候选沿用原界面。导出按钮明确为「导出原始草稿」，反馈仍写入原候选ID。

样稿包含观察事实、方法建议、适用情境、证据缺口、关联来源说明及建议检查清单，可用可选的 `checklistTitle` 按工作类型命名清单。真实样稿不随源码分发。原始草稿可完整展开查看，来源文本默认折叠。

启用时参考 `examples/reading-presentation.example.json`，将本机文件保存为 `~/Library/Application Support/work-playbook-observer/presentations.json`，再刷新应用。示例为合成数据，不能原样匹配真实候选：`candidateID`、`originalTitle` 和 `originalSourceIDs` 必须与本机 `state.json` 中的原始候选一致；`sourceNotes` 必须逐一对应其全部来源，每个来源恰好一项，并出现在原分析的 `sources` 中。文案须区分已观察到的事实、方法建议和缺失证据。

该文件目前由用户或开发者准备，应用只读取它；分析器不会自动生成或修改阅读稿。不要将真实 `state.json`、阅读稿或工作截图提交到仓库。

纯合成绑定检查：

```sh
swiftc Sources/PlaybookWorkbench/CandidatePresentation.swift tests/test_candidate_presentation.swift -o .build/test-candidate-presentation
.build/test-candidate-presentation
```
