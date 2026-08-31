#!/bin/bash

# 遇到错误立即退出
set -e

# 切换到脚本所在目录
cd "$(dirname "$0")"

function show_menu() {
    echo "================================="
    echo "请选择构建类型 / Select build type:"
    echo "1) 传统 / Traditional (rootful)"
    echo "2) Rootless"
    echo "3) Roothide"
    echo "4) 全部构建 / Build All"
    echo "0) 退出 / Exit"
    echo "================================="
}

function clean_packages() {
    echo ">>> 清理历史构建包..."
    rm -rf packages/*
    echo ">>> 清理完成"
}

function build_traditional() {
    echo ""
    echo ">>> 开始构建 Traditional 版本..."
    make clean
    make package FINALPACKAGE=1
    echo ">>> Traditional 版本构建完成"
    echo ""
}

function build_rootless() {
    echo ""
    echo ">>> 开始构建 Rootless 版本..."
    make clean
    THEOS_PACKAGE_SCHEME=rootless make package FINALPACKAGE=1
    echo ">>> Rootless 版本构建完成"
    echo ""
}

function build_roothide() {
    echo ""
    echo ">>> 开始构建 Roothide 版本..."
    make clean
    THEOS_PACKAGE_SCHEME=roothide make package FINALPACKAGE=1
    echo ">>> Roothide 版本构建完成"
    echo ""
}

# 如果有参数，直接执行对应动作
if [ -n "$1" ]; then
    clean_packages
    case "$1" in
        "traditional")
            build_traditional
            ;;
        "rootless")
            build_rootless
            ;;
        "roothide")
            build_roothide
            ;;
        "all")
            build_traditional
            build_rootless
            build_roothide
            ;;
        *)
            echo "用法 / Usage: $0 {traditional|rootless|roothide|all}"
            exit 1
            ;;
    esac
    exit 0
fi

# 交互式菜单
while true; do
    show_menu
    read -p "请输入选项 [0-4]: " choice
    if [[ "$choice" =~ ^[1-4]$ ]]; then
        clean_packages
    fi
    case $choice in
        1)
            build_traditional
            break
            ;;
        2)
            build_rootless
            break
            ;;
        3)
            build_roothide
            break
            ;;
        4)
            build_traditional
            build_rootless
            build_roothide
            break
            ;;
        0)
            echo "已退出"
            exit 0
            ;;
        *)
            echo "无效选项，请重新输入"
            ;;
    esac
done
