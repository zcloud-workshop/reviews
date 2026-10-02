"""根据 GitHub Release 标签生成构建使用的应用版本。"""

import os
import re
from pathlib import Path


def prepare_release_version(pubspec_path: Path, release_tag: str) -> dict[str, str]:
    match = re.fullmatch(
        r"v((0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
        r"(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?)",
        release_tag,
    )
    if not match:
        raise ValueError("Release 标签格式无效，请使用 v0.1.1 这样的标签，无需添加 +构建号。")

    version = match.group(1)
    major, minor, patch = (int(match.group(index)) for index in (2, 3, 4))
    if minor >= 1000 or patch >= 1000 or major * 1000000 + minor * 1000 + patch + 1 + 4000 > 2100000000:
        raise ValueError("Release 标签版本超出 Android 内部编号支持范围。")

    pubspec = pubspec_path.read_text(encoding="utf-8")
    names = re.findall(r"^name:[ \t]*([^\n#]+)", pubspec, re.MULTILINE)
    app_name = names[0].strip().strip("\"'") if len(names) == 1 else ""
    if not re.fullmatch(r"[a-z][a-z0-9_]*", app_name):
        raise ValueError("pubspec.yaml 缺少唯一且有效的应用名称。")
    if len(re.findall(r"^version:[^\n]*$", pubspec, re.MULTILINE)) != 1:
        raise ValueError("pubspec.yaml 必须包含唯一的 version 字段。")

    pubspec_path.write_text(
        re.sub(r"^version:[^\n]*$", f"version: {version}", pubspec, count=1, flags=re.MULTILINE),
        encoding="utf-8",
    )
    return {"app_name": app_name, "version": version, "release_tag": release_tag}


def main() -> None:
    try:
        metadata = prepare_release_version(Path("pubspec.yaml"), os.environ.get("RELEASE_TAG", ""))
    except ValueError as error:
        raise SystemExit(str(error)) from None

    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
            for name, value in metadata.items():
                output.write(f"{name}={value}\n")
    print(f"发布标签：{metadata['release_tag']}，已生成 pubspec.yaml 版本：{metadata['version']}")


if __name__ == "__main__":
    main()
