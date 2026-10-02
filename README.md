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
- 单选、多选、判断和填空题自动判分；简答题显示参考答案，供自行核对
- 支持亮色与暗色主题
- 首次安装不预置模块，由用户自行导入题库

## 下载与开始使用

在 [GitHub Releases](https://github.com/zcloud-workshop/reviews/releases) 中选择版本，从 **Assets** 下载对应设备架构的 APK：

| 设备架构 | APK 文件名示例（`v0.1.1`） |
| --- | --- |
| ARM 64 位（常见 Android 手机） | `reviews-arm64-v8a-0.1.1.apk` |
| ARM 32 位 | `reviews-armeabi-v7a-0.1.1.apk` |
| x86 64 位 | `reviews-x86_64-0.1.1.apk` |

安装后，点击首页右下角“导入题库”，选择文件，检查模块、练习组和题目数量，修改模块名称并确认导入。与现有模块同名或同 ID 时，可选择“覆盖导入”或“另存导入”。进入模块后选择练习组即可开始答题。

答题草稿会自动保存，提交后可查看判题结果和参考答案。正确率只统计可自动判分的题目，简答题不计入正确率。

## JSON 题库格式

JSON 文件使用 UTF-8 编码，根对象包含 `formatVersion: 1` 和 `modules` 数组。每个模块包含一个或多个 `days` 练习组，每组包含 `questions` 题目。

| `type` | 题型 | `answer` 格式 |
| --- | --- | --- |
| `choice` | 单选题 | 正确选项下标，从 `0` 开始 |
| `multi` | 多选题 | 不重复的正确选项下标数组 |
| `judge` | 判断题 | `true` 或 `false` |
| `fill` | 填空题 | 标准答案字符串数组 |
| `shortAnswer` | 简答题 | 参考答案字符串 |

应用会在导入前校验字段、题型和答案下标，发现错误时提示模块、练习组和题号，错误文件不会写入本地题库。完整字段说明见 [JSON 格式说明](docs/question-bank-format.md)，可直接修改 [JSON 题库模板](docs/question-bank-template.json) 制作题库。

## 文档题库格式

应用右上角的文档按钮可以查看并复制完整模板，项目中也提供了 [文档题库模板](docs/question-bank-document-template.txt)。按模板整理题目后，用 Word/WPS 保存为 `.docx` 或 `.doc`，再导入应用。

每份 Word 文档会生成一个模块和一组“文档题目”练习，默认模块名称取自文件名。章节标题只会被忽略，不会将文档拆分成多个模块；需要多个模块或练习组时可使用 JSON 格式。

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

> 单个导入文件限制为 20 MB。`.docx` 在后台提取正文文字，不识别图片中的题目；旧版 `.doc` 的读取由 Android 原生代码实现，其他平台请先用 Word/WPS 另存为 `.docx`。无法读取的 `.doc` 文件也可尝试转换为 `.docx` 后导入。

## 从 QQ 导入（Android）

1. 在 QQ 中下载题库文件。
2. 长按文件，选择“分享”“发送到其他应用”或“用其他应用打开”。
3. 在应用列表中选择 Reviews。
4. 检查识别数量、修改模块名称，然后确认导入。

如果 QQ 没有显示 Reviews，可以先将文件保存到手机，再打开 Reviews，点击首页右下角“导入题库”。

## 开发环境

- Flutter SDK（CI 固定 stable `3.47.6`；项目 Dart SDK 约束：`^3.6.2`）
- Android Studio 或 VS Code
- Android SDK
- JDK 17（Android 构建，与 CI 一致）
- Android 最低版本：API 26（Android 8.0）

Android Studio 打开包含 `pubspec.yaml` 的项目根目录，并启用 Flutter / Dart 插件。无需单独安装 Gradle，Flutter 会通过项目的 Gradle Wrapper 自动使用指定版本。工具版本、本机 SDK 配置和打包步骤见 [Android 构建说明](docs/ci-workflow.md)。

## 运行项目

```bash
flutter pub get --enforce-lockfile
flutter run
```

运行静态分析和测试：

```bash
flutter analyze --no-pub
flutter test --no-pub
```

构建通用 Android Release APK：

```bash
flutter build apk --release --no-pub
```

输出位置：

```text
build/app/outputs/flutter-apk/app-release.apk
```

Release APK 使用项目固定签名，本地和 GitHub Actions 共用同一证书。本地构建需准备被 Git 忽略的 `android/key.properties`，配置方法与密钥备份说明见 [签名配置](docs/ci-workflow.md#固定签名配置)。缺少密钥时 Release 构建会失败；Debug 运行无需发布密钥。

构建与 CI 相同的三种架构 APK：

```bash
flutter build apk --release --split-per-abi --no-pub
```

原始输出位于 `build/app/outputs/flutter-apk/`，文件名为 `app-armeabi-v7a-release.apk`、`app-arm64-v8a-release.apk` 和 `app-x86_64-release.apk`。CI 上传前会将文件重命名为“应用名-架构-版本.apk”。

## GitHub Actions 自动构建

工作流定义在 [`.github/workflows/flutter-ci.yml`](.github/workflows/flutter-ci.yml)。

| 触发事件 | 行为 |
| --- | --- |
| 任意分支推送、PR、`v*` 标签推送、手动运行 | 仅静态分析与测试 |
| 发布 GitHub Release，标签提交属于 `main` 历史 | 测试通过后构建、签名并上传三种架构 APK |
| 发布 GitHub Release，标签提交不属于 `main` 历史 | 仅静态分析与测试 |
| 保存 Release 草稿或编辑已有 Release | 不触发工作流 |

发布新版本：

1. 将通过测试的待发布代码合入 `main`。
2. 在 [GitHub Releases](https://github.com/zcloud-workshop/reviews/releases) 创建新版本，选择 **Target: main**，输入递增的版本标签，例如 `v0.1.1`、`v0.1.2`，无需添加 `+构建号`。
3. 点击 **Publish release**。CI 从标签生成构建中的 `pubspec.yaml` 版本，并自动计算 Android 内部构建号，无需手动修改版本文件。正式版本和预发布版本均使用此流程。
4. 等待对应的 **Android APK** 工作流成功，在该 Release 的 **Assets** 中下载安装包。

仓库中的 `version` 仅作为本地开发默认值。CI 通过 [发布版本脚本](.github/scripts/prepare_release_version.py) 在临时检出目录中生成版本，不回写 Git 提交。标签格式为 `v主版本.次版本.修订版本`，可附加 `-beta.1` 等预发布标识。Android 内部构建号只由三个数字部分计算，修改预发布标识不会提高内部构建号。

CI 测试并构建标签指向的同一个提交，校验标签未被移动、提交属于 `main` 历史，并检查 APK 是否使用项目固定签名。仅推送标签或点击 Actions 的 **Run workflow** 不会构建 APK；需要重建时，在对应 Release 触发的运行中选择 **Re-run all jobs**，同名附件会被更新。

APK 文件和 Actions 构件统一按“应用名-架构-版本”命名：应用名取自 `pubspec.yaml`，版本取自 Release 标签，例如 `v0.1.1` 生成 `reviews-arm64-v8a-0.1.1.apk`，构件名去掉 `.apk` 后缀。安装包上传到触发构建的 GitHub Release 和 [Actions 页面](https://github.com/zcloud-workshop/reviews/actions)。Actions 构件保留 14 天，Release 附件不受此期限影响。完整构建、版本与签名说明见 [CI 文档](docs/ci-workflow.md)。

## 项目结构

```text
lib/
├─ data/       示例/基础数据
├─ models/     题库与进度模型
├─ screens/    首页、模块和答题界面
├─ services/   文件读取、文档解析、题库与进度持久化
├─ src/        应用入口和全局状态
└─ theme/      亮色/暗色主题

docs/          题库格式说明、模板、构建文档和图标
android/       Android 分享接收与 DOC 兼容读取
test/          Flutter 测试
.github/       GitHub Actions 工作流与发布版本脚本
```

## 数据与隐私

题库和学习进度通过 `SharedPreferences` 保存在设备本地。应用不会将题库内容上传到第三方服务器，也不需要账号登录。

删除模块会同步删除该模块的学习记录；卸载应用会清除本地数据。目前没有导出全部学习进度的功能，请保留题库原文件以便重新导入。

## 许可证

本项目采用 [MIT 许可证](LICENSE)。
