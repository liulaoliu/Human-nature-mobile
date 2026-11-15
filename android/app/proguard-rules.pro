# R8 / ProGuard 规则（2026-11-15 新增）
#
# 为什么需要这个文件：
# 离线神经朗读走 `neural_tts` → `flutter_onnxruntime` → ONNX Runtime 的 Java 层。
# 那一层的 `OrtSession.run` 是 **native 代码反查 Java 类**（JNI `GetMethodID`），
# 从 Java 侧看不到对 `TensorInfo` / `OnnxJavaType` 的直接引用，R8 就把它们裁掉了。
# 结果：debug 包正常，release 包一点「试听一句」就
#   Abort message: 'JNI DETECTED ERROR IN APPLICATION: java_class == null
#     in call to GetMethodID
#     from ... ai.onnxruntime.OrtSession.run(...)'
#   #06 libonnxruntime4j_jni.so (convertToTensorInfo+628)
# 直接 SIGABRT 退出（2026-11-15 在 vivo V1981A / Android 12 上实测）。

# ONNX Runtime 的 Java 绑定：全部保留，别混淆、别裁。
-keep class ai.onnxruntime.** { *; }
-keep interface ai.onnxruntime.** { *; }
-dontwarn ai.onnxruntime.**

# 本项目 vendored 的 neural_tts（packages/neural_tts）与它依赖的音素化/推理壳。
# 这些类由 MethodChannel 按字符串名反射进来，同样看不到静态引用。
-keep class com.localmind.neural_tts.** { *; }
-dontwarn com.localmind.neural_tts.**

# 保留注解与泛型签名，JNI 反射取方法签名时要用。
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes InnerClasses
-keepattributes EnclosingMethod
