project(rime-ids-reverse)
cmake_minimum_required(VERSION 3.10)

aux_source_directory(src ids_reverse_src)

add_library(rime-ids-reverse-objs OBJECT ${ids_reverse_src})
if(BUILD_SHARED_LIBS)
  set_target_properties(rime-ids-reverse-objs
    PROPERTIES
    POSITION_INDEPENDENT_CODE ON)
endif()

set(plugin_name rime-ids-reverse PARENT_SCOPE)
set(plugin_objs $<TARGET_OBJECTS:rime-ids-reverse-objs> PARENT_SCOPE)
set(plugin_deps ${rime_library} PARENT_SCOPE)
set(plugin_modules "ids_reverse" PARENT_SCOPE)
