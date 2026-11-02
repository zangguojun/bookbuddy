# GitHub 一键打包 Android APK

1. 打开仓库 Actions，选择 Android APK。
2. 点击 Run workflow，选择 main，再点击 Run workflow。
3. 等待构建成功，在运行详情底部 Artifacts 下载 bookbuddy-debug-arm64。
4. 解压 ZIP，将 app-debug.apk 传到 ARM64 Android 手机或平板安装。

流程固定 Flutter 3.47.5、Java 17 与 NDK 28.2.13676358，并执行 flutter analyze 和 flutter test。产物保留 30 天。

这是测试 APK，不用于应用商店正式发布。云端临时环境生成的调试签名可能随运行变化，无法保证覆盖旧安装；不要为安装新包贸然卸载有重要数据的旧版本。长期分发前应配置持久签名与独立包名。

构建不需要模型密钥。安装后在 App 设置中配置文本模型及支持参考图的生图接口。不要将 API Key 写入仓库或工作流。
