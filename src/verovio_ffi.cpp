#include "verovio_ffi.h"

#include "toolkit.h"
#include "toolkitdef.h"

#include <cstdlib>
#include <cstring>
#include <string>

namespace {

static inline vrv::Toolkit* as_tk(VrvToolkitHandle handle) {
    return static_cast<vrv::Toolkit*>(handle);
}

static char* dup_string(const std::string& value) {
    char* out = static_cast<char*>(std::malloc(value.size() + 1));
    if (!out) return nullptr;
    std::memcpy(out, value.data(), value.size());
    out[value.size()] = '\0';
    return out;
}

} // namespace

extern "C" {

VrvToolkitHandle vrv_ffi_create(const char* resource_path) {
    try {
        vrv::Toolkit* toolkit = new vrv::Toolkit(false);  // Create without initializing fonts
        if (!toolkit) return nullptr;

        // Now explicitly set the resource path, which will initialize fonts properly
        std::string path = "/data";
        if (resource_path && resource_path[0] != '\0') {
            path = resource_path;
        }

        if (!toolkit->SetResourcePath(path)) {
            delete toolkit;
            return nullptr;
        }

        return toolkit;
    } catch (...) {
        return nullptr;
    }
}

void vrv_ffi_destroy(VrvToolkitHandle handle) {
    if (!handle) return;
    try {
        delete as_tk(handle);
    } catch (...) {
        // swallow
    }
}

bool vrv_ffi_set_resource_path(VrvToolkitHandle handle, const char* resource_path) {
    if (!handle) return false;
    try {
        return as_tk(handle)->SetResourcePath(resource_path ? resource_path : "");
    } catch (...) {
        return false;
    }
}

bool vrv_ffi_set_options_json(VrvToolkitHandle handle, const char* options_json) {
    if (!handle) return false;
    try {
        return as_tk(handle)->SetOptions(options_json ? options_json : "");
    } catch (...) {
        return false;
    }
}

bool vrv_ffi_load_data(VrvToolkitHandle handle, const char* utf8_data) {
    if (!handle) return false;
    try {
        return as_tk(handle)->LoadData(utf8_data ? utf8_data : "");
    } catch (...) {
        return false;
    }
}

bool vrv_ffi_load_zip_data_base64(VrvToolkitHandle handle, const char* base64_data) {
    if (!handle) return false;
    try {
        return as_tk(handle)->LoadZipDataBase64(base64_data ? base64_data : "");
    } catch (...) {
        return false;
    }
}

int32_t vrv_ffi_get_page_count(VrvToolkitHandle handle) {
    if (!handle) return -1;
    try {
        return static_cast<int32_t>(as_tk(handle)->GetPageCount());
    } catch (...) {
        return -1;
    }
}

char* vrv_ffi_render_to_svg(VrvToolkitHandle handle, int32_t page_no, bool xml_declaration) {
    if (!handle) return nullptr;
    try {
        return dup_string(as_tk(handle)->RenderToSVG(static_cast<int>(page_no), xml_declaration));
    } catch (...) {
        return nullptr;
    }
}

char* vrv_ffi_get_log(VrvToolkitHandle handle) {
    if (!handle) return nullptr;
    try {
        return dup_string(as_tk(handle)->GetLog());
    } catch (...) {
        return nullptr;
    }
}

char* vrv_ffi_get_version(VrvToolkitHandle handle) {
    if (!handle) return nullptr;
    try {
        return dup_string(as_tk(handle)->GetVersion());
    } catch (...) {
        return nullptr;
    }
}

char* vrv_ffi_render_to_midi(VrvToolkitHandle handle) {
    if (!handle) return nullptr;
    try {
        return dup_string(as_tk(handle)->RenderToMIDI());
    } catch (...) {
        return nullptr;
    }
}

char* vrv_ffi_render_to_pae(VrvToolkitHandle handle) {
    if (!handle) return nullptr;
    try {
        return dup_string(as_tk(handle)->RenderToPAE());
    } catch (...) {
        return nullptr;
    }
}

char* vrv_ffi_render_to_timemap(VrvToolkitHandle handle, const char* json_options) {
    if (!handle) return nullptr;
    try {
        return dup_string(as_tk(handle)->RenderToTimemap(json_options ? json_options : ""));
    } catch (...) {
        return nullptr;
    }
}

char* vrv_ffi_render_to_expansion_map(VrvToolkitHandle handle) {
    if (!handle) return nullptr;
    try {
        return dup_string(as_tk(handle)->RenderToExpansionMap());
    } catch (...) {
        return nullptr;
    }
}

int32_t vrv_ffi_get_scale(VrvToolkitHandle handle) {
    if (!handle) return -1;
    try {
        return static_cast<int32_t>(as_tk(handle)->GetScale());
    } catch (...) {
        return -1;
    }
}

bool vrv_ffi_set_scale(VrvToolkitHandle handle, int32_t scale) {
    if (!handle) return false;
    try {
        return as_tk(handle)->SetScale(static_cast<int>(scale));
    } catch (...) {
        return false;
    }
}

int32_t vrv_ffi_get_page_with_element(VrvToolkitHandle handle, const char* xml_id) {
    if (!handle) return -1;
    try {
        return static_cast<int32_t>(as_tk(handle)->GetPageWithElement(xml_id ? xml_id : ""));
    } catch (...) {
        return -1;
    }
}

int32_t vrv_ffi_get_time_for_element(VrvToolkitHandle handle, const char* xml_id) {
    if (!handle) return -1;
    try {
        return static_cast<int32_t>(as_tk(handle)->GetTimeForElement(xml_id ? xml_id : ""));
    } catch (...) {
        return -1;
    }
}

bool vrv_ffi_select(VrvToolkitHandle handle, const char* selection_json) {
    if (!handle) return false;
    try {
        return as_tk(handle)->Select(selection_json ? selection_json : "");
    } catch (...) {
        return false;
    }
}

bool vrv_ffi_set_input_from(VrvToolkitHandle handle, const char* input_from) {
    if (!handle) return false;
    try {
        return as_tk(handle)->SetInputFrom(input_from ? input_from : "");
    } catch (...) {
        return false;
    }
}

bool vrv_ffi_set_output_to(VrvToolkitHandle handle, const char* output_to) {
    if (!handle) return false;
    try {
        return as_tk(handle)->SetOutputTo(output_to ? output_to : "");
    } catch (...) {
        return false;
    }
}

bool vrv_ffi_edit(VrvToolkitHandle handle, const char* editor_action) {
    if (!handle) return false;
    try {
        return as_tk(handle)->Edit(editor_action ? editor_action : "");
    } catch (...) {
        return false;
    }
}

char* vrv_ffi_get_available_options(VrvToolkitHandle handle) {
    if (!handle) return nullptr;
    try {
        return dup_string(as_tk(handle)->GetAvailableOptions());
    } catch (...) {
        return nullptr;
    }
}

char* vrv_ffi_get_default_options(VrvToolkitHandle handle) {
    if (!handle) return nullptr;
    try {
        return dup_string(as_tk(handle)->GetDefaultOptions());
    } catch (...) {
        return nullptr;
    }
}

char* vrv_ffi_get_options(VrvToolkitHandle handle) {
    if (!handle) return nullptr;
    try {
        return dup_string(as_tk(handle)->GetOptions());
    } catch (...) {
        return nullptr;
    }
}

char* vrv_ffi_get_option_usage_string(VrvToolkitHandle handle) {
    if (!handle) return nullptr;
    try {
        return dup_string(as_tk(handle)->GetOptionUsageString());
    } catch (...) {
        return nullptr;
    }
}

char* vrv_ffi_get_descriptive_features(VrvToolkitHandle handle, const char* json_options) {
    if (!handle) return nullptr;
    try {
        return dup_string(as_tk(handle)->GetDescriptiveFeatures(json_options ? json_options : ""));
    } catch (...) {
        return nullptr;
    }
}

char* vrv_ffi_get_element_attr(VrvToolkitHandle handle, const char* xml_id) {
    if (!handle) return nullptr;
    try {
        return dup_string(as_tk(handle)->GetElementAttr(xml_id ? xml_id : ""));
    } catch (...) {
        return nullptr;
    }
}

char* vrv_ffi_get_elements_at_time(VrvToolkitHandle handle, int32_t millisec) {
    if (!handle) return nullptr;
    try {
        return dup_string(as_tk(handle)->GetElementsAtTime(static_cast<int>(millisec)));
    } catch (...) {
        return nullptr;
    }
}

char* vrv_ffi_get_expansion_ids_for_element(VrvToolkitHandle handle, const char* xml_id) {
    if (!handle) return nullptr;
    try {
        return dup_string(as_tk(handle)->GetExpansionIdsForElement(xml_id ? xml_id : ""));
    } catch (...) {
        return nullptr;
    }
}

char* vrv_ffi_get_midi_values_for_element(VrvToolkitHandle handle, const char* xml_id) {
    if (!handle) return nullptr;
    try {
        return dup_string(as_tk(handle)->GetMIDIValuesForElement(xml_id ? xml_id : ""));
    } catch (...) {
        return nullptr;
    }
}

char* vrv_ffi_get_notated_id_for_element(VrvToolkitHandle handle, const char* xml_id) {
    if (!handle) return nullptr;
    try {
        return dup_string(as_tk(handle)->GetNotatedIdForElement(xml_id ? xml_id : ""));
    } catch (...) {
        return nullptr;
    }
}

char* vrv_ffi_get_times_for_element(VrvToolkitHandle handle, const char* xml_id) {
    if (!handle) return nullptr;
    try {
        return dup_string(as_tk(handle)->GetTimesForElement(xml_id ? xml_id : ""));
    } catch (...) {
        return nullptr;
    }
}

char* vrv_ffi_get_id(VrvToolkitHandle handle) {
    if (!handle) return nullptr;
    try {
        return dup_string(as_tk(handle)->GetID());
    } catch (...) {
        return nullptr;
    }
}

char* vrv_ffi_get_resource_path(VrvToolkitHandle handle) {
    if (!handle) return nullptr;
    try {
        return dup_string(as_tk(handle)->GetResourcePath());
    } catch (...) {
        return nullptr;
    }
}

char* vrv_ffi_get_humdrum(VrvToolkitHandle handle) {
    if (!handle) return nullptr;
    try {
        return dup_string(as_tk(handle)->GetHumdrum());
    } catch (...) {
        return nullptr;
    }
}

char* vrv_ffi_get_mei(VrvToolkitHandle handle, const char* json_options) {
    if (!handle) return nullptr;
    try {
        return dup_string(as_tk(handle)->GetMEI(json_options ? json_options : ""));
    } catch (...) {
        return nullptr;
    }
}

char* vrv_ffi_convert_humdrum_to_humdrum(VrvToolkitHandle handle, const char* humdrum_data) {
    if (!handle) return nullptr;
    try {
        return dup_string(as_tk(handle)->ConvertHumdrumToHumdrum(humdrum_data ? humdrum_data : ""));
    } catch (...) {
        return nullptr;
    }
}

char* vrv_ffi_convert_humdrum_to_midi(VrvToolkitHandle handle, const char* humdrum_data) {
    if (!handle) return nullptr;
    try {
        return dup_string(as_tk(handle)->ConvertHumdrumToMIDI(humdrum_data ? humdrum_data : ""));
    } catch (...) {
        return nullptr;
    }
}

char* vrv_ffi_convert_mei_to_humdrum(VrvToolkitHandle handle, const char* mei_data) {
    if (!handle) return nullptr;
    try {
        return dup_string(as_tk(handle)->ConvertMEIToHumdrum(mei_data ? mei_data : ""));
    } catch (...) {
        return nullptr;
    }
}

char* vrv_ffi_edit_info(VrvToolkitHandle handle) {
    if (!handle) return nullptr;
    try {
        return dup_string(as_tk(handle)->EditInfo());
    } catch (...) {
        return nullptr;
    }
}

char* vrv_ffi_validate_pae(VrvToolkitHandle handle, const char* data) {
    if (!handle) return nullptr;
    try {
        return dup_string(as_tk(handle)->ValidatePAE(data ? data : ""));
    } catch (...) {
        return nullptr;
    }
}

char* vrv_ffi_render_data(VrvToolkitHandle handle, const char* data, const char* json_options) {
    if (!handle) return nullptr;
    try {
        return dup_string(as_tk(handle)->RenderData(data ? data : "", json_options ? json_options : ""));
    } catch (...) {
        return nullptr;
    }
}

void vrv_ffi_redo_layout(VrvToolkitHandle handle, const char* json_options) {
    if (!handle) return;
    try {
        as_tk(handle)->RedoLayout(json_options ? json_options : "");
    } catch (...) {
        // swallow
    }
}

void vrv_ffi_redo_page_pitch_pos_layout(VrvToolkitHandle handle) {
    if (!handle) return;
    try {
        as_tk(handle)->RedoPagePitchPosLayout();
    } catch (...) {
        // swallow
    }
}

void vrv_ffi_reset_options(VrvToolkitHandle handle) {
    if (!handle) return;
    try {
        as_tk(handle)->ResetOptions();
    } catch (...) {
        // swallow
    }
}

void vrv_ffi_reset_xml_id_seed(VrvToolkitHandle handle, int32_t seed) {
    if (!handle) return;
    try {
        as_tk(handle)->ResetXmlIdSeed(static_cast<int>(seed));
    } catch (...) {
        // swallow
    }
}

bool vrv_ffi_load_zip_data_buffer(VrvToolkitHandle handle, const uint8_t* data, int32_t length) {
    if (!handle || !data || length <= 0) return false;
    try {
        std::string buf(reinterpret_cast<const char*>(data), static_cast<size_t>(length));
        return as_tk(handle)->LoadZipDataBuffer(
            reinterpret_cast<const unsigned char*>(buf.data()),
            static_cast<int>(buf.size()));
    } catch (...) {
        return false;
    }
}

void vrv_ffi_string_free(char* s) {
    std::free(s);
}

} // extern "C"
