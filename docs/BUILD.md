# 打包规格（Android）

> 口径对齐 `I:\Examples\patrol_helper` 的 `android/app/build.gradle.kts` +
> `android/gradle.properties` + `scripts/build_release.bat`。
> 目标：**只给用户自己的手机用**，不追求全平台兼容。

## 一、硬规格

| 项 | 值 | 在哪定 |
|---|---|---|
| ABI | **只有 `arm64-v8a`** | `android/app/build.gradle.kts` 的 `ndk.abiFilters` + `android/gradle.properties` 的 `disable-abi-filtering=true` |
| 目标平台参数 | `--target-platform android-arm64` | `scripts/build_release.bat` |
| 混淆 | `--obfuscate --split-debug-info=build/symbols` | 同上；符号表在 `build/symbols/`，**崩溃栈还原要用，别删** |
| minSdk | 24（`flutter.minSdkVersion`） | `defaultConfig` |
| targetSdk / compileSdk | 36 | `flutter.targetSdkVersion` / `compileSdkVersion` |
| 签名 | **有 `android/key.properties` 就用正式签名，没有退回 debug** | `signingConfig`（见第七节） |
| jniLibs 打包方式 | `useLegacyPackaging = true` | `packaging.jniLibs` |

## 二、为什么必须 abiFilters + disable-abi-filtering

`flutter build apk --target-platform android-arm64` **只裁 Flutter 自己的产物**
（`libapp.so` / `libflutter.so`）。带预编译 `.so` 的插件（`onnxruntime`、
`neural_tts`、`flutter_onnxruntime`）会把 **arm64 + armeabi-v7a + x86_64**
三套一起塞进来：

- 2026-11-15 实测：三 ABI 的 release 包 **138.08MB**，
  其中 `lib/x86_64` 33.2MB + `lib/armeabi-v7a` 19.6MB 完全用不上；
  而且这两份目录里**只有第三方 so、没有 `libapp.so` / `libflutter.so`**，是残缺目录
  —— 真机装上去如果被判定成 32 位会直接闪退。
- 只留 arm64 后 **89.3MB**（85.19MB，`native-code: 'arm64-v8a'` 单一 ABI）。
- 再把 jniLibs 改成压缩打包（`useLegacyPackaging = true`）→ **52.73MB（55,292,965 字节）**。
  `.so` 进了 APK 的 deflate 流，安装时由系统解压；代价是首启解压一次，
  换来包小 32MB —— 给自己手机装，这个交易划算。

> 上面的 52.73MB 是「只有词典/例句、没有神经 TTS 模型」时代的数字。
> 之后每次加离线朗读档都会往上抬：换 Kokoro-82M int8（88MiB）后是 **97.1MB**，
> 2026-11-16 把 Kitten（27MB）也装回来，预期回到 **约 125MB**。以实际构建产物为准。

两处缺一不可：

1. **`android/app/build.gradle.kts`** 的 release 里加 `ndk { abiFilters.clear(); abiFilters.addAll(targetAbiFilters) }`；
2. **`android/gradle.properties`** 加 `disable-abi-filtering=true`
   —— 否则 Flutter Gradle 插件会用自己的 ABI 列表**覆盖**掉 abiFilters，第 1 条白写。

## 三、体积构成（Kokoro 版 97.1MB 的包）

`lib/arm64-v8a` 原始 57.62MB，压缩后约 22.91MB：

| 项 | 原始 | 压缩后 |
|---|---|---|
| `libonnxruntime.so` | 28.64MB | 10.57MB |
| `libapp.so` | 16.65MB | 6.66MB |
| `libflutter.so` | 11.58MB | 5.41MB |
| `libonnxruntime4j_jni.so` | 0.08MB | 0.03MB |
| `libespeak_native.so` | 0.53MB | 0.22MB |

`assets/flutter_assets` 原始 152.71MB，压缩后约 77.57MB：

| 项 | 原始 | 压缩后 |
|---|---|---|
| `tts/kokoro/model.onnx` | 92.36MB | 63.05MB |
| `data/economist-backup-2026-11-10.json` | 36.50MB | 3.40MB |
| `ecdict/words.tsv` | 8.17MB | 3.58MB |
| `tatoeba/tatoeba-en.tsv` | 6.84MB | 2.63MB |
| `tts/en-us.bin` | 3.56MB | 1.11MB |
| `tts/kokoro/voices/*.bin` ×6 | 3.13MB | 2.88MB |
| `ecdict/forms.tsv` | 1.11MB | 0.28MB |

**要再瘦只能砍功能**：不要离线朗读（去掉 onnxruntime + Kokoro 模型 / 音色 / 词典
≈ 128MB 原始 / ≈ 78MB 压缩后，APK 回到 ~24MB）；内置样本
`economist-backup-2026-11-10.json` 只在 debug 导入时用，却仍打进 release 包，
去掉再省 3.4MB 压缩后。

## 四、命令

```bat
REM 发版（唯一推荐入口）
scripts\build_release.bat

REM 它内部就是：
flutter build apk --release --target-platform android-arm64 ^
  --obfuscate --split-debug-info=build/symbols -PtargetAbi=arm64

REM 模拟器冒烟（x86_64 模拟器装 arm64 包会崩：Could not find libflutter.so）
flutter build apk --release --target-platform android-x64 -PtargetAbi=x64
```

产物：`build\app\outputs\flutter-apk\app-release.apk`

**别直接 `flutter build apk --release`**：

- 不会把 `assets/data/` 的 34.8MB 开发样本挪走（脚本会），包会白胖 34MB；
- 不会传 `-PtargetAbi`，走缺省 arm64 但 Flutter 插件仍可能覆盖。

## 五、两种已知的构建期噪音

- **`scripts/build_release.bat` 现在按「APK 的 mtime 晚于本轮开始时间」判完成**
  （2026-11-15 修）。旧写法只看 `if exist "%APK%"`，上一轮的包还在时会立刻
  误报 `==== DONE ====` 并报一个中间态字节数 —— 那天报的是 56,901,632，
  实际 144,790,699。**自己核对仍以 `Get-Item` 的 `Length` / `LastWriteTime` 为准。**
- **KGP 警告**（`file_picker, flutter_onnxruntime, flutter_tts, neural_tts,
  record_android, share_plus` 用了 Kotlin Gradle Plugin）：
  `Future versions of Flutter will fail to build...`，现在不挡，将来要升插件。

## 六、装到手机

```bat
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

`INTERNET` 权限已在 `android/app/src/main/AndroidManifest.xml`
（Flutter 模板只在 debug/profile 给，release 会漏 → 任何网络请求都报
`Failed host lookup`）。核对：

```bat
aapt2 dump badging app-release.apk | findstr INTERNET
```

## 七、正式签名（33.16）

以前 release 写死 `signingConfig = signingConfigs.getByName("debug")`。自用包能装，但：

- **debug key 每台机器不一样**，换台机器重打就签不上同一个包 —— 手机上只能
  「卸载重装」，数据全丢（应用内备份能救，但麻烦）；
- 永远不能上架任何应用商店。

现在的口径是 **「有材料就用正式签名，没有退回 debug」**，所以自用包照旧
`scripts\build_release.bat` 直接打，不会因为缺 keystore 就构建失败。

### 一次性准备（只做一次）

```bat
REM 1) 生成 keystore。丢了就再也签不出同一个包，务必另存一份。
REM    -dname 可省，会交互提问；CN 随便填。
keytool -genkey -v -keystore android\dlaoshi-release.jks ^
  -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias dlaoshi

REM 2) 建 key.properties（模板已入库：android\key.properties.example）
copy android\key.properties.example android\key.properties
REM    然后把四个 CHANGE_ME / 路径改成真值
```

`android/key.properties`：

```properties
storeFile=dlaoshi-release.jks
storePassword=真口令
keyAlias=dlaoshi
keyPassword=真口令
```

`storeFile` 写**相对 `android/` 的路径**（`build.gradle.kts` 里用 `file(it)` 解析）。

### 两处都不进 git

`.gitignore` 已列 `/android/key.properties`、`*.jks`、`*.keystore`。
`test/services/android_signing_test.dart` 会盯这件事：谁把 keystore 或
`key.properties` 提交上来，或者谁把 `signingConfig` 改回写死 debug，那个测试就红。

### 怎么确认这一包到底是哪个签名

```bat
REM debug 签名的证书主体是 "CN=Android Debug"，正式签名是你在 -dname 里填的
"%JAVA_HOME%\bin\keytool" -printcert -jarfile build\app\outputs\flutter-apk\app-release.apk
```

用 debug 签名构建时，Gradle 日志里会有一行
`==> 没找到 android/key.properties，release 退回 debug 签名（33.16）`——
**看到这行就说明这一包换台机器装不上同一个 App**。

> 切正式签名后，手机上原来那个 debug 签名的包**必须先卸载**才能装新的
> （签名不同 = 不同 App）。卸载前先在应用内导出一份备份。
