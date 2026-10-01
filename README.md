# Reviews

<p align="center">
  <img src="docs/app-icon.png" width="128" alt="Reviews 应用图标">
</p>

Reviews 是一个本地优先的 Flutter 题库练习应用。用户可以导入 JSON、DOCX 或 DOC 文档，应用会识别题目、选项和答案并生成练习模块。题库、答题草稿和成绩均保存在设备本地，无需服务器。

## 功能

- 支持单选题、多选题、判断题、填空题和简答题
- 支持导入 `.json`、`.docx`、`.doc` 题库
- Android 支持从 QQ 的“分享”或“用其他应用打开”导入文件
- 根据标准文档模板自动识别题目、选项和答案
- 导入前预览题目数量并自定义模块名称
- 支持同名模块覆盖或另存
- 支持删除导入模块，并同步清理该模块的学习进度
- 自动保存答题草稿、完成状态和正确率
- 支持亮色与暗色主题
- 首次安装不预置模块，由用户自行导入题库

## 文档题库格式

应用右上角的文档按钮可以查看并复制完整模板，项目中也提供了：

- [`docs/question-bank-document-template.txt`](docs/question-bank-document-template.txt)
- [`docs/question-bank-format.md`](docs/question-bank-format.md)
- [`docs/question-bank-template.json`](docs/question-bank-template.json)

一个可识别的 Word 文档示例：

```text
1. HTTP 默认使用的端口是？（选择最佳答案。）
A. 21
B. 53
C. 80
D. 443
答案：C

2. 以下哪些属于应用层协议？（选择两项。）
A. HTTP
B. TCP
C. DNS
D. IP
答案：AC

3. 判断题：HTTPS 使用 TLS 加密。
答案：正确

4. IPv4 地址由 ______ 位二进制数组成。
答案：32

5. 简述 DNS 的作用。
答案：DNS 用于把域名解析为 IP 地址。
```

解析规则：

1. 题目建议使用 `1.`、`2、`、`3）` 或 `第1题` 等编号。
2. 没有编号时，题干包含 `( )` 或 `（ ）` 且下一行是选项，也可识别为题目。
3. 选择题的每个选项独占一行，并以 `A.`、`B.` 等开头。
4. 答案独占一行，以 `答案：` 或 `正确答案：` 开头。
5. 多选题需注明“选择两项”或“选择多项”，答案可写为 `AC`。
6. 判断题答案支持“正确/错误”“对/错”“√/×”等写法。
7. 填空位置使用至少 6 个连续下划线，多个答案使用逗号分隔。
8. `# 模块1`、`第1章` 等标题不会被识别为题目。

> `.docx` 使用 Dart 在后台解析，仅提取文档正文；旧版 `.doc` 在兼容性较差时，建议先用 Word/WPS 另存为 `.docx`。单个导入文件限制为 20 MB。

## 从 QQ 导入（Android）

1. 在 QQ 中下载题库文件。
2. 长按文件，选择“分享”“发送到其他应用”或“用其他应用打开”。
3. 在应用列表中选择 Reviews。
4. 检查识别数量、修改模块名称，然后确认导入。

如果 QQ 没有显示 Reviews，可以先将文件保存到手机，再打开 Reviews，点击首页右下角“导入题库”。

## 开发环境

- Flutter SDK（项目 Dart SDK 约束：`^3.6.2`）
- Android Studio 或 VS Code
- Android SDK
- Android 最低版本：API 26（Android 8.0）

## 运行项目

```bash
flutter pub get
flutter run
```

运行静态分析和测试：

```bash
dart analyze
flutter test
```

构建通用 Android Release APK：

```bash
flutter build apk --release
```

输出位置：

```text
build/app/outputs/flutter-apk/app-release.apk
```

> 当前 `android/app/build.gradle` 的 Release 构建使用调试签名，适合安装测试。正式发布到应用商店前，请创建自己的 keystore 并配置正式签名，同时妥善保管密钥且不要提交到 GitHub。

## 项目结构

```text
lib/
├─ data/       示例/基础数据
├─ models/     题库与进度模型
├─ screens/    首页、模块和答题界面
├─ services/   文件读取、文档解析、题库与进度持久化
├─ src/        应用入口和全局状态
└─ theme/      亮色/暗色主题

docs/          题库格式说明、模板和图标
android/       Android 分享接收与 DOC 兼容读取
test/          Flutter 测试
```

## 数据与隐私

题库和学习进度通过 `SharedPreferences` 保存在设备本地。应用不会将题库内容上传到第三方服务器，也不需要账号登录。

