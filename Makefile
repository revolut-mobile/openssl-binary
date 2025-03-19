BUILD_VERSION ?= 1.1.2301

distribute:
	Scripts/make_xcframework.sh build "$(BUILD_VERSION)"
