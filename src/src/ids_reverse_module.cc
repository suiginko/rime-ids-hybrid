//
// ids_reverse_module.cc — 插件模块注册入口。
//
#include <rime/component.h>
#include <rime/registry.h>
#include <rime_api.h>

#include "ids_reverse_composer.h"
#include "ids_reverse_translator.h"

using namespace rime;

static void rime_ids_reverse_initialize() {
  Registry& r = Registry::instance();
  r.Register("ids_reverse_processor",
             new Component<ids_reverse::IdsReverseProcessor>);
  r.Register("ids_reverse_segmentor",
             new Component<ids_reverse::IdsReverseSegmentor>);
  r.Register("ids_reverse_filter",
             new Component<ids_reverse::IdsReverseFilter>);
  r.Register("ids_reverse_translator",
             new Component<ids_reverse::IdsReverseTranslator>);
}

static void rime_ids_reverse_finalize() {}

RIME_REGISTER_MODULE(ids_reverse)
