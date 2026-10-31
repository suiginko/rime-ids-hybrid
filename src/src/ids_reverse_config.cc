//
// ids_reverse_config.cc — ids_reverse 统一配置加载与混合检字状态。
//
#include "ids_reverse_config.h"

#include <filesystem>
#include <string>

#include <rime/config.h>
#include <rime/context.h>
#include <rime/engine.h>
#include <rime/schema.h>
#include <rime/service.h>
#include <rime/ticket.h>

#include "ids_store.h"

namespace ids_reverse {

namespace {

using rime::Config;
using rime::Context;

std::string ToLowerAscii(const std::string& s) {
  std::string r = s;
  for (auto& ch : r) {
    if (ch >= 'A' && ch <= 'Z')
      ch = static_cast<char>(ch + 32);
  }
  return r;
}

void LoadDisabledBlocks(Config* config,
                        const std::string& ns,
                        ReverseConfig* cfg) {
  if (!config)
    return;
  if (auto list = config->GetList(ns + "/disabled_blocks")) {
    for (size_t i = 0; i < list->size(); ++i) {
      if (auto value = rime::As<rime::ConfigValue>(list->GetValueAt(i))) {
        std::string name;
        if (value->GetString(&name)) {
          auto it = BlockAliasMap().find(ToLowerAscii(name));
          if (it != BlockAliasMap().end())
            cfg->disabled_blocks.insert(it->second);
        }
      }
    }
  }
  std::string str;
  if (config->GetString(ns + "/disabled_blocks", &str) && !str.empty()) {
    size_t i = 0;
    while (i < str.size()) {
      while (i < str.size() &&
             (str[i] == ',' || str[i] == ' ' || str[i] == '\t' ||
              str[i] == '\r' || str[i] == '\n'))
        ++i;
      size_t j = i;
      while (j < str.size() && str[j] != ',' && str[j] != ' ' &&
             str[j] != '\t' && str[j] != '\r' && str[j] != '\n')
        ++j;
      if (j > i) {
        auto it = BlockAliasMap().find(ToLowerAscii(str.substr(i, j - i)));
        if (it != BlockAliasMap().end())
          cfg->disabled_blocks.insert(it->second);
      }
      i = j;
    }
  }
  cfg->disabled_blocks_enabled = !cfg->disabled_blocks.empty();
}

}  // namespace

bool StartsWith(const std::string& s, const std::string& prefix) {
  return !prefix.empty() && s.size() >= prefix.size() &&
         s.compare(0, prefix.size(), prefix) == 0;
}

std::string DefaultReverseNamespace(const rime::Ticket& ticket) {
  if (ticket.name_space.empty() || ticket.name_space == "processor" ||
      ticket.name_space == "segmentor" || ticket.name_space == "translator" ||
      ticket.name_space == "filter") {
    return "ids_reverse";
  }
  return ticket.name_space;
}

void LoadReverseConfig(const rime::Ticket& ticket,
                       std::string* name_space,
                       ReverseConfig* config) {
  *name_space = DefaultReverseNamespace(ticket);
  const std::string ns = *name_space;

  rime::Engine* engine = ticket.engine;
  if (!engine || !engine->schema())
    return;
  Config* conf = engine->schema()->config();
  if (!conf)
    return;

  conf->GetString(ns + "/search_prefix", &config->search.prefix);
  conf->GetString(ns + "/search_tag", &config->search.tag);
  conf->GetString(ns + "/search_tips", &config->search.tips);
  conf->GetString(ns + "/hybrid_prefix", &config->hybrid.prefix);
  conf->GetString(ns + "/hybrid_tag", &config->hybrid.tag);
  conf->GetString(ns + "/hybrid_tips", &config->hybrid.tips);

  conf->GetString(ns + "/data_file", &config->data_path);
  conf->GetString(ns + "/custom_file", &config->custom_path);
  conf->GetString(ns + "/shuangpin_scheme", &config->shuangpin_scheme);
  conf->GetString(ns + "/ids_format", &config->ids_format);
  conf->GetInt(ns + "/max_results", &config->max_results);

  if (config->search.prefix.empty())
    config->search.prefix = "I";
  if (config->search.tag.empty())
    config->search.tag = "ids_reverse_search";
  if (config->search.tips.empty())
    config->search.tips = "〔部件检字〕";
  if (config->hybrid.prefix.empty())
    config->hybrid.prefix = "O";
  if (config->hybrid.tag.empty())
    config->hybrid.tag = "ids_reverse_hybrid";
  if (config->hybrid.tips.empty())
    config->hybrid.tips = "〔汉字部件检字〕";
  if (config->search.prefix == config->hybrid.prefix) {
    LOG(WARNING)
        << "ids_reverse: search_prefix and hybrid_prefix are identical ('"
        << config->search.prefix << "'); search mode takes precedence";
  }

  if (config->data_path.empty())
    config->data_path = "ids_data.bin";
  if (config->shuangpin_scheme != "zrm" &&
      config->shuangpin_scheme != "quanpin")
    config->shuangpin_scheme = "flypy";
  if (config->max_results <= 0)
    config->max_results = 60;

  bool v;
  if (conf->GetBool(ns + "/show_pinyin", &v))
    config->show_pinyin = v;
  if (conf->GetBool(ns + "/show_ids", &v))
    config->show_ids = v;
  if (conf->GetBool(ns + "/show_unicode", &v))
    config->show_unicode = v;
  if (conf->GetBool(ns + "/show_block", &v))
    config->show_block = v;

  for (size_t i = 0; i < 64; ++i) {
    std::string s_name;
    if (conf->GetString("switches/@" + std::to_string(i) + "/name", &s_name)) {
      if (s_name == "show_pinyin")
        config->has_sw_pinyin = true;
      else if (s_name == "show_ids")
        config->has_sw_ids = true;
      else if (s_name == "show_unicode")
        config->has_sw_unicode = true;
      else if (s_name == "show_block")
        config->has_sw_block = true;
    } else if (conf->GetItem("switches/@" + std::to_string(i)) == nullptr) {
      break;
    }
  }

  LoadDisabledBlocks(conf, ns, config);
}

bool IsReverseActive(Context* ctx, const std::string& prefix) {
  if (!ctx || prefix.empty())
    return false;
  if (ctx->get_option("ascii_mode"))
    return false;
  return StartsWith(ctx->input(), prefix);
}

HybridState ReadHybridState(Context* ctx, const std::string& prefix) {
  HybridState st;
  if (!ctx)
    return st;
  std::string prop = ctx->get_property(kHybridStateProperty);
  size_t pos = 0;
  while (pos < prop.size()) {
    size_t nl = prop.find('\n', pos);
    if (nl == std::string::npos)
      nl = prop.size();
    std::string line = prop.substr(pos, nl - pos);
    if (!line.empty() && line.back() == '\r')
      line.pop_back();
    size_t tab = line.find('\t');
    if (tab != std::string::npos) {
      st.components.push_back(line.substr(0, tab));
      st.codes.push_back(line.substr(tab + 1));
    }
    pos = nl + 1;
  }

  std::string expected = prefix;
  for (const auto& code : st.codes)
    expected += code + "'";
  const std::string& input = ctx->input();
  if (!StartsWith(input, expected)) {
    st.components.clear();
    st.codes.clear();
    st.pending = input.size() > prefix.size() ? input.substr(prefix.size())
                                              : std::string();
    return st;
  }
  st.pending = input.substr(expected.size());
  return st;
}

void SaveHybridState(Context* ctx,
                     const std::vector<std::string>& components,
                     const std::vector<std::string>& codes) {
  std::string prop;
  for (size_t i = 0; i < components.size() && i < codes.size(); ++i) {
    prop += components[i];
    prop += '\t';
    prop += codes[i];
    prop += '\n';
  }
  ctx->set_property(kHybridStateProperty, prop);
}

bool EnsureIdsStoreLoaded(const ReverseConfig& config) {
  IdsStore& store = IdsStore::Instance();
  if (store.loaded())
    return true;
  rime::Deployer& deployer = rime::Service::instance().deployer();
  auto resolve = [&](const std::string& filename) -> fs::path {
    fs::path p(filename);
    if (p.is_absolute())
      return p;
    fs::path ud = deployer.user_data_dir / filename;
    if (fs::exists(ud))
      return ud;
    fs::path sd = deployer.shared_data_dir / filename;
    if (fs::exists(sd))
      return sd;
    return ud;
  };
  fs::path data =
      resolve(config.data_path.empty() ? "ids_data.bin" : config.data_path);
  fs::path custom;
  if (!config.custom_path.empty())
    custom = resolve(config.custom_path);
  bool ok = store.Load(data, custom);
  if (!ok) {
    LOG(ERROR) << "ids_reverse: cannot load data file: '" << data << "'";
    return false;
  }
  return true;
}

void MergeCustomDisabledBlocks(rime::hash_set<int>* disabled, bool* enabled) {
  IdsStore& store = IdsStore::Instance();
  for (int b : store.custom_disabled_blocks()) {
    if (disabled->insert(b).second)
      *enabled = true;
  }
}

}  // namespace ids_reverse
