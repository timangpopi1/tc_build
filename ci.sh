#!/usr/bin/env bash

base=$(dirname "$(readlink -f "$0")")

set -eu

function parse_parameters() {
    while (($#)); do
        case $1 in
            all | binutils | deps | kernel | llvm) action=$1 ;;
            *) exit 33 ;;
        esac
        shift
    done
}

function do_all() {
    do_deps
    do_llvm
    do_binutils
    do_kernel
}

function do_binutils() {
    "$base"/build-binutils.py -t x86_64
}

function do_deps() {
    # We only run this when running on GitHub Actions
    [[ -z ${GITHUB_ACTIONS:-} ]] && return 0
    export PATH=/usr/bin/core_perl:$PATH
    git config --global user.name "greenforce-bot"
    git config --global user.email "85951498+greenforce-bot@users.noreply.github.com"
    mkdir -p ~/.git/hooks/
    wget "https://github.com/fadlyas07/Scripts/raw/master/github/commit-msg"
    mv commit-msg ~/.git/hooks/ && chmod +x ~/.git/hooks/commit-msg
    git config --global core.hooksPath ~/.git/hooks
    wget "https://github.com/fadlyas07/Scripts/raw/master/github/github-release"
    sudo chmod +x github-release
    get_distro_name=$(source /etc/os-release && echo ${NAME})
    if [[ "$get_distro_name" == "Ubuntu" ]]; then
    sudo apt-get install -y --no-install-recommends \
        bc \
        bison \
        ca-certificates \
        clang \
        cmake \
        curl \
        file \
        flex \
        gcc \
        g++ \
        git \
        libelf-dev \
        libssl-dev \
        lld \
        make \
        ninja-build \
        python3 \
        texinfo \
        xz-utils \
        zlib1g-dev
    fi
}

function do_kernel() {
    cd "$base"/kernel
    ./build.sh -t X86
}

function do_llvm() {
    extra_args=()
    [[ -n ${GITHUB_ACTIONS:-} ]] && extra_args+=(--no-ccache)

    "$base"/build-llvm.py \
        --assertions \
        --branch "release/14.x" \
        --build-stage1-only \
        --check-targets clang lld llvm \
        --install-stage1-only \
        --projects "clang;lld" \
        --shallow-clone \
        --targets X86 \
        "${extra_args[@]}"
}

parse_parameters "$@"
do_"${action:=all}"
