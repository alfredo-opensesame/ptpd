# Example application using ptpd library

# Build ptpd-app executable
add_executable(ptpd-app ptpd-app.c)

# Include directories for headers
# Build directory MUST come first to find config.h
target_include_directories(ptpd-app PRIVATE
	${PROJECT_BINARY_DIR}
	${CMAKE_SOURCE_DIR}/src
)

# Add HAVE_CONFIG_H definition
target_compile_definitions(ptpd-app PRIVATE HAVE_CONFIG_H)

# Link against shared library by default, fall back to static
if(TARGET ptpd-shared)
	target_link_libraries(ptpd-app PRIVATE ptpd-shared)
else()
	target_link_libraries(ptpd-app PRIVATE ptpd-static)
endif()

# Install example app
install(TARGETS ptpd-app
	RUNTIME DESTINATION ${CMAKE_INSTALL_SBINDIR}
)
