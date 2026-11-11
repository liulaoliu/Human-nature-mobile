# 开发用的真数据样本

把一份完整备份 JSON 放在这个目录，App 的「备份 → 开发用 → 导入内置样本」
（仅 debug 包可见）就会读它，省得每次装包都手动选文件。

当前约定的文件名：

```
assets/data/economist-backup-2026-11-10.json
```

（约 33MB，10,892 词 / 50 篇。改数据就替换这个文件，或改
`lib/views/backup_page.dart` 里的 `sampleBackupAsset` 常量。）

## 为什么这里只有一个 README

样本体积太大，**不进 git**（`.gitignore` 里忽略了 `assets/data/*`，
只保留本文件）。所以：

- 新克隆的仓库没有样本文件，`pubspec.yaml` 里 `assets/data/` 这个目录
  仍能正常构建（目录里至少有这份 README）；
- 想用样本就自己把 JSON 拷进来，`test/views/backup_page_test.dart`
  里那条用例在文件缺失时会自动跳过。
