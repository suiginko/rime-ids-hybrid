//
// ids_reverse_composer.cc — ids_reverse 原生 processor / segmentor / filter。
//
#include "ids_reverse_composer.h"

#include <algorithm>
#include <cctype>
#include <set>
#include <string>
#include <vector>

#include <rime/candidate.h>
#include <rime/engine.h>
#include <rime/key_event.h>
#include <rime/key_table.h>
#include <rime/menu.h>
#include <rime/schema.h>
#include <rime/segmentation.h>

#include "ids_reverse_config.h"
#include "ids_reverse_search.h"
#include "ids_store.h"
#include "ids_text.h"

namespace ids_reverse {

namespace {

using rime::an;
using rime::Candidate;
using rime::Context;
using rime::New;
using rime::Segment;
using rime::Segmentation;

bool IsSingleChar(const std::string& text) {
  return Utf8Length(text) == 1 && !HasWhitespace(text);
}

}  // namespace

// ---------------------------------------------------------------------------
// Processor
// ---------------------------------------------------------------------------

IdsReverseProcessor::IdsReverseProcessor(const rime::Ticket& ticket)
    : Processor(ticket) {
  LoadReverseConfig(ticket, &name_space_, &config_);
  Context* ctx = engine_ ? engine_->context() : nullptr;
  if (ctx) {
    select_before_ = ctx->select_notifier().connect(
        [this](Context* c) { OnSelectBefore(c); }, boost::signals2::at_front);
    select_after_ = ctx->select_notifier().connect(
        [this](Context* c) { OnSelectAfter(c); }, boost::signals2::at_back);
    update_connection_ =
        ctx->update_notifier().connect([this](Context* c) { OnUpdate(c); });
  }
}

IdsReverseProcessor::~IdsReverseProcessor() {
  select_before_.disconnect();
  select_after_.disconnect();
  update_connection_.disconnect();
}

void IdsReverseProcessor::OnSelectBefore(Context* ctx) {
  if (!IsReverseActive(ctx, config_.hybrid.prefix))
    return;
  if (ctx->composition().empty())
    return;
  an<Candidate> cand = ctx->GetSelectedCandidate();
  if (!cand)
    return;
  an<Candidate> genuine = Candidate::GetGenuineCandidate(cand);
  const std::string& type = genuine ? genuine->type() : cand->type();
  has_selection_ = true;
  selected_is_result_ = (type == "ids_reverse" || type == "hanzi_result");

  selected_text_ = cand->text();
  selected_component_ = genuine ? genuine->text() : cand->text();
  // 选择期间临时关闭自动上屏，交给 OnSelectAfter 统一处理。
  saved_auto_commit_ = ctx->get_option("_auto_commit");
  if (saved_auto_commit_)
    ctx->set_option("_auto_commit", false);
}

void IdsReverseProcessor::OnSelectAfter(Context* ctx) {
  if (!has_selection_)
    return;
  has_selection_ = false;
  const bool restore_auto_commit = saved_auto_commit_;
  saved_auto_commit_ = false;

  if (selected_is_result_) {
    engine_->CommitText(selected_text_);
    ctx->Clear();
  } else {
    HybridState st = ReadHybridState(ctx, config_.hybrid.prefix);
    std::string text = selected_component_;
    if (!text.empty() && !st.pending.empty() && st.pending[0] == '-' &&
        text[0] != '-') {
      text = "-" + text;
    } else if (!text.empty() && !st.pending.empty() && st.pending[0] == '+' &&
               text[0] != '+') {
      text = "+" + text;
    }
    st.components.push_back(text);
    st.codes.push_back(st.pending);
    SaveHybridState(ctx, st.components, st.codes);
    ctx->PushInput("'");
  }

  if (restore_auto_commit && !ctx->get_option("_auto_commit"))
    ctx->set_option("_auto_commit", true);
}

void IdsReverseProcessor::OnUpdate(Context* ctx) {
  if (!IsReverseActive(ctx, config_.hybrid.prefix))
    return;
  if (!ctx->composition().empty())
    ctx->composition().back().prompt = config_.hybrid.tips;
}

bool IdsReverseProcessor::HandleIdsHotkey(const rime::KeyEvent& key_event,
                                          Context* ctx) {
  if (!ctx || ctx->composition().empty())
    return false;
  if (!IsReverseActive(ctx, config_.hybrid.prefix))
    return false;
  const int code = key_event.keycode();
  const bool ctrl = key_event.ctrl();
  const bool alt = key_event.alt();
  const bool shift = key_event.shift();
  const bool is_return = (code == XK_Return || code == XK_KP_Enter);

  int digit = 0;
  if (code >= XK_1 && code <= XK_6)
    digit = code - XK_0;

  bool action = false;
  int ids_digit = 0;
  if (ctrl && !shift && !alt && is_return)
    action = true;
  else if (alt && !shift && !ctrl && is_return)
    action = true;
  else if (alt && !ctrl && (code == XK_i || code == XK_I))
    action = true;
  else if (ctrl && shift && (code == XK_i || code == XK_I))
    action = true;
  else if (ctrl && !shift && !alt && digit) {
    action = true;
    ids_digit = digit;
  } else if (alt && !shift && !ctrl && digit) {
    action = true;
    ids_digit = digit;
  }
  if (!action)
    return false;

  Segment& seg = ctx->composition().back();
  if (!seg.menu)
    return false;
  size_t index = seg.selected_index;
  if (ids_digit) {
    int page_size = engine_->schema() ? engine_->schema()->page_size() : 5;
    if (page_size <= 0)
      page_size = 5;
    size_t page_start =
        (seg.selected_index / static_cast<size_t>(page_size)) * page_size;
    index = page_start + static_cast<size_t>(ids_digit) - 1;
  }
  seg.menu->Prepare(index + 1);
  an<Candidate> cand = seg.GetCandidateAt(index);
  if (!cand || cand->text().empty())
    return false;
  if (!EnsureIdsStoreLoaded(config_))
    return false;
  IdsStore& store = IdsStore::Instance();
  std::string ids = IdsOfText(store, cand->text());
  if (ids.empty())
    return false;
  engine_->CommitText(ids);
  ctx->Clear();
  return true;
}

bool IdsReverseProcessor::HandleSelectionKey(int digit, Context* ctx) {
  if (!ctx || ctx->composition().empty())
    return false;
  Segment& seg = ctx->composition().back();
  if (!seg.menu)
    return false;
  int page_size = engine_->schema() ? engine_->schema()->page_size() : 5;
  if (page_size <= 0)
    page_size = 5;
  size_t page_start =
      (seg.selected_index / static_cast<size_t>(page_size)) * page_size;
  size_t target = page_start + static_cast<size_t>(digit) - 1;
  size_t count = seg.menu->Prepare(target + 1);
  if (target >= count)
    return true;
  ctx->Select(target);
  return true;
}

rime::ProcessResult IdsReverseProcessor::ProcessKeyEvent(
    const rime::KeyEvent& key_event) {
  if (key_event.release())
    return rime::kNoop;
  Context* ctx = engine_ ? engine_->context() : nullptr;
  if (!ctx)
    return rime::kNoop;

  if (HandleIdsHotkey(key_event, ctx))
    return rime::kAccepted;

  const std::string repr = key_event.repr();
  const int code = key_event.keycode();
  const bool ctrl = key_event.ctrl();
  const bool alt = key_event.alt();

  if (!IsReverseActive(ctx, config_.hybrid.prefix)) {
    if (!ctx->get_option("ascii_mode") && !ctrl && !alt &&
        !ctx->IsComposing()) {
      if (repr == config_.search.prefix) {
        ctx->PushInput(config_.search.prefix);
        return rime::kAccepted;
      }
      if (repr == config_.hybrid.prefix) {
        ctx->PushInput(config_.hybrid.prefix);
        return rime::kAccepted;
      }
    }
    return rime::kNoop;
  }

  if (code == XK_Escape || repr == "Escape") {
    ctx->Clear();
    return rime::kAccepted;
  }

  if (code == XK_Return || code == XK_KP_Enter || repr == "Return") {
    HybridState st = ReadHybridState(ctx, config_.hybrid.prefix);
    if (st.components.empty() && st.pending.empty()) {
      engine_->CommitText(config_.hybrid.prefix);
      ctx->Clear();
      return rime::kAccepted;
    }
    if (!st.pending.empty() && st.pending != "-" && st.pending != "+") {
      if (!ctx->composition().empty())
        ctx->composition().pop_back();
      st.components.push_back(st.pending);
      st.codes.push_back(st.pending);
      SaveHybridState(ctx, st.components, st.codes);
      ctx->PushInput("'");
      return rime::kAccepted;
    }
    if (ctx->HasMenu() && ctx->GetSelectedCandidate()) {
      ctx->ConfirmCurrentSelection();
      return rime::kAccepted;
    }
    return rime::kNoop;
  }

  if (code == XK_BackSpace || repr == "BackSpace") {
    HybridState st = ReadHybridState(ctx, config_.hybrid.prefix);
    if (!st.pending.empty()) {
      if (st.pending.size() == 1 && !st.components.empty()) {
        if (!ctx->composition().empty())
          ctx->composition().pop_back();
        if (!ctx->composition().empty()) {
          Segment& sep = ctx->composition().back();
          sep.tags.clear();
          sep.tags.insert(config_.hybrid.tag);
          sep.status = Segment::kVoid;
        }
      }
      ctx->PopInput(1);
    } else if (!st.components.empty()) {
      st.components.pop_back();
      st.codes.pop_back();
      SaveHybridState(ctx, st.components, st.codes);
      if (!ctx->composition().empty())
        ctx->composition().pop_back();
      if (!ctx->composition().empty())
        ctx->composition().back().status = Segment::kGuess;
      ctx->PopInput(1);
    } else {
      ctx->Clear();
    }
    return rime::kAccepted;
  }

  if (!ctrl && !alt && code >= XK_1 && code <= XK_6) {
    if (ctx->HasMenu()) {
      HandleSelectionKey(code - XK_0, ctx);
      return rime::kAccepted;
    }
    return rime::kNoop;
  }
  if (!ctrl && !alt && (code == XK_semicolon || repr == "semicolon")) {
    if (ctx->HasMenu()) {
      HandleSelectionKey(2, ctx);
      return rime::kAccepted;
    }
    return rime::kNoop;
  }
  if (code == XK_space || repr == "space") {
    if (!key_event.shift() && ctx->HasMenu() && ctx->GetSelectedCandidate()) {
      ctx->ConfirmCurrentSelection();
      return rime::kAccepted;
    }
    return rime::kNoop;
  }

  bool is_letter = !ctrl && !alt && repr.size() == 1 &&
                   std::isalpha(static_cast<unsigned char>(repr[0]));
  bool is_minus =
      !ctrl && !alt && (code == XK_minus || repr == "minus" || repr == "-");
  bool is_plus = !ctrl && !alt &&
                 (code == XK_plus || code == XK_equal || repr == "plus" ||
                  repr == "equal" || repr == "+" || repr == "=");

  if (is_letter || is_minus || is_plus) {
    char ch = is_minus ? '-' : (is_plus ? '+' : repr[0]);
    if (ch >= 'A' && ch <= 'Z')
      ch = static_cast<char>(ch - 'A' + 'a');
    if (ctx->caret_pos() != ctx->input().size())
      ctx->set_caret_pos(ctx->input().size());
    if (!ctx->composition().empty() &&
        ctx->composition().back().HasTag(config_.hybrid.tag)) {
      ctx->ClearNonConfirmedComposition();
    }
    ctx->PushInput(std::string(1, ch));
    return rime::kAccepted;
  }

  return rime::kNoop;
}

// ---------------------------------------------------------------------------
// Segmentor
// ---------------------------------------------------------------------------

IdsReverseSegmentor::IdsReverseSegmentor(const rime::Ticket& ticket)
    : Segmentor(ticket) {
  LoadReverseConfig(ticket, &name_space_, &config_);
}

bool IdsReverseSegmentor::Proceed(Segmentation* segmentation) {
  if (!segmentation)
    return false;
  Context* ctx = engine_ ? engine_->context() : nullptr;

  const std::string& input = segmentation->input();
  size_t start = segmentation->GetCurrentStartPosition();

  // search 模式：整段输入打标签，交给 translator 直接检索。
  if (start == 0 && (!ctx || !ctx->get_option("ascii_mode")) &&
      StartsWith(input, config_.search.prefix)) {
    Segment seg(0, static_cast<int>(input.size()));
    seg.tags.insert(config_.search.tag);
    seg.prompt = config_.search.tips;
    if (!segmentation->AddSegment(seg))
      return true;
    if (!segmentation->empty())
      segmentation->back().prompt = config_.search.tips;
    return false;
  }

  if (!IsReverseActive(ctx, config_.hybrid.prefix))
    return true;

  if (start >= input.size())
    return false;

  size_t prefix_end = (start == 0) ? config_.hybrid.prefix.size() : start + 1;
  bool is_prefix =
      (start == 0) || (start < input.size() && input[start] == '\'');

  Segment seg;
  if (is_prefix && prefix_end < input.size()) {
    seg = Segment(static_cast<int>(start), static_cast<int>(prefix_end));
    // 保留 hybrid 前缀在组字区显示；引号分隔符仍隐藏。
    if (start != 0)
      seg.tags.insert("phony");
    seg.status = Segment::kConfirmed;
  } else if (is_prefix) {
    seg = Segment(static_cast<int>(start), static_cast<int>(input.size()));
    if (start == 0) {
      seg.tags.insert(config_.hybrid.tag);
    } else {
      seg.tags.insert(config_.hybrid.tag);
      seg.tags.insert(kResultSegmentTag);
    }
  } else {
    size_t next_quote = input.find('\'', start + 1);
    char first_char = (start < input.size()) ? input[start] : '\0';
    if (first_char == '-' || first_char == '+') {
      bool has_code_after =
          (start + 1 < input.size()) &&
          (next_quote == std::string::npos || next_quote > start + 1);
      if (has_code_after) {
        seg = Segment(static_cast<int>(start), static_cast<int>(start + 1));
        seg.status = Segment::kConfirmed;
        seg.tags.insert("confirmed_component");
      } else if (start + 1 == input.size()) {
        seg = Segment(static_cast<int>(start), static_cast<int>(input.size()));
        seg.tags.insert(config_.hybrid.tag);
        seg.tags.insert(kResultSegmentTag);
      } else {
        seg = Segment(static_cast<int>(start), static_cast<int>(start + 1));
        seg.status = Segment::kConfirmed;
        seg.tags.insert("confirmed_component");
      }
    } else if (next_quote != std::string::npos) {
      seg = Segment(static_cast<int>(start), static_cast<int>(next_quote));
      seg.status = Segment::kConfirmed;
      seg.tags.insert("confirmed_component");
    } else {
      seg = Segment(static_cast<int>(start), static_cast<int>(input.size()));
      seg.tags.insert("abc");
      seg.tags.insert("hanzi_component");
    }
  }

  seg.prompt = config_.hybrid.tips;
  segmentation->AddSegment(seg);
  return false;
}

// ---------------------------------------------------------------------------
// Filter / Cleaner
// ---------------------------------------------------------------------------

namespace {

class HybridFilterTranslation : public rime::PrefetchTranslation {
 public:
  HybridFilterTranslation(an<rime::Translation> translation, Context* ctx)
      : PrefetchTranslation(translation), ctx_(ctx) {}

  an<Candidate> Peek() override {
    if (exhausted())
      return nullptr;
    if (!cache_.empty())
      return cache_.front();
    if (!Replenish()) {
      // 不要把未过滤的底层候选回退出去。
      set_exhausted(true);
      return nullptr;
    }
    return cache_.front();
  }

 protected:
  bool Replenish() override {
    // 防止底层翻译器（预测、句子等）产生海量候选时长时间扫描。
    constexpr size_t kMaxScan = 2000;
    size_t scanned = 0;
    while (cache_.empty()) {
      if (scanned++ >= kMaxScan)
        break;
      an<Candidate> next = translation_->Peek();
      if (!next) {
        translation_->Next();
        if (translation_->exhausted())
          break;
        continue;
      }
      translation_->Next();
      an<Candidate> genuine = Candidate::GetGenuineCandidate(next);
      const std::string& type = genuine ? genuine->type() : next->type();
      if (type == "ids_reverse" || type == "hanzi_result") {
        cache_.push_back(next);
        continue;
      }
      if (!ctx_ || ctx_->composition().empty()) {
        cache_.push_back(next);
        continue;
      }
      Segment& seg = ctx_->composition().back();
      const bool component_stage = seg.HasTag("hanzi_component");
      if (!component_stage)
        continue;
      if (next->end() == seg.end && IsSingleChar(next->text()) &&
          seen_.insert(next->text()).second) {
        cache_.push_back(New<rime::ShadowCandidate>(next, "hanzi_component"));
      }
    }
    return !cache_.empty();
  }

 private:
  Context* ctx_;
  std::set<std::string> seen_;
};

}  // namespace

IdsReverseFilter::IdsReverseFilter(const rime::Ticket& ticket)
    : Filter(ticket) {
  LoadReverseConfig(ticket, &name_space_, &config_);
}

bool IdsReverseFilter::AppliesToSegment(Segment* segment) {
  suppress_ = false;
  Context* ctx = engine_ ? engine_->context() : nullptr;
  if (!ctx || !segment || ctx->get_option("ascii_mode"))
    return true;
  if (ctx->input() != config_.search.prefix)
    return true;
  if (segment->start != 0 ||
      segment->end != static_cast<size_t>(config_.search.prefix.size())) {
    return true;
  }
  suppress_ = true;
  return true;
}

an<rime::Translation> IdsReverseFilter::Apply(an<rime::Translation> translation,
                                              rime::CandidateList* candidates) {
  (void)candidates;
  Context* ctx = engine_ ? engine_->context() : nullptr;
  if (!ctx)
    return translation;

  if (suppress_) {
    suppress_ = false;
    return New<rime::FifoTranslation>();
  }

  if (!IsReverseActive(ctx, config_.hybrid.prefix))
    return translation;

  // 初始 O / 前缀段既不是部件选择段，也不是结果段。
  // 直接返回空翻译，避免遍历完整词典或预测翻译器的海量候选。
  if (ctx->composition().empty())
    return New<rime::FifoTranslation>();
  Segment& seg = ctx->composition().back();
  if (!seg.HasTag("hanzi_component") && !seg.HasTag(kResultSegmentTag))
    return New<rime::FifoTranslation>();

  return New<HybridFilterTranslation>(translation, ctx);
}

}  // namespace ids_reverse
