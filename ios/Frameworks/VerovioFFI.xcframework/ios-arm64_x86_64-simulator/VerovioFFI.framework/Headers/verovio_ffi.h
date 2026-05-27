#pragma once

#include <stdbool.h>
#include <stdint.h>

#define VRV_FFI_EXPORT __attribute__((visibility("default")))

#ifdef __cplusplus
extern "C" {
#endif

typedef void* VrvToolkitHandle;

VRV_FFI_EXPORT VrvToolkitHandle vrv_ffi_create(const char* resource_path);
VRV_FFI_EXPORT void vrv_ffi_destroy(VrvToolkitHandle handle);
VRV_FFI_EXPORT bool vrv_ffi_set_resource_path(VrvToolkitHandle handle, const char* resource_path);
VRV_FFI_EXPORT bool vrv_ffi_set_options_json(VrvToolkitHandle handle, const char* options_json);
VRV_FFI_EXPORT bool vrv_ffi_load_data(VrvToolkitHandle handle, const char* utf8_data);
VRV_FFI_EXPORT bool vrv_ffi_load_zip_data_base64(VrvToolkitHandle handle, const char* base64_data);
VRV_FFI_EXPORT int32_t vrv_ffi_get_page_count(VrvToolkitHandle handle);
VRV_FFI_EXPORT char* vrv_ffi_render_to_svg(VrvToolkitHandle handle, int32_t page_no, bool xml_declaration);
VRV_FFI_EXPORT char* vrv_ffi_get_log(VrvToolkitHandle handle);
VRV_FFI_EXPORT char* vrv_ffi_get_version(VrvToolkitHandle handle);

// C group: render/export helpers.
// These return owned strings; the caller must free them with vrv_ffi_string_free().
// Failure / exception path returns nullptr.
VRV_FFI_EXPORT char* vrv_ffi_render_to_midi(VrvToolkitHandle handle);
VRV_FFI_EXPORT char* vrv_ffi_render_to_pae(VrvToolkitHandle handle);
VRV_FFI_EXPORT char* vrv_ffi_render_to_timemap(VrvToolkitHandle handle, const char* json_options);
VRV_FFI_EXPORT char* vrv_ffi_render_to_expansion_map(VrvToolkitHandle handle);

// D group: scalar queries / setters.
// bool functions return false on invalid handle / invalid input / exception; callers can inspect vrv_ffi_get_log().
// int32_t functions return -1 on invalid handle / exception.
VRV_FFI_EXPORT int32_t vrv_ffi_get_scale(VrvToolkitHandle handle);
VRV_FFI_EXPORT bool vrv_ffi_set_scale(VrvToolkitHandle handle, int32_t scale);
VRV_FFI_EXPORT int32_t vrv_ffi_get_page_with_element(VrvToolkitHandle handle, const char* xml_id);
VRV_FFI_EXPORT int32_t vrv_ffi_get_time_for_element(VrvToolkitHandle handle, const char* xml_id);
VRV_FFI_EXPORT bool vrv_ffi_select(VrvToolkitHandle handle, const char* selection_json);
VRV_FFI_EXPORT bool vrv_ffi_set_input_from(VrvToolkitHandle handle, const char* input_from);
VRV_FFI_EXPORT bool vrv_ffi_set_output_to(VrvToolkitHandle handle, const char* output_to);
VRV_FFI_EXPORT bool vrv_ffi_edit(VrvToolkitHandle handle, const char* editor_action);

VRV_FFI_EXPORT char* vrv_ffi_get_available_options(VrvToolkitHandle handle);
VRV_FFI_EXPORT char* vrv_ffi_get_default_options(VrvToolkitHandle handle);
VRV_FFI_EXPORT char* vrv_ffi_get_options(VrvToolkitHandle handle);
VRV_FFI_EXPORT char* vrv_ffi_get_option_usage_string(VrvToolkitHandle handle);
VRV_FFI_EXPORT char* vrv_ffi_get_descriptive_features(VrvToolkitHandle handle, const char* json_options);
VRV_FFI_EXPORT char* vrv_ffi_get_element_attr(VrvToolkitHandle handle, const char* xml_id);
VRV_FFI_EXPORT char* vrv_ffi_get_elements_at_time(VrvToolkitHandle handle, int32_t millisec);
VRV_FFI_EXPORT char* vrv_ffi_get_expansion_ids_for_element(VrvToolkitHandle handle, const char* xml_id);
VRV_FFI_EXPORT char* vrv_ffi_get_midi_values_for_element(VrvToolkitHandle handle, const char* xml_id);
VRV_FFI_EXPORT char* vrv_ffi_get_notated_id_for_element(VrvToolkitHandle handle, const char* xml_id);
VRV_FFI_EXPORT char* vrv_ffi_get_times_for_element(VrvToolkitHandle handle, const char* xml_id);
VRV_FFI_EXPORT char* vrv_ffi_get_id(VrvToolkitHandle handle);
VRV_FFI_EXPORT char* vrv_ffi_get_resource_path(VrvToolkitHandle handle);
VRV_FFI_EXPORT char* vrv_ffi_get_humdrum(VrvToolkitHandle handle);
VRV_FFI_EXPORT char* vrv_ffi_get_mei(VrvToolkitHandle handle, const char* json_options);
VRV_FFI_EXPORT char* vrv_ffi_convert_humdrum_to_humdrum(VrvToolkitHandle handle, const char* humdrum_data);
VRV_FFI_EXPORT char* vrv_ffi_convert_humdrum_to_midi(VrvToolkitHandle handle, const char* humdrum_data);
VRV_FFI_EXPORT char* vrv_ffi_convert_mei_to_humdrum(VrvToolkitHandle handle, const char* mei_data);
VRV_FFI_EXPORT char* vrv_ffi_edit_info(VrvToolkitHandle handle);
VRV_FFI_EXPORT char* vrv_ffi_validate_pae(VrvToolkitHandle handle, const char* data);
VRV_FFI_EXPORT char* vrv_ffi_render_data(VrvToolkitHandle handle, const char* data, const char* json_options);

// E group: void operations.
VRV_FFI_EXPORT void vrv_ffi_redo_layout(VrvToolkitHandle handle, const char* json_options);
VRV_FFI_EXPORT void vrv_ffi_redo_page_pitch_pos_layout(VrvToolkitHandle handle);
VRV_FFI_EXPORT void vrv_ffi_reset_options(VrvToolkitHandle handle);
VRV_FFI_EXPORT void vrv_ffi_reset_xml_id_seed(VrvToolkitHandle handle, int32_t seed);

// F group: binary buffer input.
VRV_FFI_EXPORT bool vrv_ffi_load_zip_data_buffer(VrvToolkitHandle handle, const uint8_t* data, int32_t length);

VRV_FFI_EXPORT void vrv_ffi_string_free(char* s);

#ifdef __cplusplus
}
#endif
