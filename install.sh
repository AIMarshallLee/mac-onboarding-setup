#!/bin/bash
# ============================================================
#   航海家 · AI 工具一键部署助手 (macOS)
#   检测 → 安装 → 授权，全程中文引导，给零基础新手用
#
#   必装：Codex / 飞书桌面版；可选增强：飞书CLI / Hermes / Obsidian
#   安装方式：一律各家官方脚本，零 Homebrew 依赖，脚本内不含任何密钥
#
#   用法（任选其一）：
#     一键运行：  curl -fsSL <你的链接>/install.sh | bash
#     只检测：    curl -fsSL <你的链接>/install.sh | bash -s -- --check
#     本地运行：  bash install.sh   /   bash install.sh --check
# ============================================================

# 失败不中断：不开 set -e；不开 set -u（新手环境变量可能未定义）
# 但远程安装器管道必须保留 curl 的失败状态，避免空脚本被误判为成功。
set -o pipefail

# ---------- 颜色与输出 ----------
if [ -t 1 ]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GRN=$'\033[32m'
  YLW=$'\033[33m'; BLU=$'\033[34m'; CYN=$'\033[36m'; RST=$'\033[0m'
else
  BOLD=""; DIM=""; RED=""; GRN=""; YLW=""; BLU=""; CYN=""; RST=""
fi
hr(){ printf '%s\n' "────────────────────────────────────────────"; }
say(){ printf '%s\n' "$*"; }
ok(){ printf "${GRN}✅ %s${RST}\n" "$*"; }
warn(){ printf "${YLW}⚠️  %s${RST}\n" "$*"; }
err(){ printf "${RED}❌ %s${RST}\n" "$*"; }
step(){ printf "\n${BOLD}${BLU}▶ %s${RST}\n" "$*"; }

# ---------- 工具函数 ----------
has_cmd(){ command -v "$1" >/dev/null 2>&1; }
command_version(){
  local cmd="$1" timeout_seconds="${VERSION_TIMEOUT_SECONDS:-8}"
  local tmp_dir output_file status_file pid elapsed=0 status=""
  case "$timeout_seconds" in ''|*[!0-9]*|0) timeout_seconds=8 ;; esac
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/navigator-version.XXXXXX") || return 1
  output_file="$tmp_dir/output"
  status_file="$tmp_dir/status"
  (
    "$cmd" --version >"$output_file" 2>/dev/null
    printf '%s' "$?" >"$status_file"
  ) &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$elapsed" -ge "$timeout_seconds" ]; then
      has_cmd pkill && pkill -TERM -P "$pid" 2>/dev/null || true
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      rm -f "$output_file" "$status_file"
      rmdir "$tmp_dir" 2>/dev/null || true
      return 124
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  wait "$pid" 2>/dev/null || true
  [ -f "$status_file" ] && status=$(cat "$status_file")
  if [ "$status" = "0" ]; then head -1 "$output_file"; fi
  rm -f "$output_file" "$status_file"
  rmdir "$tmp_dir" 2>/dev/null || true
  [ "$status" = "0" ]
}
command_ok(){ [ -n "$(command_version "$1")" ]; }
codex_ok(){ command_ok codex; }
lark_ok(){ command_ok lark-cli; }
hermes_version(){ command_version hermes; }
hermes_ok(){ [ -n "$(hermes_version)" ]; }
tool_ok(){
  case "${1:-}" in
    codex) codex_ok ;;
    hermes) hermes_ok ;;
    lark-cli) lark_ok ;;
    node|npm) node_ok ;;
    *) command_ok "$1" ;;
  esac
}

# 检测 Xcode 命令行工具(CLT)是否真装好。macOS 的 git 是 CLT 的占位命令——
# 没装 CLT 时 command -v git 也成功，但真跑 git 会报 xcrun error。必须实跑校验。
clt_ok(){ xcode-select -p >/dev/null 2>&1 && git --version >/dev/null 2>&1; }

# Node 是否真可用：node 和 npm 都得能跑（飞书 CLI 要 npm，光有 node 不够）
node_ok(){ node -v >/dev/null 2>&1 && npm -v >/dev/null 2>&1; }
lark_skills_ok(){ [ -f "$HOME/.agents/skills/lark-shared/SKILL.md" ]; }

# 从 Node 官方 index.json 选择兼容 macOS 11+ 的 Node 22 LTS 最新补丁版。
node_version_from_index(){
  tr '{' '\n' | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\(v22\.[0-9.]*\)".*/\1/p' | head -1
}

node_archive_arch(){
  case "${1:-}" in
    arm64) printf '%s\n' 'darwin-arm64' ;;
    x86_64) printf '%s\n' 'darwin-x64' ;;
    *) return 1 ;;
  esac
}

# 当前 Obsidian DMG 使用 Obsidian-x.y.z.dmg，不依赖固定的 universal 文件名。
obsidian_dmg_url_from_json(){
  grep -o '"browser_download_url"[[:space:]]*:[[:space:]]*"https://[^"]*\.dmg"' | head -1 | cut -d'"' -f4
}

failure_hint_from_log(){
  local raw lower
  raw=$(cat)
  lower=$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')
  case "$lower" in
    *"permission denied"*|*"operation not permitted"*|*"access is denied"*|*"eacces"*)
      printf '%s\n' "权限不足：请检查目标目录权限，或改用当前用户可写的位置。" ;;
    *"no space left"*|*"disk full"*)
      printf '%s\n' "磁盘空间不足：请先释放空间后重试。" ;;
    *"unsupported"*|*"not supported"*|*"bad cpu"*|*"exec format"*)
      printf '%s\n' "系统或芯片架构不受该安装包支持。" ;;
    *"checksum"*|*"hash mismatch"*)
      printf '%s\n' "安装包校验失败：文件可能不完整或被代理改写，请重新下载。" ;;
    *"proxy"*|*" 407 "*)
      printf '%s\n' "代理认证失败：请检查系统代理、账号或 TUN 模式。" ;;
    *"could not resolve"*|*"resolve host"*|*"name or service not known"*)
      printf '%s\n' "DNS 解析失败：当前终端无法找到下载域名。" ;;
    *"timed out"*|*"timeout"*)
      printf '%s\n' "下载超时：请检查网络稳定性后重试。" ;;
    *)
      printf '%s\n' "安装器返回了未分类错误；请保留上方原始报错用于排查。" ;;
  esac
}

format_elapsed(){
  local seconds="${1:-0}" hours minutes
  [ "$seconds" -lt 0 ] 2>/dev/null && seconds=0
  hours=$((seconds / 3600))
  minutes=$(((seconds % 3600) / 60))
  seconds=$((seconds % 60))
  if [ "$hours" -gt 0 ]; then printf '%s小时%s分%s秒' "$hours" "$minutes" "$seconds"
  elif [ "$minutes" -gt 0 ]; then printf '%s分%s秒' "$minutes" "$seconds"
  else printf '%s秒' "$seconds"
  fi
}

download_with_progress(){
  local label="$1" url="$2" output="$3" max_time="${4:-600}" started rc elapsed
  started=$(date +%s)
  say "${DIM}正在下载 $label；下面显示实时百分比和速度……${RST}"
  curl -fL --progress-bar --show-error --connect-timeout 10 --max-time "$max_time" "$url" -o "$output"
  rc=$?
  elapsed=$(($(date +%s) - started))
  if [ "$rc" -eq 0 ]; then say "${DIM}$label 下载完成，耗时 $(format_elapsed "$elapsed")。${RST}"
  else warn "$label 下载中断（curl 返回 $rc，已用时 $(format_elapsed "$elapsed")）。"
  fi
  return "$rc"
}

run_with_elapsed(){
  local label="$1" started rc elapsed
  shift
  started=$(date +%s)
  "$@"
  rc=$?
  elapsed=$(($(date +%s) - started))
  say "${DIM}$label 已结束，耗时 $(format_elapsed "$elapsed")，返回码 $rc。${RST}"
  return "$rc"
}

run_downloaded_installer(){
  local shell_bin="$1" url="$2" label="$3" tmp_dir script_path log_path rc
  shift 3
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/navigator-installer.XXXXXX") || { err "$label：无法创建临时目录。"; return 1; }
  script_path="$tmp_dir/installer"
  log_path="$tmp_dir/install.log"
  if ! download_with_progress "$label 安装脚本" "$url" "$script_path" 180 2> >(tee "$log_path" >&2); then
    err "$label：安装脚本下载失败（$url）。"
    tail -8 "$log_path" 2>/dev/null
    failure_hint_from_log <"$log_path"
    rm -rf "$tmp_dir"
    return 1
  fi
  if [ ! -s "$script_path" ] || ! head -1 "$script_path" | grep -q '^#!'; then
    err "$label：下载内容不是有效安装脚本，可能被登录页、代理或网关替换。"
    rm -rf "$tmp_dir"
    return 1
  fi
  run_with_elapsed "$label 官方安装器" "$shell_bin" "$script_path" "$@" 2>&1 | tee "$log_path"
  rc=${PIPESTATUS[0]}
  if [ "$rc" -ne 0 ]; then
    err "$label：官方安装器返回错误码 $rc。"
    failure_hint_from_log <"$log_path"
  fi
  rm -rf "$tmp_dir"
  return "$rc"
}

obsidian_installed(){
  [ -d "/Applications/Obsidian.app" ] || [ -d "$HOME/Applications/Obsidian.app" ]
}

feishu_desktop_installed(){
  local candidate
  if [ "$#" -gt 0 ]; then
    for candidate in "$@"; do [ -d "$candidate" ] && return 0; done
    return 1
  fi
  for candidate in "/Applications/Feishu.app" "$HOME/Applications/Feishu.app" "/Applications/Lark.app" "$HOME/Applications/Lark.app"; do
    [ -d "$candidate" ] && return 0
  done
  return 1
}

feishu_download_url_from_json(){
  local platform="$1" json
  json=$(tr -d '\r\n')
  printf '%s' "$json" | sed -nE "s|.*\"$platform\"[[:space:]]*:[[:space:]]*\{[^}]*\"download_link\"[[:space:]]*:[[:space:]]*\"([^\"]+)\".*|\1|p"
}

feishu_download_hash_from_json(){
  local platform="$1" json
  json=$(tr -d '\r\n')
  printf '%s' "$json" | sed -nE "s|.*\"$platform\"[[:space:]]*:[[:space:]]*\{[^}]*\"hash\"[[:space:]]*:[[:space:]]*\"([^\"]+)\".*|\1|p"
}

space_meets_requirement(){
  local free_bytes="${1:-0}" minimum_gb="${2:-10}"
  [ "$free_bytes" -ge $((minimum_gb * 1024 * 1024 * 1024)) ] 2>/dev/null
}

course_workspace_ready(){
  local root="$1" dir
  [ -d "$root" ] || return 1
  for dir in '01-我的业务' '02-我自己' '03-数据包' '04-机会卡' '05-我的Agent'; do
    [ -d "$root/$dir" ] || return 1
  done
}

direction_checklist_found(){
  local root="$1"
  [ -d "$root" ] || return 1
  find "$root" -type f -name '*方向清单*' -print -quit 2>/dev/null | grep -q .
}

course_named_file_found(){
  local root="$1" pattern="$2"
  [ -d "$root" ] || return 1
  find "$root" -type f -name "$pattern" -size +0c -print -quit 2>/dev/null | grep -q .
}

course_prework_files_ready(){
  local root="$1"
  course_named_file_found "$root" '*人格档案*' &&
    course_named_file_found "$root" '*AI*协作说明*' &&
    course_named_file_found "$root" '*我的业务说明书*' &&
    course_named_file_found "$root" '*方向清单*'
}

course_data_package_ready(){
  local root="$1" data_dir="$1/03-数据包" minimum total file size
  minimum="${COURSE_DATA_MIN_BYTES:-2000000000}"
  [ -d "$data_dir" ] || return 1
  total=0
  while IFS= read -r file; do
    size=$(wc -c < "$file" 2>/dev/null || printf '0')
    total=$((total + size))
  done < <(find "$data_dir" -type f ! -name '*.zip' ! -name '.DS_Store' ! -name 'Thumbs.db' -print 2>/dev/null)
  [ "$total" -ge "$minimum" ] 2>/dev/null
}

find_existing_course_workspace(){
  local candidate
  for candidate in "${COURSE_WORKSPACE:-}" "$PWD/我的跨境Agent大课" "$HOME/Documents/我的跨境Agent大课"; do
    [ -n "$candidate" ] && [ -d "$candidate" ] && { printf '%s\n' "$candidate"; return 0; }
  done
  case "$PWD" in */我的跨境Agent大课) printf '%s\n' "$PWD"; return 0 ;; esac
  return 1
}

resolve_course_root(){
  if [ -n "${COURSE_ROOT:-}" ]; then printf '%s\n' "$COURSE_ROOT"; return 0; fi
  COURSE_ROOT=$(find_existing_course_workspace 2>/dev/null || true)
  printf '%s\n' "$COURSE_ROOT"
}

course_disk_space_ok(){
  local path="$1" free_bytes
  [ -n "$path" ] && [ -e "$path" ] || path="$HOME"
  free_bytes=$(df -Pk "$path" 2>/dev/null | awk 'NR==2 { printf "%.0f\n", $4 * 1024 }')
  space_meets_requirement "${free_bytes:-0}" 10
}

readiness_status(){
  local check
  for check in "$@"; do [ "$check" = "1" ] || { printf '%s\n' 'action_required'; return 0; }; done
  printf '%s\n' 'ready'
}

check_flag(){ if "$@" >/dev/null 2>&1; then printf '%s' 1; else printf '%s' 0; fi; }
platform_supported_on_mac(){ [ "$ARCH" = "arm64" ] || [ "$ARCH" = "x86_64" ]; }

# 2026-07 起新版 ChatGPT 桌面 App 已合并 Codex；同时兼容旧版 Codex.app 名称。
codex_desktop_app_installed(){
  [ -d "/Applications/ChatGPT.app" ] || [ -d "$HOME/Applications/ChatGPT.app" ] ||
    [ -d "/Applications/Codex.app" ] || [ -d "$HOME/Applications/Codex.app" ]
}

codex_desktop_app_signature_ok(){
  local app="$1" signature
  [ -d "$app" ] || return 1
  codesign --verify --deep --strict "$app" >/dev/null 2>&1 || return 1
  signature=$(codesign -dv --verbose=4 "$app" 2>&1)
  printf '%s\n' "$signature" | grep -q '^TeamIdentifier=2DC432GLL2$' || return 1
  printf '%s\n' "$signature" | grep -q '^Identifier=com.openai.codex$'
}

codex_desktop_app_arch_ok(){
  local app="$1" executable_name executable_path archs
  executable_name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist" 2>/dev/null)
  [ -n "$executable_name" ] || return 1
  executable_path="$app/Contents/MacOS/$executable_name"
  [ -x "$executable_path" ] || return 1
  archs=$(lipo -archs "$executable_path" 2>/dev/null) || return 1
  case "$ARCH" in
    arm64) case " $archs " in *" arm64 "*) return 0 ;; esac ;;
    x86_64) case " $archs " in *" x86_64 "*) return 0 ;; esac ;;
  esac
  return 1
}

install_codex_desktop_app(){
  local url tmp_dir dmg attach_out vol source_app candidate dest target copy_log
  url="https://persistent.oaistatic.com/codex-app-prod/ChatGPT.dmg"
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/navigator-codex-desktop.XXXXXX") || {
    err "无法创建 ChatGPT 桌面安装临时目录（权限或磁盘问题）。"
    return 1
  }
  dmg="$tmp_dir/ChatGPT.dmg"
  copy_log="$tmp_dir/copy.log"

  if ! download_with_progress "ChatGPT 桌面 App（内含 Codex）" "$url" "$dmg" 900 || [ ! -s "$dmg" ]; then
    err "ChatGPT 桌面安装包下载失败：$url"
    rm -rf "$tmp_dir"
    return 1
  fi
  if ! hdiutil verify "$dmg" >/dev/null 2>&1; then
    err "ChatGPT DMG 完整性校验失败；不会安装该文件。"
    rm -rf "$tmp_dir"
    return 1
  fi

  attach_out=$(hdiutil attach "$dmg" -nobrowse -readonly 2>&1)
  vol=$(printf '%s\n' "$attach_out" | awk -F '\t' '/\/Volumes\// { print $NF; exit }')
  if [ -z "$vol" ]; then
    err "ChatGPT DMG 挂载失败。"
    printf '%s\n' "$attach_out" | tail -5
    rm -rf "$tmp_dir"
    return 1
  fi

  source_app=""
  for candidate in "$vol/ChatGPT.app" "$vol/Codex.app"; do
    if [ -d "$candidate" ]; then source_app="$candidate"; break; fi
  done
  if [ -z "$source_app" ]; then
    err "DMG 中没有找到 ChatGPT.app 或 Codex.app；官方安装包结构可能已变化。"
    hdiutil detach "$vol" >/dev/null 2>&1
    rm -rf "$tmp_dir"
    return 1
  fi
  if ! codex_desktop_app_signature_ok "$source_app"; then
    err "ChatGPT App 的代码签名、OpenAI 签名团队或 Bundle ID 校验失败；不会安装。"
    hdiutil detach "$vol" >/dev/null 2>&1
    rm -rf "$tmp_dir"
    return 1
  fi
  if ! codex_desktop_app_arch_ok "$source_app"; then
    err "ChatGPT App 不包含当前芯片架构 $ARCH；请改用官方页面提供的对应版本。"
    hdiutil detach "$vol" >/dev/null 2>&1
    rm -rf "$tmp_dir"
    return 1
  fi

  dest="/Applications"
  if [ ! -w "$dest" ]; then
    dest="$HOME/Applications"
    mkdir -p "$dest" 2>"$copy_log" || dest=""
    [ -n "$dest" ] && warn "系统 Applications 不可写，将安装到当前用户目录：$dest"
  fi
  target=""
  if [ -n "$dest" ]; then target="$dest/$(basename "$source_app")"; fi
  if [ -z "$target" ]; then
    err "系统和用户 Applications 目录都不可写。"
  elif ditto "$source_app" "$target" 2>"$copy_log"; then
    ok "ChatGPT 桌面 App（内含 Codex）安装成功：$target"
  else
    err "ChatGPT 桌面 App 复制失败：$(tail -1 "$copy_log" 2>/dev/null)"
    failure_hint_from_log <"$copy_log"
  fi

  hdiutil detach "$vol" >/dev/null 2>&1
  rm -rf "$tmp_dir"
  codex_desktop_app_installed
}

install_feishu_desktop(){
  local platform metadata url expected actual tmp_dir dmg attach_out vol source_app dest target copy_log signature
  case "$ARCH" in
    arm64) platform="MacOS_m1" ;;
    x86_64) platform="MacOS" ;;
    *) err "飞书桌面版不支持当前芯片架构：$ARCH"; return 1 ;;
  esac
  metadata=$(curl -fsSL --connect-timeout 10 --max-time 60 https://www.feishu.cn/api/downloads 2>/dev/null) || {
    err "无法读取飞书官网安装包信息。"
    return 1
  }
  url=$(printf '%s' "$metadata" | feishu_download_url_from_json "$platform")
  expected=$(printf '%s' "$metadata" | feishu_download_hash_from_json "$platform")
  [ -n "$url" ] || { err "飞书官网返回中没有找到当前芯片的 macOS 安装包。"; return 1; }
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/navigator-feishu.XXXXXX") || { err "无法创建飞书安装临时目录。"; return 1; }
  dmg="$tmp_dir/Feishu.dmg"
  copy_log="$tmp_dir/copy.log"
  if ! download_with_progress "飞书桌面版" "$url" "$dmg" 1200 || [ ! -s "$dmg" ]; then
    err "飞书桌面安装包下载失败。"
    rm -rf "$tmp_dir"
    return 1
  fi
  if [ -n "$expected" ] && has_cmd md5; then
    actual=$(md5 -q "$dmg" 2>/dev/null)
    if [ "$actual" != "$expected" ]; then
      err "飞书安装包 MD5 与官网元数据不一致；不会安装。"
      rm -rf "$tmp_dir"
      return 1
    fi
  fi
  if ! hdiutil verify "$dmg" >/dev/null 2>&1; then
    err "飞书 DMG 完整性校验失败；不会安装。"
    rm -rf "$tmp_dir"
    return 1
  fi
  attach_out=$(hdiutil attach "$dmg" -nobrowse -readonly 2>&1)
  vol=$(printf '%s\n' "$attach_out" | awk -F '\t' '/\/Volumes\// { print $NF; exit }')
  if [ -z "$vol" ]; then
    err "飞书 DMG 挂载失败。"
    rm -rf "$tmp_dir"
    return 1
  fi
  source_app=""
  [ -d "$vol/Lark.app" ] && source_app="$vol/Lark.app"
  [ -z "$source_app" ] && [ -d "$vol/Feishu.app" ] && source_app="$vol/Feishu.app"
  if [ -z "$source_app" ]; then
    err "飞书 DMG 中没有找到 Lark.app 或 Feishu.app。"
    hdiutil detach "$vol" >/dev/null 2>&1
    rm -rf "$tmp_dir"
    return 1
  fi
  signature=$(codesign -dv --verbose=4 "$source_app" 2>&1)
  if ! codesign --verify --deep --strict "$source_app" >/dev/null 2>&1 ||
     ! spctl --assess --type execute "$source_app" >/dev/null 2>&1 ||
     ! printf '%s\n' "$signature" | grep -Eq '^Identifier=(com\.electron\.lark|com\.bytedance\..*lark.*)$'; then
    err "飞书 App 的代码签名、Gatekeeper或Bundle ID校验失败；不会安装。"
    hdiutil detach "$vol" >/dev/null 2>&1
    rm -rf "$tmp_dir"
    return 1
  fi
  dest="/Applications"
  if [ ! -w "$dest" ]; then dest="$HOME/Applications"; mkdir -p "$dest" 2>"$copy_log" || dest=""; fi
  target=""; [ -n "$dest" ] && target="$dest/Feishu.app"
  if [ -z "$target" ] || ! ditto "$source_app" "$target" 2>"$copy_log"; then
    err "飞书桌面版复制失败：$(tail -1 "$copy_log" 2>/dev/null)"
  else
    ok "飞书桌面版安装成功：$target"
  fi
  hdiutil detach "$vol" >/dev/null 2>&1
  rm -rf "$tmp_dir"
  feishu_desktop_installed
}

# 平台支持矩阵。参数化是为了能在不改本机环境的情况下做回归测试。
hermes_supported_on_mac(){
  [ "${1:-}" = "arm64" ] && [ "${2:-0}" -ge 12 ] 2>/dev/null
}
codex_app_supported_on_mac(){
  [ "${2:-0}" -ge 14 ] 2>/dev/null && { [ "${1:-}" = "arm64" ] || [ "${1:-}" = "x86_64" ]; }
}

# 深圳课程官方必装工具；飞书 CLI、Hermes 和 Obsidian 保留为可选增强。
all_installed(){
  codex_ok && feishu_desktop_installed
}

course_ready(){
  local root
  root=$(resolve_course_root)
  [ "$(readiness_status \
    "$(check_flag platform_supported_on_mac)" \
    "$(check_flag codex_ok)" \
    "$(check_flag feishu_desktop_installed)" \
    "${COURSE_NETWORK_OK:-0}" \
    "$(check_flag course_disk_space_ok "$root")" \
    "$(check_flag course_workspace_ready "$root")" \
    "$(check_flag course_prework_files_ready "$root")" \
    "$(check_flag course_data_package_ready "$root")")" = ready ]
}

# 把命令目录加入当前会话和新开的 zsh/bash。
add_shell_path_entry(){
  local dir="$1" label="${2:-命令目录}" rc line
  [ -d "$dir" ] || return 1
  case "$PATH" in
    "$dir"|"$dir:"*) ;;
    *) export PATH="$dir:$PATH" ;;
  esac
  line="export PATH=\"$dir:\$PATH\"  # 航海家脚本：$label"
  for rc in "$HOME/.zshrc" "$HOME/.bash_profile"; do
    [ -e "$rc" ] || touch "$rc" 2>/dev/null || continue
    grep -qF "$dir" "$rc" 2>/dev/null || printf '\n%s\n' "$line" >> "$rc"
  done
}

# 询问：回车=继续 / s=跳过(返回1) / q=退出整个脚本
# 通过 curl | bash 运行时，stdin 是脚本本身，这里显式从 /dev/tty 读键盘
ask_continue(){
  local prompt="$1" ans
  printf "${CYN}%s${RST} ${DIM}[回车=继续 / s=跳过 / q=退出]${RST}: " "$prompt"
  IFS= read -r ans </dev/tty || ans=""
  case "$ans" in
    s|S) return 1 ;;
    q|Q) say ""; say "已退出。随时可以重新运行，已装好的会自动跳过。"; exit 0 ;;
    *) return 0 ;;
  esac
}

# 把 ~/.local/bin 加入当前会话和新开的 zsh/bash（官方脚本多装到这里）
ensure_local_bin(){ add_shell_path_entry "$HOME/.local/bin" "本地命令"; }

latest_local_node_bin(){
  local dir
  for dir in "$HOME"/.local/node-*/bin; do
    [ -x "$dir/node" ] && { printf '%s\n' "$dir"; return 0; }
  done
  return 1
}

npm_global_bin(){
  local prefix
  prefix=$(npm prefix -g 2>/dev/null || npm config get prefix 2>/dev/null)
  [ -n "$prefix" ] && printf '%s\n' "$prefix/bin"
}

ensure_npm_user_cache(){
  local user_cache test_file
  user_cache="$HOME/.npm-cache"
  # 专门给一键脚本使用的 npm 缓存，绕开旧 ~/.npm 里可能存在的 root-owned 文件。
  warn "飞书 CLI 安装将使用用户缓存目录，避开旧 npm 缓存权限问题：$user_cache"
  mkdir -p "$user_cache" 2>/dev/null || return 1
  export npm_config_cache="$user_cache"
  test_file="$user_cache/.hjsx-cache-test-$$"
  if ! ( : > "$test_file" ) 2>/dev/null; then
    return 1
  fi
  rm -f "$test_file" 2>/dev/null
  npm config set cache "$user_cache" >/dev/null 2>&1 || true
  return 0
}

ensure_npm_user_prefix(){
  local prefix user_prefix bin
  prefix=$(npm prefix -g 2>/dev/null || npm config get prefix 2>/dev/null)
  user_prefix="$HOME/.npm-global"
  if [ -n "$prefix" ] && [ -w "$prefix/lib/node_modules" ]; then
    bin="$prefix/bin"
    add_shell_path_entry "$bin" "npm 全局命令"
    return 0
  fi
  warn "当前 npm 全局目录不可写，改用用户目录安装飞书 CLI（不需要 sudo）：$user_prefix"
  mkdir -p "$user_prefix" 2>/dev/null || return 1
  export npm_config_prefix="$user_prefix"
  npm config set prefix "$user_prefix" >/dev/null 2>&1 || true
  bin="$user_prefix/bin"
  mkdir -p "$bin" 2>/dev/null
  add_shell_path_entry "$bin" "npm 全局命令"
  return 0
}

repair_path_for_tool(){
  local display="$1" cmd="$2" dir="$3" file="${4:-$2}" cmd_label
  cmd_label="${cmd:-$file}"
  tool_ok "$cmd" && return 0
  [ -n "$dir" ] && [ -e "$dir/$file" ] || return 1
  echo
  hr
  say "${BOLD}PATH 修复：$display${RST}"
  warn "检测到 $display 本体已安装在：$dir"
  warn "但当前终端找不到 [$cmd_label] 命令，说明 PATH（命令查找目录）缺少这一项。"
  if ask_continue "按回车配置 PATH，让现在和新开的终端都能找到 [$cmd_label]"; then
    add_shell_path_entry "$dir" "$display"
    if tool_ok "$cmd"; then
      ok "$display 环境已补好：$cmd_label 可用了"
      echo
      return 0
    fi
    warn "$display 的 PATH 已写入，但当前窗口仍没识别；关掉终端重开后再试 $cmd_label --version。"
    echo
  fi
  echo
  return 1
}

repair_path_if_body_found(){
  local touched="" node_dir npm_bin
  node_dir=$(latest_local_node_bin)
  if ! node_ok && [ -n "$node_dir" ]; then repair_path_for_tool "Node.js / npm" node "$node_dir" node && touched=1; fi

  if ! codex_ok; then repair_path_for_tool "Codex (CLI)" codex "$HOME/.local/bin" codex && touched=1; fi
  if ! hermes_ok; then repair_path_for_tool "Hermes (CLI)" hermes "$HOME/.local/bin" hermes && touched=1; fi

  npm_bin=$(npm_global_bin)
  if ! lark_ok && [ -n "$npm_bin" ]; then repair_path_for_tool "飞书 CLI" lark-cli "$npm_bin" lark-cli && touched=1; fi
  [ -z "$touched" ] || hr
}

# ---------- 环境检测（芯片 / macOS 版本）----------
ARCH=$(uname -m)
case "$ARCH" in
  arm64) CHIP="Apple 芯片（M 系列）" ;;
  x86_64) CHIP="Intel 芯片" ;;
  *) CHIP="未知芯片（$ARCH）" ;;
esac
MACOS_VER=$(sw_vers -productVersion 2>/dev/null)
MACOS_MAJOR=$(printf '%s' "$MACOS_VER" | cut -d. -f1)
[ -n "$MACOS_MAJOR" ] || MACOS_MAJOR=0

# ---------- 状态记录 ----------
INSTALLED=(); SKIPPED=(); FAILED=(); OPTIONAL_FAILED=()
COURSE_NETWORK_OK=0
COURSE_ROOT=""

# ---------- 网络检测（这些工具的源都在国外，得先能连上）----------
check_endpoint(){
  local label="$1" url="$2"
  if curl -fsS --connect-timeout 5 --max-time 8 -o /dev/null "$url" 2>/dev/null; then
    ok "$label 可访问"
    return 0
  fi
  warn "$label 当前不可访问；只影响使用这个源的工具，脚本仍会继续并保留实际错误。"
  return 1
}

check_network(){
  hr; say "${BOLD}先检查实际下载源${RST}（预检只提醒，不会把所有问题都归为网络）"; hr
  COURSE_NETWORK_OK=1
  check_endpoint "GitHub 课程网络" "https://github.com" || COURSE_NETWORK_OK=0
  check_endpoint "Google 课程网络" "https://www.google.com/generate_204" || COURSE_NETWORK_OK=0
  check_endpoint "GitHub Raw" "https://raw.githubusercontent.com/AIMarshallLee/mac-onboarding-setup/main/install.sh" || true
  check_endpoint "Codex 官方安装源" "https://chatgpt.com/codex/install.sh" || true
  check_endpoint "Hermes 官方安装源" "https://hermes-agent.nousresearch.com/install.sh" || true
  check_endpoint "Node.js 官方源" "https://nodejs.org/dist/index.json" || true
  check_endpoint "npm / 飞书 CLI 源" "https://registry.npmjs.org/@larksuite%2fcli" || true
  check_endpoint "飞书桌面版官方源" "https://www.feishu.cn/api/downloads" || true
  check_endpoint "Obsidian 发布源" "https://api.github.com/repos/obsidianmd/obsidian-releases/releases/latest" || true
}

# ---------- 检测清单 ----------
detect(){
  hr; say "${BOLD}先看看你这台电脑现在的安装情况${RST}"; hr
  say "  ${DIM}本机：$CHIP / macOS $MACOS_VER${RST}"
  say "${DIM}  命令行工具(CLI)=终端里用、功能最全；桌面 App=图形界面、更直观。两者不冲突、可以都装。${RST}"
  say "${BOLD}  ▸ 命令行工具（CLI）${RST}"
  if codex_ok; then ok "Codex (CLI) —— $(command_version codex)"
  elif has_cmd codex; then err "Codex (CLI) —— 命令存在但已损坏（版本检测失败，会重新安装）"
  else err "Codex (CLI) —— 未装"; fi
  if hermes_supported_on_mac "$ARCH" "$MACOS_MAJOR"; then
    hermes_ok && ok "Hermes (CLI，可选) —— $(hermes_version)" || say "  ◦ Hermes (CLI，可选) —— 未装或命令无响应"
  else
    say "  ◦ Hermes (CLI) —— 已跳过（当前 Mac 不受官方支持）"
  fi
  if lark_ok; then ok "飞书 CLI（可选）—— $(command_version lark-cli)"
  elif has_cmd lark-cli; then warn "飞书 CLI（可选）—— 命令存在但版本检测失败"
  else say "  ◦ 飞书 CLI（可选增强）—— 未装"; fi
  lark_skills_ok && ok "飞书官方 Agent Skills（可选）—— 已装" || say "  ◦ 飞书官方 Agent Skills（可选）—— 未补齐"
  say "${BOLD}  ▸ 桌面 App / 知识库${RST}"
  feishu_desktop_installed && ok "飞书桌面版 —— 已装" || err "飞书桌面版 —— 未装（深圳课程必装）"
  obsidian_installed && ok "Obsidian（可选）—— 已装" || say "  ◦ Obsidian（可选）—— 未装"
  if codex_desktop_app_installed; then ok "ChatGPT 桌面 App（内含 Codex）—— 已装"
  elif codex_app_supported_on_mac "$ARCH" "$MACOS_MAJOR"; then say "  ◦ ChatGPT 桌面 App（内含 Codex）—— 未装（可选，macOS 14+）"
  else say "  ◦ ChatGPT 桌面 App（内含 Codex）—— 当前系统不支持（需要 macOS 14+）"; fi
  if ! hermes_supported_on_mac "$ARCH" "$MACOS_MAJOR"; then
    warn "Hermes 官方不支持当前 Mac：需要 Apple Silicon 且 macOS 12+；本机将跳过 Hermes。"
  fi
  say "${DIM}  ── 下面是依赖，不用单独管 ──${RST}"
  node_ok && ok "Node.js / npm（飞书 CLI 可选依赖）—— $(node -v)" || say "  ◦ Node.js / npm（可选）—— 未装；选择飞书 CLI 时会自动补齐"
  clt_ok && ok "开发者命令行工具 / Git —— 已就绪" || warn "开发者命令行工具(CLT) —— 没装好（git 跑不起来；装 Hermes 前会引导 xcode-select --install）"
  local course_root direction
  course_root=$(resolve_course_root)
  say "${BOLD}  ▸ 深圳课程课前检查${RST}"
  course_disk_space_ok "$course_root" && ok "可用磁盘空间不少于 10GB" || err "可用磁盘空间不足 10GB 或无法读取"
  course_workspace_ready "$course_root" && ok "课程五个文件夹已就绪：$course_root" || err "未找到完整的『我的跨境Agent大课』五个文件夹"
  direction=$(find "$course_root" -type f -name '*方向清单*' -print -quit 2>/dev/null)
  [ -n "$direction" ] && ok "方向清单已找到：$direction" || err "方向清单尚未找到（需完成课前作业）"
  course_prework_files_ready "$course_root" && ok "课前四份文件已齐：人格档案 / AI协作说明 / 我的业务说明书 / 方向清单" || err "课前四份文件未齐（需完成作业③的课前任务包）"
  course_data_package_ready "$course_root" && ok "课程 ABA 数据包已解压放入 03-数据包（不少于约 2GB）" || err "课程 ABA 数据包未就绪（不能只有 ZIP，需解压到 03-数据包）"
}

# ---------- 工作区（知识库文件夹）----------
setup_workspace(){
  step "准备『我的跨境Agent大课』课程文件夹"
  say "最新版课前手册要求由作业③的『课前任务包』让 Codex 创建五个子文件夹并写入内容。"
  say "本脚本只确定课程根目录，不提前创建空子文件夹，也不会覆盖你已有的文档。"
  local default="$HOME/Documents/我的跨境Agent大课" dir
  say "  ${DIM}直接回车用默认：$default${RST}"
  say "  ${DIM}或粘贴你想要的完整路径（绝对路径，例如 $HOME/我的跨境Agent大课）：${RST}"
  printf "${CYN}工作区路径：${RST} "
  local inp; IFS= read -r inp </dev/tty || inp=""
  [ -z "$inp" ] && WORKSPACE="$default" || WORKSPACE="$inp"
  if ! mkdir -p "$WORKSPACE" 2>/dev/null || ! cd "$WORKSPACE" 2>/dev/null; then
    err "工作区创建或进入失败：$WORKSPACE"
    say "  ${DIM}常见原因：路径写错、上级目录不可写、磁盘只读或空间不足。${RST}"
    FAILED+=("工作区（路径或权限）")
    return 1
  fi
  COURSE_ROOT="$WORKSPACE"
  ok "课程根目录：$WORKSPACE（五个子文件夹由课前任务包创建）"
}

# ---------- 基础底座前置安装（CLT / Node，后面各工具都依赖）----------
ensure_base_deps(){
  hr; say "${BOLD}先检查基础环境${RST}（可选工具的依赖会在选择安装时按需补齐）"; hr
  # 1) Xcode 命令行工具：提供 git + 编译环境（Codex 与部分可选工具需要）
  if clt_ok; then
    ok "开发者命令行工具 / git —— 已就绪"
  else
    warn "缺「Xcode 命令行工具」（git / Codex 等工具会用到）。马上弹一个系统窗口，请点【安装】。"
    say "  ${DIM}它要联网下载、约几分钟。点了【安装】就别关窗口，脚本会等它装完自动继续。${RST}"
    xcode-select --install 2>/dev/null || true
    local waited=0
    printf "  ${DIM}等待安装中"
    while ! clt_ok; do
      sleep 8; waited=$((waited+8)); printf "."
      if [ "$waited" -ge 600 ]; then
        printf "${RST}\n"; err "等了 10 分钟还没装好（可能没点【安装】或网络慢）。"
        say "  ${DIM}装完 CLT 后重跑本脚本即可；或现在先跳过（Hermes 这步会失败）。${RST}"
        OPTIONAL_FAILED+=("Xcode 命令行工具（Hermes 可选依赖）")
        warn "先跳过 Xcode 工具，继续装其它（只有 Hermes 受影响；装完 CLT 重跑即可）。"
        return
      fi
    done
    printf "${RST}\n"; ok "Xcode 命令行工具已就绪，git 可用了"; INSTALLED+=("Xcode 命令行工具")
  fi
  node_ok && ok "Node.js / npm（飞书 CLI 可选依赖）—— 已就绪（$(node -v)）" || say "  ${DIM}Node.js 暂未安装；只有选择飞书 CLI 时才会自动安装。${RST}"
  # Python 不用单独装——Hermes 官方脚本会用 uv 自动装 Python 3.11
}

# ---------- 各工具安装 ----------
do_codex(){
  step "Codex —— OpenAI 的 AI 终端（命令行）"
  if codex_ok; then ok "已安装：$(command_version codex)"; SKIPPED+=("Codex"); return; fi
  if has_cmd codex; then
    warn "检测到 Codex 命令，但 codex --version 执行失败；下面会用官方安装器覆盖修复。"
  fi
  case "$ARCH" in
    arm64|x86_64) ;;
    *) err "Codex 不支持当前芯片架构：$ARCH"; FAILED+=("Codex（不支持的芯片）"); return ;;
  esac
  say "将运行官方安装脚本（不需要 Node）："
  say "  ${DIM}curl -fsSL https://chatgpt.com/codex/install.sh | sh${RST}"
  ask_continue "现在安装 Codex？" || { SKIPPED+=("Codex"); return; }
  say "${DIM}正在下载安装，可能 1-2 分钟，请耐心等、别关窗口……${RST}"
  if run_downloaded_installer sh "https://chatgpt.com/codex/install.sh" "Codex"; then
    ensure_local_bin
    if codex_ok; then ok "Codex 安装成功：$(command_version codex)"; INSTALLED+=("Codex")
    else err "安装器结束后 codex --version 仍失败；这不是单纯 PATH 问题。"; FAILED+=("Codex（安装后不可用）"); fi
  else err "Codex 安装未完成，请根据上面的具体原因处理后重试。"; FAILED+=("Codex"); fi
}

do_hermes(){
  step "Hermes Agent —— 能成长的 AI 助手"
  if ! hermes_supported_on_mac "$ARCH" "$MACOS_MAJOR"; then
    if [ "$ARCH" != "arm64" ]; then
      warn "Hermes 官方不支持 Intel Mac；已安全跳过，不会继续下载不兼容版本。"
    else
      warn "Hermes 需要 Apple Silicon 且 macOS 12+；当前 macOS $MACOS_VER 不受支持，已跳过。"
    fi
    SKIPPED+=("Hermes（当前 Mac 不受官方支持）")
    return
  fi
  if hermes_ok; then ok "已安装：$(hermes_version)"; SKIPPED+=("Hermes"); return; fi
  if ! clt_ok; then
    warn "命令行 Hermes 需要 Xcode 命令行工具，你这台还没装好。"
    say "  ${DIM}更省事：直接装 Hermes 桌面 App（自带运行环境、不用 CLT），后面「图形界面」步骤会引导你装；想用命令行版就先把 Xcode 工具装好再重跑脚本。${RST}"
    SKIPPED+=("Hermes 命令行（缺 CLT → 改用桌面 App / 或装 CLT 重跑）"); return
  fi
  say "将运行 Hermes 官方安装入口（仅安装本体和环境，不进入配置向导）："
  say "  ${DIM}curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --skip-setup${RST}"
  ask_continue "现在安装 Hermes？" || { SKIPPED+=("Hermes"); return; }
  say "${DIM}正在装 Hermes：会下 uv / Python / Node 等依赖（连 astral.sh / GitHub / PyPI 等国外源），正常首次 5-15 分钟。${RST}"
  say "${DIM}中途看到「Trying tier: all」「Resolved N packages」「uv.lock sync failed」都正常，别关窗口。${RST}"
  say "${YLW}但卡在某一步（如 Installing managed uv）超过 10 分钟完全不动 = 网络/Cloudflare 拦了下载：按 Ctrl+C 中断，先跳过 Hermes，换干净网络/IP 再单独装。${RST}"
  if run_downloaded_installer bash "https://hermes-agent.nousresearch.com/install.sh" "Hermes" --skip-setup; then
    ensure_local_bin
    if hermes_ok; then ok "Hermes 安装成功：$(hermes_version)"; INSTALLED+=("Hermes")
    else warn "Hermes（可选）官方脚本跑完了，但 hermes --version 仍不能用。"; OPTIONAL_FAILED+=("Hermes（命令不可用）"); fi
  else warn "Hermes（可选）安装未完成，请根据上面的具体原因处理后重试。"; OPTIONAL_FAILED+=("Hermes"); fi
}

# ---------- Node.js 自动安装（官方包，免 brew/密码/浏览器）----------
install_node(){
  node_ok && return 0
  local a ver url dir archive archive_path sums_path expected actual tmp_dir index_json
  if [ "$MACOS_MAJOR" -lt 11 ] 2>/dev/null; then
    err "Node 22 LTS 需要 macOS 11+；当前 macOS $MACOS_VER 无法自动安装。"
    return 1
  fi
  a=$(node_archive_arch "$ARCH") || { err "Node 22 LTS 没有当前 Mac 芯片的官方安装包：$ARCH"; return 1; }
  index_json=$(curl -fsSL --connect-timeout 10 --max-time 60 https://nodejs.org/dist/index.json 2>/dev/null)
  ver=$(printf '%s' "$index_json" | node_version_from_index)
  [ -z "$ver" ] && ver="v22.11.0"
  archive="node-$ver-$a.tar.gz"
  url="https://nodejs.org/dist/$ver/$archive"
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/navigator-node.XXXXXX") || { err "无法创建 Node 临时目录（权限或磁盘问题）。"; return 1; }
  archive_path="$tmp_dir/$archive"
  sums_path="$tmp_dir/SHASUMS256.txt"
  if ! download_with_progress "Node $ver LTS（官方包）" "$url" "$archive_path" 300 || [ ! -s "$archive_path" ]; then
    err "Node 安装包下载失败：$url"
    rm -rf "$tmp_dir"
    return 1
  fi
  if ! curl -fsSL --connect-timeout 10 --max-time 60 "https://nodejs.org/dist/$ver/SHASUMS256.txt" -o "$sums_path"; then
    err "Node 校验文件下载失败，为安全起见不执行未校验安装包。"
    rm -rf "$tmp_dir"
    return 1
  fi
  expected=$(awk -v f="$archive" '$2 == f { print $1; exit }' "$sums_path")
  actual=$(shasum -a 256 "$archive_path" 2>/dev/null | awk '{print $1}')
  if [ -z "$expected" ] || [ "$actual" != "$expected" ]; then
    err "Node 安装包 SHA-256 校验失败（expected=$expected / actual=$actual）。"
    rm -rf "$tmp_dir"
    return 1
  fi
  mkdir -p "$HOME/.local" 2>/dev/null || { err "无法写入 $HOME/.local（权限不足）。"; rm -rf "$tmp_dir"; return 1; }
  if ! tar -xzf "$archive_path" -C "$HOME/.local"; then
    err "Node 安装包解压失败（文件损坏、磁盘空间或权限问题）。"
    rm -rf "$tmp_dir"
    return 1
  fi
  rm -rf "$tmp_dir"
  dir="$HOME/.local/node-$ver-$a/bin"
  add_shell_path_entry "$dir" "Node"
  node_ok && { ok "Node / npm 安装成功：$(node -v) / npm $(npm -v)"; return 0; }
  err "Node 文件已解压，但 node 或 npm 版本检测失败。"
  return 1
}

do_larkcli(){
  step "飞书 CLI —— 让 AI 直接读写你的飞书表格 / 文档"
  if lark_ok; then
    ok "已检测到飞书 CLI：$(command_version lark-cli)"
    say "  ${DIM}为了补齐官方 AI Agent Skills，这一步会再运行一次官方安装器（已装好的会自动升级/跳过）。${RST}"
  fi
  ask_continue "现在安装 / 补齐飞书 CLI + 官方 AI Agent Skills？" || { SKIPPED+=("飞书 CLI"); return; }
  if ! node_ok; then
    warn "飞书 CLI 需要 Node.js，没检测到，正在自动装（免 brew、免密码）……"
    if ! install_node; then
      err "Node 22 LTS 自动安装失败；请根据上方具体提示处理。"
      say "  ${DIM}也可到 ${RST}${CYN}https://nodejs.org/zh-cn/download${RST}${DIM} 手动安装 Node 22 LTS，重开终端后再运行。${RST}"
      OPTIONAL_FAILED+=("Node.js（飞书 CLI 可选依赖）")
      SKIPPED+=("飞书 CLI（缺 Node）"); return
    fi
  fi
  if ! ensure_npm_user_prefix; then
    err "npm 全局目录配置失败。请截图发到群里。"
    OPTIONAL_FAILED+=("飞书 CLI（npm 全局目录不可写）"); return
  fi
  if ! ensure_npm_user_cache; then
    err "npm 缓存目录配置失败。请截图发到群里。"
    OPTIONAL_FAILED+=("飞书 CLI（npm 缓存目录不可写）"); return
  fi
  say "将通过官方安装器安装：${DIM}npx --yes @larksuite/cli@latest install${RST}"
  say "  ${DIM}这一步会把飞书 CLI 本体 + 官方 AI Agent Skills 一起装好。${RST}"
  if ! has_cmd npx; then
    err "Node/npm 已检测到，但 npx 命令缺失；请重新安装完整的 Node 22 LTS。"
    OPTIONAL_FAILED+=("飞书 CLI（缺 npx）")
    return
  fi
  if run_with_elapsed "飞书 CLI 官方安装器" npx --yes @larksuite/cli@latest install; then
    repair_path_if_body_found
    if lark_ok && lark_skills_ok; then ok "飞书 CLI + 官方 Agent Skills 安装成功：$(command_version lark-cli)"; INSTALLED+=("飞书 CLI（含官方 Agent Skills）")
    elif lark_ok; then warn "飞书 CLI 可用，但官方 Agent Skills 没检测到；重跑安装器仍未补齐。"; OPTIONAL_FAILED+=("飞书 Agent Skills")
    else err "官方安装器返回成功，但 lark-cli --version 仍失败；请查看上方 npm 输出。"; OPTIONAL_FAILED+=("飞书 CLI（安装后不可用）"); fi
  else
    err "飞书 CLI 安装失败。可能原因包括 npm/二进制下载源、代理、权限、磁盘空间或不兼容版本；请保留上方原始错误。"
    OPTIONAL_FAILED+=("飞书 CLI")
  fi
}

do_obsidian(){
  step "Obsidian（可选）—— 你的 AI 第二大脑 / 知识库"
  if obsidian_installed; then ok "Obsidian 已安装"; SKIPPED+=("Obsidian"); return; fi
  ask_continue "现在安装 Obsidian（可选知识库）？" || { SKIPPED+=("Obsidian"); return; }
  say "下载 Obsidian 安装包（约几十 MB，稍等）..."
  local metadata url tmp_dir tmp vol attach_out dest copy_log
  metadata=$(curl -fsSL --connect-timeout 10 --max-time 60 https://api.github.com/repos/obsidianmd/obsidian-releases/releases/latest 2>/dev/null)
  if [ -z "$metadata" ]; then
    err "无法读取 Obsidian 最新版本信息（GitHub API 网络、限流或代理问题）。"
  else
    url=$(printf '%s' "$metadata" | obsidian_dmg_url_from_json)
    if [ -z "$url" ]; then
      err "Obsidian 发布信息里没有找到 macOS DMG；官方资产命名可能已变化。"
    else
      tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/navigator-obsidian.XXXXXX")
      if [ -z "$tmp_dir" ]; then
        err "无法创建 Obsidian 临时目录（权限或磁盘问题）。"
      else
        tmp="$tmp_dir/Obsidian-installer.dmg"
        copy_log="$tmp_dir/copy.log"
        if ! download_with_progress "Obsidian 安装包" "$url" "$tmp" 600; then
          err "Obsidian DMG 下载失败：$url"
        else
          attach_out=$(hdiutil attach "$tmp" -nobrowse 2>&1)
          vol=$(printf '%s\n' "$attach_out" | awk -F '\t' '/\/Volumes\// { print $NF; exit }')
          if [ -z "$vol" ]; then
            err "Obsidian DMG 挂载失败。"
            printf '%s\n' "$attach_out" | tail -5
          elif [ ! -d "$vol/Obsidian.app" ]; then
            err "DMG 已挂载，但里面没有 Obsidian.app；安装包结构可能已变化。"
          else
            dest="/Applications"
            if [ ! -w "$dest" ]; then
              dest="$HOME/Applications"
              mkdir -p "$dest" 2>"$copy_log" || dest=""
              [ -n "$dest" ] && warn "系统 Applications 不可写，将安装到当前用户目录：$dest"
            fi
            if [ -z "$dest" ]; then
              err "系统和用户 Applications 目录都不可写。"
              cat "$copy_log" 2>/dev/null
            elif ditto "$vol/Obsidian.app" "$dest/Obsidian.app" 2>"$copy_log"; then
              ok "Obsidian 安装成功：$dest/Obsidian.app"
              INSTALLED+=("Obsidian")
            else
              err "Obsidian 复制失败：$(tail -1 "$copy_log" 2>/dev/null)"
              failure_hint_from_log <"$copy_log"
            fi
          fi
          [ -z "$vol" ] || hdiutil detach "$vol" >/dev/null 2>&1
        fi
        rm -rf "$tmp_dir"
      fi
    fi
  fi
  obsidian_installed && return
  warn "自动安装未完成，请手动下载：双击 .dmg，把图标拖进 Applications"
  say "  ${CYN}https://obsidian.md/download${RST}"
  has_cmd open && open "https://obsidian.md/download" 2>/dev/null
  OPTIONAL_FAILED+=("Obsidian（请手动装）")
}

do_feishu_desktop(){
  step "飞书桌面版 —— 课程资料、学员群和 21 天挑战入口"
  if feishu_desktop_installed; then ok "飞书桌面版已安装"; SKIPPED+=("飞书桌面版"); return; fi
  ask_continue "现在安装飞书桌面版？" || { SKIPPED+=("飞书桌面版"); return; }
  if install_feishu_desktop; then INSTALLED+=("飞书桌面版")
  else
    err "飞书桌面版自动安装未完成。可从官网手动安装：https://www.feishu.cn/download"
    FAILED+=("飞书桌面版")
  fi
}

# ---------- 授权 / 登录 ----------
auth_phase(){
  hr; say "${BOLD}第二步：一个个带你登录 / 授权${RST}"; hr
  say "每个工具会打开浏览器或问你几个问题，跟着走就行。"
  say "${DIM}脚本不碰你的任何密码，所有登录都是你在官方页面自己完成。${RST}"

  if codex_ok; then
    step "1) Codex OAuth（用你的 ChatGPT 账号）"
    say "脚本不自动打开 OAuth 登录。需要官方账号登录时，之后手动运行：${BOLD}codex login${RST}"
    say "  ${DIM}远程/无浏览器环境可用：codex login --device-auth${RST}"
  fi

  if lark_ok; then
    step "2) 配置并授权 飞书 CLI"
    say "先初始化，再扫码 / 浏览器授权。"
    if ask_continue "现在配置并授权飞书 CLI？"; then
      if ! lark-cli config init --new </dev/tty; then
        warn "飞书初始化失败，未继续登录。稍后手动运行：lark-cli config init --new"
        OPTIONAL_FAILED+=("飞书初始化")
      elif ! lark-cli auth login --recommend </dev/tty; then
        warn "飞书授权失败或被取消。稍后手动运行：lark-cli auth login --recommend"
        OPTIONAL_FAILED+=("飞书授权")
      else
        ok "飞书初始化和授权流程已完成"
      fi
    fi
  fi

  if hermes_ok; then
    step "3) Hermes —— 装好就行，先不用配"
    ok "Hermes 命令行已就绪（hermes --version 能看到版本就成）。"
    say "  ${DIM}今晚不用急着选模型 / 订阅——那一步等你了解后再弄，免得不懂时误操作。${RST}"
    say "  Hermes 的模型 / provider 配置请按 Hermes 官方文档进行。"
  fi
}

# ---------- 图形界面：桌面客户端 ----------
do_clients(){
  step "图形界面：桌面客户端（按你的芯片）"

  # 1) ChatGPT 桌面 App——新版已内含 Codex，macOS 14+ 支持 Apple Silicon / Intel
  echo
  if codex_desktop_app_installed; then
    ok "ChatGPT 桌面 App（内含 Codex）已安装"
  elif codex_app_supported_on_mac "$ARCH" "$MACOS_MAJOR"; then
    local cxbuild="Apple Silicon 版"; [ "$ARCH" != "arm64" ] && cxbuild="Intel 版"
    say "${BOLD}1) ChatGPT 桌面 App${RST}（内含 Codex，需要 macOS 14+）"
    say "  你的电脑是 $CHIP，脚本会下载 OpenAI 官方 ${BOLD}$cxbuild${RST}，验证签名后自动安装。"
    if ask_continue "现在自动安装 ChatGPT 桌面 App（内含 Codex）？（需 ChatGPT 账号）"; then
      if install_codex_desktop_app; then
        INSTALLED+=("ChatGPT 桌面 App（内含 Codex）")
      else
        warn "自动安装未完成。可在官方页面手动下载：https://chatgpt.com/download/"
        has_cmd open && open "https://chatgpt.com/download/" 2>/dev/null
      fi
    fi
    say "  ${DIM}不想装桌面 App 也可以，命令行 Codex 不受影响。${RST}"
  else
    say "${BOLD}1) ChatGPT 桌面 App（内含 Codex）${RST}"
    warn "当前 macOS $MACOS_VER 不支持新版 ChatGPT 桌面 App（需要 macOS 14+），已安全跳过。"
  fi

  # 2) Hermes 桌面 App —— CLI 的图形外壳，比命令行友好
  echo
  say "${BOLD}2) Hermes 桌面 App${RST}（图形界面，比命令行友好；和命令行 Hermes 共享同一份配置）"
  if ! hermes_supported_on_mac "$ARCH" "$MACOS_MAJOR"; then
    warn "当前 Mac 不在 Hermes 官方支持范围内，桌面 App 也已跳过。"
  elif [ -d "/Applications/Hermes.app" ]; then
    ok "Hermes 桌面 App 已安装"
  elif hermes_ok; then
    say "  你已装命令行 Hermes，可用官方命令 ${BOLD}hermes desktop${RST} 构建并打开桌面 App（首次几分钟，会显示实时输出和耗时）。"
    if ask_continue "现在构建并打开 Hermes 桌面 App？（完成后脚本再继续）"; then
      if run_with_elapsed "Hermes 桌面 App 构建" hermes desktop; then
        ok "Hermes 桌面 App 构建流程已结束；如成功会自动打开。"
      else
        warn "Hermes 桌面 App 构建失败；可去 https://hermes-agent.nousresearch.com/desktop 下载安装包。"
      fi
    fi
  else
    if ask_continue "下载并打开 Hermes 桌面 App 安装包？"; then
      local desktop_tmp dmg
      desktop_tmp=$(mktemp -d "${TMPDIR:-/tmp}/navigator-hermes-desktop.XXXXXX") || { warn "无法创建 Hermes 桌面安装包临时目录。"; return; }
      dmg="$desktop_tmp/Hermes-Setup.dmg"
      if download_with_progress "Hermes 桌面 App（约 7MB）" "https://hermes-assets.nousresearch.com/Hermes-Setup.dmg" "$dmg" 300 && [ -s "$dmg" ] && hdiutil verify "$dmg" >/dev/null 2>&1; then
        open "$dmg" 2>/dev/null
        say "  ${DIM}安装包已通过 DMG 完整性校验。在弹出的窗口里把 Hermes 图标拖进「应用程序」；临时文件位于 $desktop_tmp。${RST}"
      else
        warn "Hermes 桌面安装包下载失败：可能是网络、代理/TLS、权限、磁盘空间或安全软件拦截。可手动下载：https://hermes-agent.nousresearch.com/desktop"
        rm -rf "$desktop_tmp"
      fi
    fi
  fi
}

# ---------- 小结 ----------
summary(){
  hr; say "${BOLD}安装小结${RST}"; hr
  if [ ${#INSTALLED[@]} -gt 0 ]; then ok "本次新装好："; for x in "${INSTALLED[@]}"; do say "    • $x"; done; fi
  if [ ${#SKIPPED[@]}  -gt 0 ]; then say "${DIM}⏭  跳过 / 本来就有：${RST}"; for x in "${SKIPPED[@]}"; do say "    • $x"; done; fi
  if [ ${#FAILED[@]}   -gt 0 ]; then err "还没搞定（需处理）："; for x in "${FAILED[@]}"; do say "    • $x"; done
    say "  ${YLW}把上面这几行截图发到群里，会帮你看。${RST}"; fi
  if [ ${#OPTIONAL_FAILED[@]} -gt 0 ]; then warn "可选工具未完成（不影响深圳课程就绪）："; for x in "${OPTIONAL_FAILED[@]}"; do say "    • $x"; done; fi
}

show_course_readiness(){
  local root direction
  root=$(resolve_course_root)
  hr; say "${BOLD}最后确认：深圳大课课前清单${RST}"; hr
  codex_ok && ok "Codex CLI 可用" || err "Codex CLI 未就绪"
  lark_ok && ok "飞书 CLI（可选）可用" || say "  ◦ 飞书 CLI（可选）未就绪"
  lark_skills_ok && ok "飞书官方 Agent Skills（可选）已就绪" || say "  ◦ 飞书官方 Agent Skills（可选）未补齐"
  node_ok && ok "Node.js / npm（可选依赖）可用" || say "  ◦ Node.js / npm（可选依赖）未就绪"
  feishu_desktop_installed && ok "飞书桌面版已安装" || err "飞书桌面版未安装"
  [ "${COURSE_NETWORK_OK:-0}" = 1 ] && ok "Google / GitHub 课程网络可用" || err "Google / GitHub 课程网络未通过"
  course_disk_space_ok "$root" && ok "课程磁盘空间不少于 10GB" || err "课程磁盘空间不足或无法读取"
  course_workspace_ready "$root" && ok "课程五个文件夹已就绪" || err "课程五个文件夹未就绪"
  direction=$(find "$root" -type f -name '*方向清单*' -print -quit 2>/dev/null)
  [ -n "$direction" ] && ok "方向清单已找到" || err "方向清单未找到"
  course_prework_files_ready "$root" && ok "课前四份文件已齐" || err "课前四份文件未齐"
  course_data_package_ready "$root" && ok "课程 ABA 数据包已解压就绪" || err "课程 ABA 数据包未解压或不足约 2GB"
  say "${DIM}以上不代表付费账号、连续对话、卖家精灵注册、网口/热点或作业提交已经完成。${RST}"
}

show_manual_checklist(){
  hr; say "${BOLD}还需本人确认（脚本无法可靠代检）${RST}"; hr
  say "  □ Google 账号可用；ChatGPT Plus / Pro 已就绪，Codex 能连续对话 5 轮"
  say "  □ 卖家精灵已注册，并在自检表填写同一注册邮箱"
  say "  □ 跨境适配度测试已提交；裸问回答和课前作业三件套已提交"
  say "  □ 自带网口或转换器已用网线测试；手机热点可作为备用网络"
  say "  ${CYN}卖家精灵注册：https://open.sellersprite.com/mcp${RST}"
  say "  ${CYN}课前自检表：https://scys.com/form/z27Vz6Fl${RST}"
}

show_native_result(){
  local status="$1"
  [ "${NO_NATIVE_DIALOG:-0}" = 1 ] && return 0
  has_cmd osascript || return 0
  if [ "$status" = ready ]; then
    osascript -e 'display dialog "深圳大课自动环境检查通过。\n仍需本人确认：Codex连续对话5轮、卖家精灵注册、作业提交、网口和手机热点。" buttons {"知道了"} default button "知道了" with title "深圳大课环境体检"' >/dev/null 2>&1 || true
  else
    osascript -e 'display dialog "深圳大课课前环境仍有待处理项。\n请查看终端中的最终清单并截图发给助教。" buttons {"知道了"} default button "知道了" with icon caution with title "深圳大课环境体检"' >/dev/null 2>&1 || true
  fi
}

# ---------- 主流程 ----------
banner(){
  say "${BOLD}════════════════════════════════════════════${RST}"
  say "${BOLD}   航海家 · AI 工具一键部署助手${RST}"
  say "${BOLD}════════════════════════════════════════════${RST}"
}

main(){
  if [ "${1:-}" = "--check" ]; then
    banner; check_network; detect; show_course_readiness; show_manual_checklist; echo; say "（这是只检测模式，没有安装任何东西；人工确认项不计入自动退出码）"
    if course_ready; then show_native_result ready; return 0; else show_native_result action_required; return 1; fi
  fi

  # curl | bash 运行时仍需交互授权，必须有可用的终端
  if [ ! -r /dev/tty ]; then
    banner
    err "需要在「终端」窗口里运行（脚本要带你登录授权）。"
    say "请打开「终端」App，把那行 curl 命令粘贴进去执行。"
    say "${DIM}只想检测不安装：在 curl 命令末尾加  ${RST}${BOLD}| bash -s -- --check${RST}"
    exit 1
  fi

  clear 2>/dev/null
  banner
  say "这个脚本帮你检测、安装深圳大课要用的工具，并检查课前环境。"
  say "工具都从${BOLD}各家官方源${RST}下载，脚本里不含任何密钥。"
  say "按提示${BOLD}回车${RST}即可；不想装某个就输 ${BOLD}s${RST} 跳过；想退出输 ${BOLD}q${RST}。"
  say "${DIM}脚本不会动你的密码，所有登录都在官方页面由你自己完成。${RST}"
  check_network
  repair_path_if_body_found
  detect
  if course_ready; then
    hr; ok "${BOLD}安装检查通过，不代表已经登录：主力命令行工具无需重新安装。${RST}"
    say "  ${DIM}已确认 Codex、飞书桌面版、网络、空间、课前四份文件和课程数据包均通过。${RST}"
    say "  ${DIM}飞书 CLI、Hermes、Obsidian 和 Node.js 是可选增强，不影响深圳课程自动就绪。${RST}"
    if ask_continue "检查 / 安装可选增强工具（飞书 CLI、Hermes、Obsidian）？"; then
      do_larkcli
      do_hermes
      do_obsidian
    fi
    do_clients
    ask_continue "进入登录 / 授权检查？" && auth_phase
    summary
    if [ ${#FAILED[@]} -gt 0 ]; then
      hr; err "安装本体可用，但登录 / 授权仍有未完成项。"
      show_native_result action_required
      return 1
    fi
    hr; ok "安装检查结束；请按上方提示完成账号登录。"
    show_native_result ready
    return 0
  fi
  hr; say "${BOLD}第一步：逐个检查并安装${RST}"; hr
  ask_continue "开始安装流程？" || { say "好的，下次再来。已装好的不会重复装。"; exit 0; }

  if ! setup_workspace; then summary; return 1; fi
  ensure_base_deps
  do_codex
  do_feishu_desktop
  do_larkcli
  do_hermes
  do_obsidian
  do_clients
  repair_path_if_body_found
  echo
  ask_continue "进入第二步：登录授权？" && auth_phase
  summary
  show_course_readiness
  show_manual_checklist

  if [ ${#FAILED[@]} -gt 0 ] || ! course_ready; then
    hr; err "流程结束，但仍有必需项未完成；本次不能标记为全部就绪。"
    say "请处理上面的具体错误后重跑；已验证可用的工具会自动跳过。"
    show_native_result action_required
    return 1
  fi
  hr; ok "安装流程完成；本机支持范围内的命令均已通过版本检测。"
  say "建议：${BOLD}关掉这个终端窗口，重新开一个${RST}，再运行各工具的 --version，并按上方提示确认账号登录。"
  show_native_result ready
  return 0
}

if [ "${INSTALLER_LIB_ONLY:-0}" != "1" ]; then
  main "$@"
fi
