# Android APK 自动构建

工作流定义在 [`.github/workflows/flutter-ci.yml`](../.github/workflows/flutter-ci.yml)。所有分支执行静态分析与测试，只有发布 GitHub Release 且标签提交属于 `main` 时，才构建、签名并上传 APK。

## 构建方式

本项目保留 Flutter。Android Studio 用于编辑、运行和调试；`flutter build apk` 调用 Flutter 的 Gradle 插件和 Android Gradle Plugin（AGP）完成 Android 打包。GitHub Actions 在云端执行同一套流程。

无需在本地单独安装 Gradle，也无需直接执行 Gradle 命令：Flutter 会补齐本项目忽略的 Wrapper 启动文件，Wrapper 按 `android/gradle/wrapper/gradle-wrapper.properties` 下载指定版本。Android Studio 也使用这套构建配置。

## 触发条件

| 事件 | 行为 |
| --- | --- |
| push 到 `main` | 仅静态分析与测试 |
| push 到其他分支 | 仅静态分析与测试 |
| PR（包括目标为 `main` 的 PR） | 仅静态分析与测试 |
| push 版本标签 `v*` | 仅静态分析与测试 |
| `workflow_dispatch`（任意分支或标签） | 仅静态分析与测试 |
| 发布 GitHub Release，标签提交属于 `main` | 检查与测试通过后，构建 APK 并上传到 Actions 和该 Release |
| 发布 GitHub Release，标签提交不属于 `main` | 仅静态分析与测试 |
| 保存 Release 草稿、编辑已有 Release | 不触发工作流 |

`test` 任务没有签名 Secrets 或仓库写入权限。Release 的 `github.ref` 是标签引用，因此不能用 `refs/heads/main` 判断来源；`test` 在 Release 事件中获取完整 Git 历史，用 `git merge-base --is-ancestor` 确认发布提交属于 `origin/main`，并输出来源校验结果。`build` 依赖测试成功，同时要求事件为 `release.published` 且来源校验通过；仅该任务拥有上传 Release 附件所需的 `contents: write` 权限。普通推送、PR、手动运行及其他分支的 Release 跳过整个构建任务。Release 事件和标签引用说明见 [GitHub 官方文档](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#release)。

同一分支或标签的新测试运行会取消旧测试运行。Release 构建使用独立的并发组，同一标签的构建不会被新的测试运行取消。Actions 中的 **Run workflow** 仅用于测试；需要重建 APK 时，在对应 Release 触发的运行中选择 **Re-run all jobs**。参见 [GitHub 手动运行工作流说明](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)。

## 发布版本与标签

先将已验证的待发布代码合入 `main`，无需修改 `pubspec.yaml` 的 `version`。在 GitHub Releases 中创建新版本，选择 **Target: main**，输入递增的版本标签（例如 `v0.1.1`、`v0.1.2`），然后点击 **Publish release**。仅推送代码、标签或保存 Release 草稿不会构建 APK。正式版本和预发布版本发布时均会触发此流程。

新发布标签应指向包含本次工作流改动的 `main` 提交。GitHub 使用事件对应提交中的工作流配置，旧标签和旧运行仍使用原来的配置，参见 [GitHub 工作流触发说明](https://docs.github.com/en/actions/concepts/workflows-and-actions/workflows#workflow-triggers)。

例如发布标签 `v0.1.1` 时，CI 自动将构建中的 `pubspec.yaml` 改为 `version: 0.1.1`，附件为 `reviews-arm64-v8a-0.1.1.apk`。版本生成脚本为 [`.github/scripts/prepare_release_version.py`](../.github/scripts/prepare_release_version.py)，测试和打包使用同一个脚本。

- 标签不存在时，由 GitHub 在发布 Release 时基于选中的 `main` 提交创建标签；CI 不再自动创建标签或 Release。
- 标签已存在时，必须属于 `main` 的提交历史。CI 测试并构建 Release 对应的同一个提交，不改用最新的 `main` 代码，也不移动已有标签。
- Release 标签决定应用版本，无需与仓库中原有的 `pubspec.yaml` 版本一致。标签使用 `v主版本.次版本.修订版本`，可附加 `-beta.1` 等预发布标识，不能包含 `+构建号`。APK 文件名和内部构建号由该标签决定。
- 重建会更新该 Release 的同名 APK 附件。
- 标签位于 `main` 历史之外时仅测试；标签格式或版本范围无效、标签被移动时，在配置签名之前失败。

仓库中的 `version: 0.1.0` 仅作为本地开发默认值。CI 在临时检出目录中生成发布版本，不回写 Git 提交。发布应用更新时，只需在 GitHub 依次创建 `v0.1.1`、`v0.1.2` 等 Release，无需修改版本文件或填写 `+构建号`。本地需要构建指定发布版本时，可先运行 `RELEASE_TAG=v0.1.1 python3 .github/scripts/prepare_release_version.py`，再执行 Flutter 构建；该命令会改写本地 `pubspec.yaml`。

Android 要求内部 `versionCode` 为递增的正整数，见 [Android 版本说明](https://developer.android.com/studio/publish/versioning)。`android/app/build.gradle` 自动按 `主版本 × 1000000 + 次版本 × 1000 + 修订版本 + 1` 计算基础编号，次版本和修订版本均须小于 1000。Flutter 分架构 APK 会为 ARM 32 位、ARM 64 位和 x86 64 位分别追加 1000、2000 和 4000；基础编号预留最大偏移后不得超过 2100000000。本地和 CI 使用同一规则；相同版本与架构重建得到相同内部编号，主、次或修订版本递增时内部编号也递增。预发布标识不参与计算，例如 `v0.1.1-beta.1`、`v0.1.1-beta.2` 和 `v0.1.1` 在同一架构下使用相同内部编号；需要提高内部编号时，须递增三个数字部分之一。该编号只用于安装更新判断，APK 文件名和 Release 标签均不展示它。

## 工具版本

| 工具 | 配置 |
| --- | --- |
| CI 系统 | `ubuntu-24.04` |
| Flutter | stable `3.47.6`，与本次本地验证版本一致 |
| JDK | Temurin 17 |
| Gradle Wrapper | `8.14.5` |
| Android Gradle Plugin | `8.11.1` |
| Kotlin Gradle Plugin | `2.2.21` |
| Android SDK | compile/target API 36，由锁定的 Flutter SDK 决定 |
| NDK | `28.2.13676358`，由锁定的 Flutter SDK 决定 |
| 最低 Android 版本 | API 26（Android 8.0） |

AGP 8.11 要求 Gradle 至少为 8.13、JDK 至少为 17，现有组合满足要求，参见 [Android 官方兼容表](https://developer.android.com/build/releases/agp-8-11-0-release-notes)。升级 Flutter 后须同步修改工作流中的版本号并重新验证 APK；仅修改 `pubspec.yaml` 的 Dart 约束不会更新 CI 的 Flutter SDK。

## 执行步骤

1. 所有分支、PR、版本标签、手动运行和已发布的 Release 先运行 `test`：校验版本生成脚本；Release 事件确认提交是否属于 `main`，通过后按 Release 标签生成测试版本。随后安装锁定的 Flutter，执行 `flutter pub get --enforce-lockfile`、`flutter analyze --no-pub` 和 `flutter test --no-pub`。
2. 只有属于 `main` 的 Release 在测试成功后启动 `build`，读取应用名称并根据同一 Release 标签生成 `pubspec.yaml` 版本，校验标签未变更且提交仍属于 `main`。
3. 检出发布代码，安装 JDK 17 和 Flutter，安装锁定依赖并输出 `flutter doctor -v`。
4. 从 GitHub Secrets 恢复固定 keystore 和 `android/key.properties`，文件仅允许当前用户读取。
5. 执行 `flutter build apk --release --split-per-abi --no-pub`，使用 `pubspec.yaml` 的版本号并自动计算 Android 内部构建号，生成三种架构的固定签名 APK。分架构构建方式见 [Flutter 官方说明](https://docs.flutter.dev/deployment/android#build-an-apk)。
6. 用 `apksigner` 逐个检查 APK，并将证书 SHA-256 与 `android/signing-certificate.sha256` 比较；任意一个不一致时失败。
7. 将 APK 复制到 `build/apk-artifacts/` 并按“应用名-架构-版本.apk”命名，每个架构单独上传为同名 Actions 构件（去掉 `.apk` 后缀）；文件缺失时失败。
8. 使用 GitHub CLI 将三个 `.apk` 附件上传到触发运行的已发布 Release。GitHub Token 仅在此步骤注入。无论任务成功或失败，最后都清理临时签名文件。

测试任务最多运行 20 分钟，构建发布任务最多运行 45 分钟。分析、测试、构建、签名验证任一步失败都不会上传 APK。

## 下载与签名

推荐从 [GitHub Releases](https://github.com/zcloud-workshop/reviews/releases) 选择所需版本，在 **Assets** 中直接下载对应架构的 `.apk` 安装。Release 附件不受 Actions 的 14 天保留期限影响。

也可以打开仓库 [Actions 页面](https://github.com/zcloud-workshop/reviews/actions)，选择 **Android APK** 中由 Release 触发的成功运行，在 **Artifacts** 中下载并解压得到同名 `.apk`。

`pubspec.yaml` 的应用名为 `reviews`，发布标签为 `v0.1.1` 时：

| 设备架构 | Actions 构件名 | APK 文件名 |
| --- | --- | --- |
| ARM 32 位 | `reviews-armeabi-v7a-0.1.1` | `reviews-armeabi-v7a-0.1.1.apk` |
| ARM 64 位（常见 Android 手机） | `reviews-arm64-v8a-0.1.1` | `reviews-arm64-v8a-0.1.1.apk` |
| x86 64 位 | `reviews-x86_64-0.1.1` | `reviews-x86_64-0.1.1.apk` |

产物保留 14 天，包名为 `com.quiz.reviews`。原始输出为 `build/app/outputs/flutter-apk/app-<架构>-release.apk`。上传使用 [`actions/upload-artifact`](https://github.com/actions/upload-artifact)，每个架构的构件名均不同。

Release APK 现在使用项目固定签名，本地与云端生成的 APK 使用同一证书，后续可覆盖安装；更新时应保持包名不变，并提高 GitHub Release 标签中的主、次或修订版本号，内部构建号会自动递增。Debug 构建仍使用开发环境自己的调试证书。

首次切换到固定签名时，旧的测试签名 APK 与新证书不同，无法直接覆盖安装。卸载会清除本地题库与学习记录，操作前应保留题库原文件；应用目前没有导出全部学习进度的功能。此后的固定签名 APK 不需要因为 runner 更换而卸载应用。

## 固定签名配置

本次生成的 keystore 使用 RSA 4096 位密钥，有效期 10000 天，别名为 `reviews-release`。公开证书指纹保存在 `android/signing-certificate.sha256`；该文件不包含私钥。签名方式参见 [Flutter Android 发布说明](https://docs.flutter.dev/deployment/android#sign-the-app)。

### 本地密钥与备份

密钥保存在工作区外的 `~/.android/reviews-signing/`，目录权限为 `700`，文件权限为 `600`：

| 文件 | 用途 |
| --- | --- |
| `reviews-release.jks` | 固定签名私钥 |
| `key.properties` | 密钥路径、别名和密码，包含敏感凭据 |
| `certificate.sha256` | 公开证书指纹，供核对 |

请将整个目录备份到你自己的安全存储位置。不要重新生成或随意替换密钥；丢失私钥或密码后，将无法继续为已安装的应用签署相同身份的更新。GitHub Secrets 不支持取回已保存的原值，不能代替本地备份。

当前 `dev` 工作区已配置 `android/key.properties`。其他本地检出或新建 worktree 如需 Release 构建，可在项目根目录执行：

```bash
install -m 600 ~/.android/reviews-signing/key.properties android/key.properties
flutter build apk --release --no-pub
```

换电脑时先安全恢复 keystore，再修改凭据文件的 `storeFile` 为新机器的绝对路径；可参考 `android/key.properties.example`。`key.properties` 和 `*.jks` 已被 Git 忽略。Release 构建在缺失配置、字段或 keystore 时明确失败，不会退回调试签名；普通 Debug 构建不要求发布密钥。

### GitHub Actions Secrets

仓库已配置以下 Actions Secrets：

| Secret | 内容 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `reviews-release.jks` 的 Base64 编码 |
| `ANDROID_KEYSTORE_PASSWORD` | keystore 密码 |
| `ANDROID_KEY_ALIAS` | 签名密钥别名 |
| `ANDROID_KEY_PASSWORD` | 私钥密码 |

工作流仅在签名准备步骤注入这些值，不输出密码或 keystore 内容。临时文件写入 runner 后用于 Gradle 签名，结束时自动删除。Secrets 缺失、编码错误、密钥密码错误或证书不匹配时，构建失败且不会上传 APK。若需要在另一仓库复用同一应用的签名，应从安全备份重新配置这四个 Secrets，不要生成新密钥。

## Android Studio 本地开发

1. 用 Android Studio 打开包含 `pubspec.yaml` 的项目根目录，并切换到 `dev` 分支。
2. 确认 Flutter 和 Dart 插件已启用，Flutter SDK 指向实际 SDK 目录。本次检查的本机路径为 `/opt/homebrew/share/flutter`。
3. 统一 Android Studio 和 Flutter 的 Android SDK 路径。本次 `flutter doctor -v` 使用 `/opt/homebrew/share/android-commandlinetools`；Android Studio 常用的 `~/Library/Android/sdk` 是另一个目录，仅安装了 API 37 平台，不能代替本项目需要的 API 36。可让 IDE 使用现有 Flutter SDK 对应的 Android SDK，或在另一个目录补齐 API 36、Build Tools 和 NDK 后显式切换。
4. Gradle JDK 推荐使用 JDK 17，与 CI 一致。本次验证的路径为 `/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home`。IDE 的 Gradle JDK 设置和 Flutter 使用的 JDK 应分别检查，后者可用 `flutter doctor -v` 确认。
5. 选择 Android 模拟器或真机，运行 `lib/main.dart`。需要本地 APK 时，在 IDE 的 Terminal 中执行以下命令。

```bash
flutter pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --release --no-pub
```

`android/local.properties`、IDE 配置和 Wrapper 生成文件已被项目忽略，无需提交本机绝对路径。
