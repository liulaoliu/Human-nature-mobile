# AGENTS.md — 项目开发约定

本项目自动加载此文件，请始终遵守以下约定。

## 项目简介

「D哥帮你办」安卓版 —— 英语精读 / 背单词 / 产出训练 App。
Flutter + Provider MVVM + SQLite（sqflite）。

**本项目是 https://github.com/liulaoliu/Human-nature 的安卓版重构**
（那个仓库是 React + TypeScript 的 Web 版，本地源码在 `I:\Examples\Stutterer`），
不是它的分支，也不是它的 WebView 壳。两份代码互不引用、互不修改。
规则语义以 Web 版为准，移植时**逐函数对齐 + 逐用例对齐**。

## 目录（三层，依赖只能单向往里收）

```
lib/models/        纯数据模型（freezed + json_serializable，禁手写 fromJson/toJson）
lib/core/          纯领域逻辑：不碰 Flutter / 不碰 sqflite / 不碰 SharedPreferences —— 全部可单测
lib/data/db/       sqflite 建表与迁移（对应 Web 版 server/sqliteSchema.ts 的 13 版迁移史）
lib/data/repositories/  实现 core 需要的存储端口
lib/services/      跨仓库的业务编排（导入导出、备份、跑批）
lib/viewmodels/    ChangeNotifier：把 repository/service 的结果变成视图状态
lib/views/         页面（按导航流分文件）
lib/widgets/       可复用组件
lib/utils/         与业务无关的工具（日期格式化、拼音等）
```

**硬规则（由 `dart run tool/check_layers.dart` 拦）**：

- `lib/core/` **不许** import `package:flutter/*`、`lib/data/`、`lib/viewmodels/`、`lib/views/`、`lib/widgets/`、`sqflite`、`shared_preferences`。
  → 要读写存储？在 `lib/core/ports.dart` 定义抽象类，由 `lib/data/repositories/` 实现、由 `viewmodels` 注入。
- `lib/data/` 不许认识界面。
- `lib/views/`、`lib/widgets/` 不许直接开数据库（不许 import `sqflite`），一律经 ViewModel。

## 工作流（硬规则）

- **说做就做，不反问**：用户指出问题就改代码 / 跑命令，不要先问「要我改吗」再等。
- **执行纪律**：
  - 不写 `for … sleep` 盲等、不静默空转；查状态用一条短命令（`tail` 日志 / `adb devices` / 进程列表），几秒内出结果。
  - 构建、全量测试、装 APK 等长命令放后台跑（agent 用自己的后台任务；人手动跑就直接跑），
    跑完再汇报；**已经验证过且未受影响的，不重复跑**。
  - ⚠️ **不提交 `run_with_watch.bat` 这类「PowerShell Start-Process + 隐藏窗口 + 重定向」的看护脚本**：
    2026-11-08 建仓时写过一版，落地即被杀毒软件当可疑行为删掉（隐藏窗口起进程 + 重定向是典型告警特征）。
    要看进度就用后台任务，或直接 `flutter test 2>&1 | tail -40`。
  - **一个主题一次 commit**：一次改动含多个独立主题时，每完成一个主题立刻单独 commit
    （代码 + 连带测试/文档同批进该 commit），不攒到最后拆。message 用
    `feat:` / `fix:` / `refactor:` / `chore:` / `docs:` + 中文简述。
- **TDD × 分层**：先写测试（把 Web 版同名测试的用例逐条翻过来当验收基准），再写实现，最后 `flutter test` 验证。
- **收尾门禁**（提交前必跑，别把不绿的留给用户）：
  ```bash
  flutter analyze                                          # 0 error / 0 warning
  dart run tool/check_god_class.dart                       # 防上帝类
  dart run tool/check_layers.dart                          # 分层依赖方向
  dart run tool/check_core_tests.dart                      # core 每个文件都要有同名测试
  flutter test                                             # 全量测试
  ```
- **文档同步**（同一次提交里改）：目录结构 / 分层 / 新增模块 → `docs/ARCHITECTURE.md`；
  新增踩坑 → `docs/TESTING.md` 补一条。

## 语言与类型（硬规则）

- 一律 `.dart`；**不许**出现 `.js` / `.ts` / Python 脚本进 `lib/`。
- 模型一律 codegen（freezed + json_serializable）。改字段后跑
  `dart run build_runner build --delete-conflicting-outputs`。
- 不许 `// ignore:` 压 analyzer 错误（`avoid_print` 这类工具脚本的例外要写明理由）。
- 不许大面积 `dynamic`；外部输入（备份 JSON、导入文章包）必须先在 `lib/core/` 的
  `normalize*` 函数里校验，坏数据要返回「好数据 + 丢弃条数」，不许静默变成空库。

## 与 Web 版的对应关系

上游：https://github.com/liulaoliu/Human-nature （React + TS Web 版，本地源码 `I:\Examples\Stutterer`）。

| Web 版（`I:\Examples\Stutterer`） | 本项目 |
|---|---|
| `src/core/*.ts`（144 文件 23k 行） | `lib/core/*.dart`，逐函数移植 |
| `src/types/document.ts` | `lib/models/*.dart`（freezed） |
| `src/adapters/*.ts`（IndexedDB / localStorage / fetch） | `lib/data/repositories/*.dart`（sqflite / SharedPreferences） |
| `server/sqlite*.ts`（Node + node:sqlite） | `lib/data/db/*.dart`（sqflite，**迁移史照搬**） |
| `src/reader/`（React 视图 43k 行） | `lib/views/` + `lib/viewmodels/`（**重新设计信息架构，不是照抄**） |
| `npm run gates` | `flutter analyze` + `tool/check_*.dart` + `flutter test` |

**服务端整个消失**：手机上没有 HTTP 服务，所有 `/api/store/*` 直接落 sqflite。
AI 跑批改为客户端直连（key 存本机，不写进仓库）。

## 分期（当前阶段）

- **一期（当前）**：`core` 地基移植 + sqflite schema + 精读 / 选词 / 背单词主链路。
- 二期：产出训练（风味酸奶）、D老师小课堂、跟读录音。
- 三期：AI 跑批、打印 / 导出、备份同步。
