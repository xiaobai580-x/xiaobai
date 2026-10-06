#!/system/bin/sh
set -eu
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m'
R=$(printf '\033[0;31m'); G=$(printf '\033[0;32m')
Y=$(printf '\033[1;33m'); B=$(printf '\033[1;36m'); N=$(printf '\033[0m')
PASS=0; WARN=0; FAIL=0; SKIP=0; TOTAL=0

# 新增: SKIP 状态 - 用于检测项被忽略时(如GPU信息不可用)
_pass()  { PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); printf "  ${GREEN}[PASS]${NC} %s\n" "$1"; }
_warn()  { WARN=$((WARN+1)); TOTAL=$((TOTAL+1)); printf "  ${YELLOW}[WARN]${NC} %s\n" "$1"; }
_fail()  { FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); printf "  ${RED}[FAIL]${NC} %s\n" "$1"; }
_skip()  { SKIP=$((SKIP+1)); TOTAL=$((TOTAL+1)); printf "  ${WHITE}[SKIP]${NC} %s\n" "$1"; }
_info()  { printf "  ${CYAN}  >${NC} %s\n" "$1"; }
_hdr()   { echo ""; sleep 1 ; echo "==================================================";  echo "  $1"; echo "=================================================="; sleep 0; }
_sub()   { echo ""; echo "-- $1 --"; }

# ── 全局变量 ──
IS_ROOTED=false
PROP_MATCH=false
CPU_MATCH=false
GPU_MATCH=false              # z.f() GPU 白名单匹配结果 (不再硬编码!)
DEVICE_CHECK_RESULT=-1
CPU_LOCK_STATUS=0
CORE_COUNT=0
LOW_FREQ_CORES=0
OFFLINE_CORES=0
CPU_HARDWARE=""
GLOBAL_MAX_FREQ=0
# 新增: 设备树检测变量 (UPDATE 2026-07-13)
DEVICE_TREE_COMPATIBLE=""    # /proc/device-tree/compatible 内容
DEVICE_TREE_MATCH=false      # 设备树白名单匹配结果 (kirin等)
DEVICE_TREE_AVAILABLE=false  # 设备树节点是否可读
# ── GPU 全局变量 (严格模拟 DataRecorder + z.f() 原逻辑) ──
GPU_RENDERER=""              # GL_RENDERER — DataRecorder.mobileGPUType 等价字段
GPU_VENDOR=""                # GL_VENDOR
GPU_VERSION=""               # GL_VERSION (OpenGL ES 版本)
GPU_TYPE=""                  # 最终匹配用的 GPU 类型字符串
GPU_FREQ=0                   # GPU 当前频率 (KHz)
GPU_MAX_FREQ=0               # GPU 最大频率 (KHz)
GPU_MIN_FREQ=0               # GPU 最小频率 (KHz)
GPU_TEMP=0                   # GPU 温度 (m°C, sensor)
GPU_LOAD=0                   # GPU 使用率 (%)
GPU_SOC_PLATFORM=""          # SoC 平台 (ro.board.platform: sdm845, mt6877…)
GPU_DRIVER_VERSION=""        # GPU 驱动版本 (ro.gpu.version)
GPU_ARCH_86=false            # x86 GPU 架构标记 (模拟器判定)
GPU_INFO_AVAILABLE=false     # GPU sysfs 节点是否可读
GPU_EGL_AVAILABLE=false      # EGL/GL 信息是否可用

# ═══════════════════════════════════════════════════════════════
#  PART 1: 工具函数 (模拟 FileUtil, SysProperty)
# ═══════════════════════════════════════════════════════════════
    echo
    printf "$G"
    cat <<'MAPLE_BANNER'
███╗   ███╗ █████╗ ██████╗ ██╗     ███████╗
████╗ ████║██╔══██╗██╔══██╗██║     ██╔════╝
██╔████╔██║███████║██████╔╝██║     █████╗
██║╚██╔╝██║██╔══██║██╔═══╝ ██║     ██╔══╝
██║ ╚═╝ ██║██║  ██║██║     ███████╗███████╗
╚═╝     ╚═╝╚═╝  ╚═╝╚═╝     ╚══════╝╚══════╝
MAPLE_BANNER
    printf "$N\n"
    printf "$B━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$N\n"
    printf "$B  MAPLE · 检测激活验证$N\n"
    printf "\n$B  『时光流转，愿你能与珍爱之人再度重逢』🍁$N\n\n"
    printf "$B  By.MapleAutumn$N\n"
    printf "$B━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$N\n"
    sleep 1
marker=
relative_marker=Android/media/com.maple.detect/MapleDetect/maple-verification.txt
for storage in "${EXTERNAL_STORAGE:-}" /storage/emulated/0 /sdcard "${HOME:-/data/local/tmp}/storage/shared"; do
    [ -n "$storage" ] || continue
    candidate="$storage/$relative_marker"
    if [ -f "$candidate" ]; then
        marker=$candidate
        break
    fi
done

if [ -z "$marker" ]; then
    printf '%s\n' '未找到Maple验证文件，请在验证页面打开MapleDetect，或使用Root权限执行此脚本！.' >&2
    exit 1
fi
if [ ! -r "$marker" ] || [ ! -w "$marker" ]; then
    printf '%s\n' '验证创建失败！请使用Root权限执行' >&2
    exit 1
fi

marker_bytes=$(wc -c < "$marker")
pending_bytes=$(printf '%s\n' 'maple-channel-pending-v1' | wc -c)
final_bytes=$(printf '%s\n' 'maple-channel-v1' | wc -c)

if [ "$(cat "$marker")" = 'maple-channel-v1' ] && [ "$marker_bytes" -eq "$final_bytes" ]; then
    printf '%s\n' '激活成功！'
    exit 0
fi

if [ "$(cat "$marker")" != 'maple-channel-pending-v1' ] || [ "$marker_bytes" -ne "$pending_bytes" ]; then
    printf '%s\n' "Invalid Maple verification file: $marker" >&2
    exit 1
fi

if ! printf '%s\n' 'maple-channel-v1' > "$marker"; then
    printf '%s\n' '验证创建失败！请使用Root权限执行' >&2
    exit 1
fi

marker_bytes=$(wc -c < "$marker")
if [ "$(cat "$marker")" != 'maple-channel-v1' ] || [ "$marker_bytes" -ne "$final_bytes" ]; then
    printf '%s\n' "验证创建失败！请使用Root权限执行" >&2
    exit 1
fi

printf '%s\n' '激活成功！'
