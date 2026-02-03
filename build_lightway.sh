#!/bin/bash

# Lightway MNN 一键构建脚本
# 构建 Android arm64-v8a 的 .so 文件，包含 LLM 和 OpenCL 支持

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 默认配置
BUILD_OPENCL=true
BUILD_QNN=false
OUTPUT_DIR="$SCRIPT_DIR/dist/arm64-v8a"
CLEAN_BUILD=false

print_usage() {
    echo "Lightway MNN 构建脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  --ndk PATH          Android NDK 路径 (必需，或设置 ANDROID_NDK 环境变量)"
    echo "  --no-opencl         不构建 OpenCL 后端"
    echo "  --qnn               构建 QNN 后端 (高通 NPU)"
    echo "  --output DIR        输出目录 (默认: dist/arm64-v8a)"
    echo "  --clean             清理后重新构建"
    echo "  -h, --help          显示帮助"
    echo ""
    echo "示例:"
    echo "  $0 --ndk ~/Android/Sdk/ndk/26.1.10909125"
    echo "  $0 --ndk ~/Android/Sdk/ndk/26.1.10909125 --no-opencl"
}

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --ndk)
            ANDROID_NDK="$2"
            shift 2
            ;;
        --no-opencl)
            BUILD_OPENCL=false
            shift
            ;;
        --qnn)
            BUILD_QNN=true
            shift
            ;;
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --clean)
            CLEAN_BUILD=true
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            echo -e "${RED}未知选项: $1${NC}"
            print_usage
            exit 1
            ;;
    esac
done

# 检查 NDK
if [ -z "$ANDROID_NDK" ]; then
    echo -e "${RED}错误: 请指定 Android NDK 路径 (--ndk 或设置 ANDROID_NDK 环境变量)${NC}"
    exit 1
fi

ANDROID_NDK="${ANDROID_NDK/#\~/$HOME}"
if [ ! -d "$ANDROID_NDK" ]; then
    echo -e "${RED}错误: NDK 路径不存在: $ANDROID_NDK${NC}"
    exit 1
fi

export ANDROID_NDK

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Lightway MNN 构建${NC}"
echo -e "${GREEN}========================================${NC}"
echo "NDK: $ANDROID_NDK"
echo "输出: $OUTPUT_DIR"
echo "OpenCL: $BUILD_OPENCL"
echo "QNN: $BUILD_QNN"
echo ""

# 创建构建目录
BUILD_DIR="$SCRIPT_DIR/build_lightway"
if [ "$CLEAN_BUILD" = true ] && [ -d "$BUILD_DIR" ]; then
    echo -e "${YELLOW}清理构建目录...${NC}"
    rm -rf "$BUILD_DIR"
fi
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# 构建 CMake 参数
CMAKE_ARGS=(
    -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake
    -DCMAKE_BUILD_TYPE=Release
    -DANDROID_ABI="arm64-v8a"
    -DANDROID_STL=c++_static
    -DANDROID_NATIVE_API_LEVEL=android-21
    -DANDROID_TOOLCHAIN=clang
    # 基础配置
    -DMNN_USE_LOGCAT=false
    -DMNN_BUILD_SHARED_LIBS=ON
    -DMNN_SEP_BUILD=OFF
    -DMNN_USE_SSE=OFF
    # LLM 支持
    -DMNN_BUILD_LLM=ON
    -DMNN_SUPPORT_TRANSFORMER_FUSE=ON
    -DMNN_LOW_MEMORY=ON
    -DMNN_CPU_WEIGHT_DEQUANT_GEMM=ON
    # ARM 优化
    -DMNN_ARM82=ON
    # 音视频支持
    -DLLM_SUPPORT_AUDIO=ON
    -DMNN_BUILD_AUDIO=ON
    -DLLM_SUPPORT_VISION=ON
    -DMNN_BUILD_OPENCV=ON
    -DMNN_IMGCODECS=ON
    # Diffusion 支持
    -DMNN_BUILD_DIFFUSION=ON
    # 输出路径
    -DMNN_BUILD_FOR_ANDROID_COMMAND=true
    -DNATIVE_LIBRARY_OUTPUT=.
    -DNATIVE_INCLUDE_OUTPUT=.
)

# OpenCL
if [ "$BUILD_OPENCL" = true ]; then
    CMAKE_ARGS+=(-DMNN_OPENCL=ON)
    echo -e "${GREEN}启用 OpenCL 后端${NC}"
else
    CMAKE_ARGS+=(-DMNN_OPENCL=OFF)
fi

# QNN
if [ "$BUILD_QNN" = true ]; then
    CMAKE_ARGS+=(-DMNN_QNN=ON -DMNN_WITH_PLUGIN=ON)
    echo -e "${GREEN}启用 QNN 后端${NC}"
else
    CMAKE_ARGS+=(-DMNN_QNN=OFF)
fi

# 运行 CMake
echo -e "${GREEN}配置 CMake...${NC}"
cmake "$SCRIPT_DIR" "${CMAKE_ARGS[@]}"

# 构建
echo -e "${GREEN}开始构建...${NC}"
make -j$(nproc) MNN

if [ "$BUILD_OPENCL" = true ]; then
    make -j$(nproc) MNN_CL 2>/dev/null || true
fi

if [ "$BUILD_QNN" = true ]; then
    make -j$(nproc) MNN_QNN 2>/dev/null || true
fi

# 复制输出
echo -e "${GREEN}复制输出文件...${NC}"
mkdir -p "$OUTPUT_DIR"

cp -v libMNN.so "$OUTPUT_DIR/" 2>/dev/null || true
cp -v libMNN_CL.so "$OUTPUT_DIR/" 2>/dev/null || true
cp -v libMNN_QNN.so "$OUTPUT_DIR/" 2>/dev/null || true

# 显示结果
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}构建完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo "输出文件:"
ls -lh "$OUTPUT_DIR"/*.so 2>/dev/null || echo "无 .so 文件"
echo ""
echo "使用方法:"
echo "  将 $OUTPUT_DIR 中的 .so 文件复制到你的项目中"
