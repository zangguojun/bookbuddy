# cliProxy 接入

在 App「模型与接口配置」顶部选择「连接 cliProxy」，输入手机可访问的 HTTPS 网关基础地址（以 /v1 结尾）及客户端访问密钥，选择生图质量，点击「保存并启用」。可先「检查模型列表」；模型被列出不代表实际调用成功。

- 故事生成、修改、分镜、照片识别：gpt-6.1-sol，reasoning.effort=medium，POST /responses。
- 无参考图生成：默认 gpt-image-2.5-flare，也可选择 Sunburst；POST /images/generations。
- 有照片、角色定妆照或单页修改原图：gpt-image-2.5-sunburst；multipart POST /images/edits，多个 image[]。
- 图片输出 PNG，1024×1024；生图接口失败不会回退到 chat/completions。
- 单页重绘会将本页原图放在参考图首位，同时保留出场角色的定妆照。
- cliProxy 启用时关闭跨厂商生图回退；既有其他配置仍保留。
- 语音伴读仍使用原有 MiniMax 通道，本次三模型规范不包含语音接口。

东京服务器 127.0.0.1:8317 只在服务器本机可用，不能填作手机连接地址。请通过已有 HTTPS 网关/隧道访问。访问密钥在 App 内填写，经现有安全存储保存，不应提交到仓库、Actions 或 APK。

验收：先查 /models，再实际生成一个故事、一张图，最后使用单页修改，检查原主体保留且指定修改生效。自动测试使用模拟接口验证路由、参数、响应解析及图片解码，不代替真实代理验收。
