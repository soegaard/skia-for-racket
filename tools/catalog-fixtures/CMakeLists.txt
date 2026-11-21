cmake_minimum_required(VERSION 3.16)
project(skia_catalog_rejections C)
add_library(skia-wrong-abi SHARED wrong-abi.c)
set_target_properties(skia-wrong-abi PROPERTIES PREFIX "")
