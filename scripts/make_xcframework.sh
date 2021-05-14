#!/bin/zsh

set -euo pipefail

readonly BUILD_DIR="build"
readonly OUTPUT_DIR="${BUILD_DIR}/output"

clone() {
    readonly VERSION="${1}"
    git clone --branch "${VERSION}" --depth 1 https://github.com/krzyzanowskim/OpenSSL.git "${BUILD_DIR}/${VERSION}"
}

build_xcframework() {
    readonly VERSION="${1}"
    readonly OPENSSL_OUTPUT_DIR="${BUILD_DIR}/${VERSION}/Frameworks"

    # Clean the openssl output directory (they have it in source control)
    rm -rf "${OPENSSL_OUTPUT_DIR}"
    mkdir -p "${OPENSSL_OUTPUT_DIR}"

    # Create xcframework using the openssl script
    (cd "${BUILD_DIR}/${VERSION}" && ./scripts/create-frameworks.sh)

    # The generated xcframework contains slices for macos and macosx_catalyst.
    # We dont need those, so instead create our own xcframework with just the iphoneos
    # and iphonesimulator slices
    xcrun xcodebuild -quiet -create-xcframework \
        -framework "${OPENSSL_OUTPUT_DIR}/iphoneos/OpenSSL.framework" \
        -framework "${OPENSSL_OUTPUT_DIR}/iphonesimulator/OpenSSL.framework" \
        -output "${OUTPUT_DIR}/OpenSSL.xcframework"
}

build_1_1_1100() {
    clone 1.1.1100
    build_xcframework 1.1.1100
}

rm -rf "${BUILD_DIR}"
"$@"
