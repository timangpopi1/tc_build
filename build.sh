#!/usr/bin/env bash
#
# Copyright (C) 2022 fadlyas07 <mhmmdfdlyas@gmail.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# Set a directory
DIR="$(pwd ...)"

# Setup about github-release
curl -Lo $(pwd)/gh-release https://github.com/ZyCromerZ/tc-build/raw/main/github-release
[ -f "$(pwd)/gh-release" ] && chmod u+x $(pwd)/gh-release

# clone push repo
git clone --single-branch "https://fadlyas07:$GH_TOKEN@github.com/greenforce-project/clang-llvm" -b main --depth=1

# clone LLVM repo
git clone --single-branch "https://github.com/llvm/llvm-project" -b main --depth=1

# Simplify clang version
path="llvm-project/clang/lib/Basic/Version.cpp"
sed -i 's/return CLANG_REPOSITORY_STRING;/return "";/g' $path
sed -i 's/return CLANG_REPOSITORY;/return "";/g' $path
sed -i 's/return LLVM_REPOSITORY;/return "";/g' $path
sed -i 's/return CLANG_REVISION;/return "";/g' $path
sed -i 's/return LLVM_REVISION;/return "";/g' $path

# Build LLVM
JobsTotal="$(($(nproc)*2))"
./build-llvm.py \
    --clang-vendor "greenforce" \
    --defines "LLVM_PARALLEL_COMPILE_JOBS=$JobsTotal LLVM_PARALLEL_LINK_JOBS=$JobsTotal CMAKE_C_FLAGS=-O3 CMAKE_CXX_FLAGS=-O3 LLVM_USE_LINKER=lld LLVM_ENABLE_LLD=ON" \
    --projects "clang;compiler-rt;lld;polly" \
    --incremental \
    --no-update \
    --targets "ARM;AArch64" || status="failed"
    
if [ $status != "failed" ]; then
    status="success"
fi

# Build binutils
./build-binutils.py --targets arm aarch64

# Remove unused products
rm -fr install/include #install/lib/libclang-cpp.so.15git
rm -f install/lib/*.a install/lib/*.la

# Strip remaining products
for f in $(find install -type f -exec file {} \; | grep 'not stripped' | awk '{print $1}'); do
    strip -s "${f: : -1}"
done

# Set executable rpaths so setting LD_LIBRARY_PATH isn't necessary
for bin in $(find install -mindepth 2 -maxdepth 3 -type f -exec file {} \; | grep 'ELF .* interpreter' | awk '{print $1}'); do
    # Remove last character from file output (':')
    bin="${bin: : -1}"

    echo "$bin"
    patchelf --set-rpath "$DIR/install/lib" "$bin"
done

# Release Info
rel_date="$(date '+%Y%m%d')" # ISO 8601 format
rel_time="$(date +'%H%M')" # HoursMinute
rel_friendly_date="$(date '+%B %-d, %Y')" # "Month day, year" format

pushd $(pwd)/llvm-project
commit_msg=$(git log --pretty="format:%s" | head -n1)
short_llvm_commit="$(git rev-parse --short HEAD)"
popd
llvm_commit_url="https://github.com/llvm/llvm-project/commit/$short_llvm_commit"

binutils_version="$(ls | grep "^binutils-" | sed "s/binutils-//g")"
clang_version="$(install/bin/clang --version | head -n1)"
rel_msg="Automated build of LLVM + Clang $clang_version as of commit [$short_llvm_commit]($llvm_commit_url) and binutils $binutils_version."

# Push to GitHub
# Update Git repository
#files="clang-$clang_version-$rel_date-$rel_time.tar.gz"

git config --global user.name "greenforce-auto-build"
git config --global user.email "greenforce-auto-build@users.noreply.github.com"

pushd $(pwd)/clang-llvm
rm -rf *
cp -r ../install/* .
git add -f .
template=$(echo -e "
------------CLANG-INFO-BEGIN------------
Clang version: $clang_version
Binutils version: $binutils_version
LLVM repo commit: $commit_msg
Link: $llvm_commit_url
--------------CLANG-INFO-END--------------
")

git commit -m "greenforce: Bump to $(date '+%Y%m%d') build" -m "$template"
git push
popd

#tar -czf "$files" $(pwd)/clang-llvm/*
echo "$rel_msg" >> body

if [ $status == success ]; then
    pushtag() {
        ./github-release release \
            --security-token "$GH_TOKEN" \
            --user "greenforce-project" \
            --repo "clang-llvm" \
            --tag "$rel_date" \
            --name "$rel_friendly_date" \
            --description "$(cat body)" || echo "Tag already exists"
    }
    if [ $(pushtag) == "Tag already exists" ]; then
        if ! [ -f "$(pwd)/gh-release" ]; then
            echo "gh-release file not found, pls check it!" && exit
        else
            chmod +x $(pwd)/gh-release
            sleep 10
            pushtag || echo "Failed again, Tag is already exists!"
        fi
    fi
fi

#./github-release upload \
    #--security-token "$GITHUB_TOKEN" \
    #--user "greenforce-project" \
    #--repo "clang-llvm" \
    #--tag "$rel_date" \
    #--name "$files" \
    #--file "$files" || echo "Maybe failed :/" && status_push="confused"
