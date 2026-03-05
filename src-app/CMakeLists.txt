# Example application using ptpd library

# -----------------------------------------------------------------------
# Utility library — pure C, no ptpd/swclock deps, linkable from tests
# -----------------------------------------------------------------------
add_library(ptpd_app_utils STATIC macos/ptpd_app_utils.c)
target_include_directories(ptpd_app_utils PUBLIC
	${CMAKE_CURRENT_SOURCE_DIR}/macos)

# -----------------------------------------------------------------------
# Build ptpd-app executable
# -----------------------------------------------------------------------
add_executable(ptpd-app macos/ptpd-app.c)

# Include directories for headers
# Build directory MUST come first to find config.h
target_include_directories(ptpd-app PRIVATE
	${PROJECT_BINARY_DIR}
	${CMAKE_SOURCE_DIR}/src
)

# Add HAVE_CONFIG_H definition
target_compile_definitions(ptpd-app PRIVATE HAVE_CONFIG_H)

# swclock support: add headers, compile define, and library link
if(BUILD_WITH_SWCLOCK)
	target_include_directories(ptpd-app PRIVATE
		${CMAKE_SOURCE_DIR}/libraries/swclock/src/sw_clock
	)
	target_compile_definitions(ptpd-app PRIVATE PTPD_USE_SWCLOCK)
	target_link_libraries(ptpd-app PRIVATE swclock)
endif()

# Link against shared library by default, fall back to static
if(TARGET ptpd-shared)
	target_link_libraries(ptpd-app PRIVATE ptpd-shared ptpd_app_utils)
else()
	target_link_libraries(ptpd-app PRIVATE ptpd-static ptpd_app_utils)
endif()

# Install example app
install(TARGETS ptpd-app
	RUNTIME DESTINATION ${CMAKE_INSTALL_SBINDIR}
)
