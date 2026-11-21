cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME}
  "main.cc"
  "key_bindings.cc"
  "my_application.cc"
  "renderer_policy.cc"
  "webviews.cc"
  "window_options.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Embed the bundled engine identity; installed applications never read the SDK.
# Local engine builds do not necessarily match the SDK's official engine stamp.
function(configure_renderer_engine)
  include("${FLUTTER_MANAGED_DIR}/ephemeral/generated_config.cmake")
  set(engine_revision "")
  set(engine_stamp "${FLUTTER_ROOT}/bin/cache/engine.stamp")
  if(NOT "${FLUTTER_TOOL_ENVIRONMENT}" MATCHES "(^|;)(LOCAL_ENGINE|LOCAL_ENGINE_HOST|FLUTTER_ENGINE)=")
    if(EXISTS "${engine_stamp}")
      file(READ "${engine_stamp}" engine_revision)
      string(STRIP "${engine_revision}" engine_revision)
      if(NOT engine_revision MATCHES "^[0-9a-f]+$")
        set(engine_revision "")
      endif()
    endif()
  endif()
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${engine_stamp}")
  target_compile_definitions(${BINARY_NAME} PRIVATE
    NAUVIM_FLUTTER_ENGINE_REVISION="${engine_revision}")
endfunction()
configure_renderer_engine()

# Add preprocessor definitions for the application ID.
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# Add dependency libraries. Add any application-specific dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK PkgConfig::WEBKIT PkgConfig::FONTCONFIG)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
