BUILD_VERSION ?= 3.3.3001

distribute:
	scripts/make_xcframework.sh build "$(BUILD_VERSION)"
