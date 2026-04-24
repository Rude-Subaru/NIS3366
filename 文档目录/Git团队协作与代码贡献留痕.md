# 🤖 AI秘书 — Git团队协作与代码贡献留痕记录

> **生成依据**：基于项目根目录 `.git` 仓库的完整 commit 历史自动提取与人工复核  
> **统计周期**：2026-03-30 至 2026-04-24（共 4 周）  
> **仓库地址**：`https://github.com/Huang Zhiyuan/NIS3366`（GitHub）

---

## 一、团队基本信息

| 项目 | 内容 |
|------|------|
| **项目名称** | AI秘书 — 基于大模型的智能个人助理 |
| **项目周期** | 4 周（2026.03.30 – 2026.04.24） |
| **团队规模** | 4 人 |
| **技术栈** | HarmonyOS ArkTS / ArkUI、relationalStore、@ohos.net.http |
| **协作工具** | Git（GitHub 托管）、Markdown 接口文档 |
| **总提交数** | 29 次 |
| **有效编码日** | 约 14 天 |

---

## 二、成员身份映射与贡献统计

> 注：以下按 Git 提交作者邮箱归并统计，括号内为项目中的角色代称。

| Git 作者 | 邮箱 | 提交次数 | 代码行贡献（估算） | 核心职责 |
|---------|------|---------|------------------|---------|
| **Huang Zhiyuan** | hzy364sjtu@gmail.com | 17 次 | 前端 UI（Index/Login/ChatDetail/PsychChat/SessionSelect）、ActionDialog、项目结构重构、README、PPT、文档统筹 | **组长**：UI 重构与主逻辑中枢管控 |
| **Haoyong Zheng** | 3371852131@qq.com | 5 次 | 主功能框架搭建、DatabaseManager 增强、UI 增补、测试文档、部署文档、设计文档 | **组员A**（兼文档负责人）：大模型调度策略、UI 实现、文档编写 |
| **Yuan Yifan** | yuan-yifan@sjtu.edu.cn | 3 次 | WriteExecutor 核心逻辑、SecurityChecker、演示视频、PPT 图片优化 | **组员C**：Write 路由分发与正则解析引擎 |
| **Xu Mingyu** | 973609470@qq.com | 3 次 | DatabaseManager 初始化、ReadExecutor 系统信息接入 | **组员B**：底层数据架构与 Read 感知层 |
| **tyzhnh** | 3371852131@qq.com | 1 次 | LLMService 模型配置微调 | Haoyong Zheng 的别名账号，同一人 |

**贡献可视化**：

```
Huang Zhiyuan     ████████████████████████████████████  17 commits (58.6%)
Haoyong Zheng   ████████████                          6 commits (20.7%)  [含 tyzhnh]
Yuan Yifan      ██████                                3 commits (10.3%)
Xu Mingyu       ██████                                3 commits (10.3%)
```

---

## 三、里程碑式提交时间线

### Phase 1：项目启动与基础框架（第 1 周）

| 日期 | Commit | 作者 | 关键动作 | 协作说明 |
|------|--------|------|---------|---------|
| 03-30 | `382edba` | Huang Zhiyuan | Initial commit | 仓库初始化，README 骨架 |
| 04-06 | `bc56e7e` | Huang Zhiyuan | 上传核心代码框架 | 一次性提交 12 个文件，奠定项目目录结构：pages、components、database、executors、security、utils 六大模块 |

### Phase 2：核心功能并行开发（第 2 周）

| 日期 | Commit | 作者 | 关键动作 | 协作说明 |
|------|--------|------|---------|---------|
| 04-15 | `17d7b95` | Yuan Yifan | 增加写执行体、安全检查 | WriteExecutor.ets (+886 行)、SecurityChecker.ets (+443 行)，实现 JSON 解析、Action 路由、敏感词拦截 |
| 04-16 | `b2316dd` | Haoyong Zheng | 完成主功能、数据库与 ArkTS 兼容修复 | 大规模重构，修复 DatabaseManager、Index、LLMService 的兼容性问题，新增 Login.ets、ChatDetail.ets 等页面 |
| 04-17 | `73208b2` ~ `8b6cc1f` | Xu Mingyu | 数据库初始化与读执行体系统信息接入 | 3 次连续提交，完成 DatabaseManager 建表逻辑、ReadExecutor 系统上下文读取 |
| 04-17 | `4d4fbcf` ~ `90f7565` | Huang Zhiyuan | 优化前端、改 UI | 前端细节打磨，新增资源文件、调整页面样式 |
| 04-17 | `c3e7178` | Haoyong Zheng | version 4-17 | 阶段性版本标记，合并多模块改动 |
| 04-17 | `788244d` | Huang Zhiyuan | API 保护 | 将硬编码 API Key 替换为占位符，防止泄露 |

### Phase 3：工程化与目录重构（第 3 周初）

| 日期 | Commit | 作者 | 关键动作 | 协作说明 |
|------|--------|------|---------|---------|
| 04-18 | `497e3a4` ~ `9dbb321` | Huang Zhiyuan | 4.18 版本迭代 | 将代码迁移至 `MyApplication/` 子目录，补充测试框架桩文件（LocalUnit.test.ets / Ability.test.ets） |
| 04-18 | `be0e54c` | Haoyong Zheng | 增加 UI | 大规模 UI 增补：Index.ets (+1700 行)、PsychChat.ets、SessionSelect.ets、DatabaseManager 大幅增强 |
| 04-18 | `77215e6` | tyzhnh | Update LLMService.ets | 微调模型配置参数 |
| 04-18 | `f87b936` | Huang Zhiyuan | change model used | 切换为 glm-4-flash 模型 |

### Phase 4：文档与演示资产产出（第 3 周中~第 4 周）

| 日期 | Commit | 作者 | 关键动作 | 协作说明 |
|------|--------|------|---------|---------|
| 04-19 | `1b56c1e` | Huang Zhiyuan | 需求分析文档 | 上传 requirement.pdf |
| 04-19 | `1fc8a3b` | Huang Zhiyuan | PPT version 4/19-22 | 汇报 PPT 迭代 |
| 04-20 | `468dcfb` ~ `632859d` | Huang Zhiyuan | 结构化、重写分工、加注释 | 工程目录规范化、代码注释补全、分工.pdf 更新 |
| 04-20 | `6e3bd73` | Yuan Yifan | 增加演示视频 | 上传 演示视频.mp4（约 30MB） |
| 04-20 | `e14cb63` | Huang Zhiyuan | 增加注释 | DatabaseManager、SecurityChecker 核心模块注释补全 |
| 04-22 | `6f4ae18` | Yuan Yifan | PPT 图片部分优化 | 汇报 PPT 视觉优化 |
| 04-24 | `e41cb79` | Haoyong Zheng | 增加测试文档、部署文档、修复需求文档 | 一次性产出测试文档.pdf、部署文档.pdf、修复需求分析文档目录问题 |
| 04-24 | `490fa37` | Haoyong Zheng | 增加设计文档 | 上传 设计文档.pdf |

---

## 四、协作模式分析

### 4.1 分支策略

- **主分支**：`main`（单主干开发）
- **合并记录**：共 2 次 Merge commit
  - `faa0ffe`（04-19）：Merge branch 'main' — 解决同步冲突
  - `a6c89fb`（04-20）：Merge branch 'main' — 同步远程更新
- **策略特征**：小团队采用「主干直推 + 必要时 Merge」的轻量模式，未使用 Feature Branch，符合 4 人课程项目的协作复杂度。


### 4.2 并行协作特征

```
时间轴（4.15 – 4.18 高峰期）
─────────────────────────────────────────────────────────
4/15  Yuan Yifan     → WriteExecutor + SecurityChecker 核心逻辑落地
4/16  Haoyong Zheng  → 主功能整合 + 兼容性修复
4/17  Xu Mingyu      → DatabaseManager + ReadExecutor 基础设施
4/17  Huang Zhiyuan    → UI 优化 + 资源文件 + API 保护
4/18  全员交叉       → 目录重构 + 模型切换 + 测试桩补充
─────────────────────────────────────────────────────────
```

**关键协作节点**：
1. **04-16 `b2316dd`**：Haoyong Zheng 的「主功能整合」commit 是项目从「各模块分散」到「可运行整体」的关键转折点，该 commit 修改了 14 个文件，整合了之前 Yuan Yifan 和 Xu Mingyu 的产出。
2. **04-18 `be0e54c`**：Haoyong Zheng 的「增加 UI」commit 是项目从「可用」到「完整体验」的跃升，新增了 PsychChat、SessionSelect 两大页面，DatabaseManager 扩展了用户体系与会话管理体系。
3. **04-20 至 04-24**：进入「文档与演示冲刺期」，Huang Zhiyuan 负责代码注释与工程结构化，Yuan Yifan 负责演示视频与 PPT，Haoyong Zheng 负责四大技术文档的编写。

---

## 五、文件级贡献热力图

> 按各 commit 的 `git show --stat` 提取，展示核心文件的修改频次与主要贡献者。

| 核心文件 | 主要贡献者 | 修改次数 | 关键演进 |
|---------|-----------|---------|---------|
| `Index.ets` | Huang Zhiyuan / Haoyong Zheng | 8+ | 从单页聊天 → 带 Tab 导航的完整主页 |
| `DatabaseManager.ets` | Xu Mingyu / Haoyong Zheng / Huang Zhiyuan | 7+ | 从基础建表 → 用户/会话/消息/日程四表 + 智能标题生成 |
| `WriteExecutor.ets` | Yuan Yifan / Haoyong Zheng | 5+ | 从 163 行 → 947 行，实现完整 Regex 管线与多态路由 |
| `LLMService.ets` | Huang Zhiyuan / Haoyong Zheng / tyzhnh | 5+ | 从基础 HTTP 调用 → 双态灾备 + Mock 降级 + API 保护 |
| `SecurityChecker.ets` | Yuan Yifan / Huang Zhiyuan | 4+ | 敏感词拦截体系完善 |
| `ActionDialog.ets` | Huang Zhiyuan / Haoyong Zheng | 3+ | 弹窗确认机制定型 |
| `README.md` | Huang Zhiyuan | 3 | 从空文件 → 完整项目说明书 |
| `组员接口文档.md` | Huang Zhiyuan | 2 | 接口契约与协作规范文档 |
| `汇报PPT.pptx` | Huang Zhiyuan / Yuan Yifan | 3 | 多轮视觉与内容迭代 |
| `需求分析文档.pdf` | Huang Zhiyuan / Haoyong Zheng | 2 | 初稿 + 目录修复 |
| `测试文档.pdf` | Haoyong Zheng | 1 | 16 页完整测试规范（04-24） |
| `部署文档.pdf` | Haoyong Zheng | 1 | 16 页部署规范（04-24） |
| `设计文档.pdf` | Haoyong Zheng | 1 | 8 页架构设计（04-24） |
| `分工.pdf` | Huang Zhiyuan | 1 | 团队分工说明（04-20） |

---

## 六、团队协作工具使用总结

| 工具 | 用途 | 使用深度 |
|------|------|---------|
| **Git** | 版本控制、代码回溯、协作留痕 | ✅ 深度使用，29 次提交完整留痕 |
| **GitHub** | 远程托管、代码同步 | ✅ 作为主干仓库 |
| **Markdown** | 接口文档（`组员接口文档.md`）、README | ✅ 规范使用 |
| **DevEco Studio** | IDE 开发、模拟器调试 | ✅ 工程配置完整 |
| **PDF/LaTeX** | 正式交付文档（需求/设计/测试/部署/分工） | ✅ 5 份正式文档 |
| **PowerPoint** | 汇报演示 | ✅ PPT 经 3 轮迭代 |
| **视频录制** | 演示视频 | ✅ 1 份完整演示视频 |

---

> **记录生成时间**：2026-04-24  
> **生成方式**：基于 `git log --all --reverse` 与 `git show --stat` 的原始数据人工整理  
> **记录维护者**：项目组全员共同确认
