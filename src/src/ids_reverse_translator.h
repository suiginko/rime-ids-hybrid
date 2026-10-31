//
// ids_reverse_translator.h — ids_reverse 统一检字翻译器。
//
#ifndef RIME_IDS_REVERSE_IDS_REVERSE_TRANSLATOR_H_
#define RIME_IDS_REVERSE_IDS_REVERSE_TRANSLATOR_H_

#include <string>
#include <vector>

#include <rime/translator.h>
#include <rime/translation.h>

#include "ids_reverse_config.h"

namespace rime {
struct Segment;
}

namespace ids_reverse {

class IdsStore;

class IdsReverseTranslator : public rime::Translator {
 public:
  explicit IdsReverseTranslator(const rime::Ticket& ticket);

  rime::an<rime::Translation> Query(const std::string& input,
                                    const rime::Segment& segment) override;

 private:
  bool EnsureLoaded();
  std::string PinyinMode();

  // search 模式：直接部件检索。
  rime::an<rime::Translation> QuerySearch(const std::string& input,
                                          const rime::Segment& segment);
  rime::an<rime::Translation> BuildSearchCandidates(
      const std::vector<uint32_t>& results,
      const std::string& preedit,
      size_t start_pos,
      size_t end_pos);
  std::vector<uint32_t> Search(const std::string& query_raw,
                               const std::string& mode);

  // hybrid 模式：部件/拼音/双拼混合检索。
  rime::an<rime::Translation> QueryHybrid(const rime::Segment& segment);
  void BuildResultCandidates(IdsStore& store,
                             const std::vector<uint32_t>& results,
                             const rime::Segment& segment,
                             const std::string& pending,
                             rime::FifoTranslation* translation);
  void BuildComponentCandidates(IdsStore& store,
                                const std::vector<uint32_t>& results,
                                const rime::Segment& segment,
                                rime::FifoTranslation* translation);

  ReverseConfig config_;
  std::string name_space_;
};

}  // namespace ids_reverse

#endif  // RIME_IDS_REVERSE_IDS_REVERSE_TRANSLATOR_H_
