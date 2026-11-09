allprojects {
    repositories {
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        google()
        mavenCentral()
    }

    // 2026-11-09 网络修复（固化进项目，跨机器生效，勿回退）：
    // integration_test 用动态版本依赖 androidx.test:runner:1.2+ 等，需要现场拉
    // maven-metadata；而 flutter 注入的 download.flutter.io 镜像
    // (storage.flutter-io.cn) 对该路径返回 403 且不 fallback，导致 gradle 动态版本
    // 解析失败、构建中断。处理：afterEvaluate（此时 flutter 仓库已注入）给
    // download.flutter.io 仓库加 content 过滤，只服务 io.flutter group；
    // 其余 group（androidx.test 等）自动跳过该仓库，走上面对配置的阿里云 google 解析。
    afterEvaluate {
        repositories.withType<MavenArtifactRepository>().forEach { repo ->
            if (repo.url.toString().contains("download.flutter.io")) {
                repo.content { includeGroup("io.flutter") }
            }
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
