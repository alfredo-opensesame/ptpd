# iOS PTP Monitor App
cmake_minimum_required(VERSION 3.25)

project(PTPMonitor LANGUAGES C OBJC Swift)

# iOS-specific settings
set(CMAKE_SYSTEM_NAME iOS)
set(CMAKE_OSX_DEPLOYMENT_TARGET "15.0")
set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64")  # Universal for simulator and device
set(CMAKE_XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH NO)
set(CMAKE_XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2")  # iPhone and iPad

# Enable Swift
enable_language(Swift)
set(CMAKE_Swift_LANGUAGE_VERSION 5.0)

# ptpd library (static, built with PTPD_IOS)
add_library(ptpdios STATIC IMPORTED)
set_target_properties(ptpdios PROPERTIES
    IMPORTED_LOCATION "${CMAKE_CURRENT_SOURCE_DIR}/../../build-cmake/ios-simulator/src/Debug-iphonesimulator/libptpd2.a"
)

# SwClock library (static)
add_library(swclock_ios STATIC IMPORTED)
set_target_properties(swclock_ios PROPERTIES
    IMPORTED_LOCATION "${CMAKE_CURRENT_SOURCE_DIR}/../../build-cmake/ios-simulator/libraries/swclock/Debug-iphonesimulator/libswclock.a"
)

# iOS App Bundle
add_executable(PTPMonitor MACOSX_BUNDLE
    PTPMonitorApp.swift
    ContentView.swift
    PTPManager.swift
    PTPBridge.m
    PTPBridge.h
)

target_include_directories(PTPMonitor PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../../src
    ${CMAKE_CURRENT_SOURCE_DIR}/../../libraries/swclock/src
)

target_link_libraries(PTPMonitor PRIVATE
    ptpdios
    swclock_ios
    "-framework Foundation"
    "-framework UIKit"
    m  # Math library
    pthread  # POSIX threads
    z  # Zlib
)

# Bridging Header
set_target_properties(PTPMonitor PROPERTIES
    XCODE_ATTRIBUTE_SWIFT_OBJC_BRIDGING_HEADER "${CMAKE_CURRENT_SOURCE_DIR}/PTPMonitor-Bridging-Header.h"
    XCODE_ATTRIBUTE_SWIFT_VERSION "5.0"
)

# App Bundle settings
set_target_properties(PTPMonitor PROPERTIES
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist"
    MACOSX_BUNDLE_BUNDLE_NAME "PTP Monitor"
    MACOSX_BUNDLE_BUNDLE_VERSION "1.0"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "1.0"
    MACOSX_BUNDLE_GUI_IDENTIFIER "com.example.ptpmonitor"
    XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "com.example.ptpmonitor"
    XCODE_ATTRIBUTE_INFOPLIST_FILE "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist"
)

# iOS-specific build settings
set_target_properties(PTPMonitor PROPERTIES
    XCODE_ATTRIBUTE_IPHONEOS_DEPLOYMENT_TARGET "15.0"
    XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY "iPhone Developer"
    XCODE_ATTRIBUTE_DEVELOPMENT_TEAM ""
    XCODE_ATTRIBUTE_ENABLE_BITCODE "NO"
)

# Define PTPD_IOS for the bridge
target_compile_definitions(PTPMonitor PRIVATE PTPD_IOS=1)
