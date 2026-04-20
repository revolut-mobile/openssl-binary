#!/bin/zsh

set -euo pipefail

readonly BUILD_DIR="build"
readonly OUTPUT_DIR="${BUILD_DIR}/output"

clone() {
    readonly VERSION="${1}"
    git clone --branch "${VERSION}" --depth 1 https://github.com/krzyzanowskim/OpenSSL.git "${BUILD_DIR}/${VERSION}"
}

patch() {
    readonly VERSION="${1}"

    if [ -d "patches/${VERSION}" ]; then
        echo "Found patches for ${VERSION}, applying..."

        pushd "${BUILD_DIR}/${VERSION}" > /dev/null

        setopt local_options null_glob
        for p in ../../patches/${VERSION}/*.patch ../../patches/${VERSION}/*.diff; do
            [[ -f "$p" ]] || continue
            echo "Applying patch: $(basename "$p")"
            git apply --ignore-whitespace "$p"
        done

        popd > /dev/null
        echo "All patches applied for ${VERSION}"
    fi
}

# Parse VAR=value from the cloned upstream Makefile (first match).
read_makefile_var() {
    local file="$1"
    local key="$2"
    grep "^${key}=" "${file}" | head -1 | cut -d= -f2- | tr -d '[:space:]'
}

rebuild_upstream_frameworks() {
    readonly VERSION="${1}"
    readonly ROOT="${BUILD_DIR}/${VERSION}"
    readonly MAKEFILE="${ROOT}/Makefile"

    if [[ ! -f "${MAKEFILE}" ]]; then
        echo "error: missing ${MAKEFILE}" >&2
        exit 1
    fi

    local openssl_version
    openssl_version=$(read_makefile_var "${MAKEFILE}" OPENSSL_VERSION)
    local marketing_version
    marketing_version=$(read_makefile_var "${MAKEFILE}" MARKETING_VERSION)

    if [[ -z "${openssl_version}" ]]; then
        echo "error: could not parse OPENSSL_VERSION from ${MAKEFILE}" >&2
        exit 1
    fi
    if [[ -z "${marketing_version}" ]]; then
        echo "error: could not parse MARKETING_VERSION from ${MAKEFILE}" >&2
        exit 1
    fi

    echo "Running scripts/build.sh with OPENSSL_VERSION=${openssl_version}"
    (
        cd "${ROOT}"
        export OPENSSL_VERSION="${openssl_version}"
        ./scripts/build.sh
    )

    if ! command -v tuist >/dev/null 2>&1; then
        echo "error: tuist not found in PATH. Install: https://docs.tuist.io" >&2
        exit 1
    fi

    echo "Running tuist generate with MARKETING_VERSION=${marketing_version}"
    (
        cd "${ROOT}"
        export TUIST_MARKETING_VERSION="${marketing_version}"
        tuist generate --no-open --cache-profile none
    )

    readonly FWNAME="OpenSSL"
    echo "Building ${FWNAME} (iOS) and (iOS Simulator) frameworks"

    local derived
    derived=$(mktemp -d)
    xcrun xcodebuild build -quiet \
        -project "${ROOT}/${FWNAME}.xcodeproj" \
        -configuration Release \
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGN_IDENTITY="" \
        ARCHS="arm64 arm64e" \
        -scheme "${FWNAME} (iOS)" \
        -derivedDataPath "${derived}" \
        -destination 'generic/platform=iOS'

    rm -rf "${ROOT}/Frameworks/iphoneos"
    mkdir -p "${ROOT}/Frameworks/iphoneos"
    ditto "${derived}/Build/Products/Release-iphoneos/${FWNAME}.framework" "${ROOT}/Frameworks/iphoneos/${FWNAME}.framework"
    if [[ -d "${derived}/Build/Products/Release-iphoneos/${FWNAME}.framework.dSYM" ]]; then
        ditto "${derived}/Build/Products/Release-iphoneos/${FWNAME}.framework.dSYM" "${ROOT}/Frameworks/iphoneos/${FWNAME}.framework.dSYM"
    fi
    rm -rf "${derived}"

    derived=$(mktemp -d)
    xcrun xcodebuild build -quiet \
        -project "${ROOT}/${FWNAME}.xcodeproj" \
        -configuration Release \
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGN_IDENTITY="" \
        -scheme "${FWNAME} (iOS Simulator)" \
        -derivedDataPath "${derived}" \
        -destination 'generic/platform=iOS Simulator'

    rm -rf "${ROOT}/Frameworks/iphonesimulator"
    mkdir -p "${ROOT}/Frameworks/iphonesimulator"
    ditto "${derived}/Build/Products/Release-iphonesimulator/${FWNAME}.framework" "${ROOT}/Frameworks/iphonesimulator/${FWNAME}.framework"
    if [[ -d "${derived}/Build/Products/Release-iphonesimulator/${FWNAME}.framework.dSYM" ]]; then
        ditto "${derived}/Build/Products/Release-iphonesimulator/${FWNAME}.framework.dSYM" "${ROOT}/Frameworks/iphonesimulator/${FWNAME}.framework.dSYM"
    fi
    rm -rf "${derived}"

    echo "iphoneos binary architectures:"
    lipo -info "${ROOT}/Frameworks/iphoneos/${FWNAME}.framework/${FWNAME}"
}

build_xcframework() {
    readonly VERSION="${1}"
    readonly OPENSSL_OUTPUT_DIR="${BUILD_DIR}/${VERSION}/Frameworks"

    # The generated xcframework contains slices for macos and macosx_catalyst (and many more).
    # We dont need those, so instead create our own xcframework with just the iphoneos
    # and iphonesimulator slices
    xcrun xcodebuild -quiet -create-xcframework \
        -framework "${OPENSSL_OUTPUT_DIR}/iphoneos/OpenSSL.framework" \
        -framework "${OPENSSL_OUTPUT_DIR}/iphonesimulator/OpenSSL.framework" \
        -output "${OUTPUT_DIR}/OpenSSL.xcframework"
}

build() {
    clone "$@"
    patch "$@"
    rebuild_upstream_frameworks "$@"
    build_xcframework "$@"
}

rm -rf "${BUILD_DIR}"
"$@"
