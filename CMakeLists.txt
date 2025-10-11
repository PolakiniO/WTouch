cmake_minimum_required(VERSION 3.16)
project(wtouch LANGUAGES CXX)

include(GNUInstallDirs)

add_executable(wtouch src/touch.cpp)
target_compile_features(wtouch PRIVATE cxx_std_17)

if (MSVC)
    target_compile_options(wtouch PRIVATE /W4 /permissive-)
else()
    target_compile_options(wtouch PRIVATE -Wall -Wextra -Wpedantic)
endif()

if (WIN32)
    target_link_libraries(wtouch PRIVATE kernel32)
endif()

enable_testing()
if (WIN32)
    add_test(
        NAME wtouch_tests
        COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File "${CMAKE_CURRENT_LIST_DIR}/tests/test_touch.ps1" "$<TARGET_FILE:wtouch>"
    )
    set_tests_properties(wtouch_tests PROPERTIES WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR})
endif()

install(TARGETS wtouch
    RUNTIME DESTINATION .
)

if (WIN32)
    option(WTOUCH_INSTALL_ADD_TO_PATH "Append the install directory to the user PATH during installation" ON)

    if (WTOUCH_INSTALL_ADD_TO_PATH)
        set(_wtouch_install_helper "${CMAKE_CURRENT_LIST_DIR}/scripts/install-wtouch.ps1")
        file(TO_NATIVE_PATH "${_wtouch_install_helper}" INSTALLER_SCRIPT_NATIVE)
        string(REPLACE "\\" "\\\\" INSTALLER_SCRIPT_NATIVE "${INSTALLER_SCRIPT_NATIVE}")
        file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/cmake")
        configure_file(
            "${CMAKE_CURRENT_LIST_DIR}/cmake/add-to-path.cmake.in"
            "${CMAKE_CURRENT_BINARY_DIR}/cmake/add-to-path.cmake"
            @ONLY
        )
        install(SCRIPT "${CMAKE_CURRENT_BINARY_DIR}/cmake/add-to-path.cmake")
    endif()
endif()
