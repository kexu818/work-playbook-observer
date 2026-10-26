# 工作观察与 Playbook 助手

先读 README.md；若工作区包含本机 PROJECT_STATUS.md 与 SOURCE_OF_TRUTH.md，也须读取。只读 Computer History 的事件与记忆，开发本机导出、Codex 订阅分析、候选核验与复用工作台。不得修改上游文件、观察设置或增加监听权限。

检查：`python3 -m unittest discover -s tests -v`。构建：`bash scripts/build-app.sh`。模型验证遵守宿主约定，已有 ke-codex-verify 时使用其隔离入口；产品分析优先复用本机隔离入口，没有时使用随附运行器。不能直接复用正式 CODEX_HOME 启动验证，不回退 API 计费。自动测试使用 fake CLI。

原始记录、导出、分析正文和凭证不得进入 Git、公开截图或测试日志。观察、候选、采用与有效分别记录；模型输出不能执行工作。保留用户改动；外发、推送和发布须有相应用户授权。机器专属状态及验收文件保持为本地忽略项。

在带有宿主知识库登记的工作区，里程碑需递增本机 PROJECT_STATUS.md 的 status_revision，并与宿主状态页、索引及登记保持一致；公开源码不包含这些机器专属投影。
