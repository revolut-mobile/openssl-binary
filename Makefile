BUILD_VERSION ?= 3.3.3001

distribute:
	Scripts/make_xcframework.sh build "$(BUILD_VERSION)"
