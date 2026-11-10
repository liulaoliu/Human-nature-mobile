# D哥帮你办（安卓版）

英语精读 / 背单词 / 产出训练 App。Flutter + Provider MVVM + SQLite（sqflite）。

**这是 https://github.com/liulaoliu/Human-nature 的安卓版重构**
（上游是 React + TypeScript 的 Web 版，本地源码在 `I:\Examples\Stutterer`）：
两份代码互不引用、互不修改；规则语义以 Web 版为准，移植时逐函数、逐用例对齐。

## 现在到哪一步了

一期起步：`lib/core/` 已移植 `activity`（20 例测试）、`entry_kind`（6 例），
三个门禁工具与文档骨架已就位。视图层只有一个占位首页。

## 开发

```bash
flutter pub get
flutter analyze                       # 0 error / 0 warning
dart run tool/check_god_class.dart    # 上帝类
dart run tool/check_layers.dart       # 分层 R1–R4
dart run tool/check_core_tests.dart   # core 每个文件都要有同名测试
flutter test                          # 全量
```

打 release 包（只出 arm64-v8a）：

```bash
scripts\build_release.bat
```

## 文档

- `AGENTS.md` —— 开发约定（分层、门禁、一个主题一次 commit、语言与类型）
- `docs/ARCHITECTURE.md` —— 分层、服务端消失、跟读用现合成、PC→手机备份迁移
- `docs/TESTING.md` —— 分层测试矩阵、移植验收方式、踩坑清单

## 数据从哪来

不依赖任何自建网络服务。电脑上的进度用 Web 版的「导出备份」
（`economist-backup-<日期>.json`）带到手机，走 U 盘 / 微信文件传输 / 数据线都行；
App 里「从电脑导入」按 `docs/ARCHITECTURE.md` §七 的规则解析（覆盖 / 合并两种）。
