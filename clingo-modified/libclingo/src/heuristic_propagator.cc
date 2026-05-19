#include "clingo/heuristic_propagator.hh"
#include "clingo/heuristic_parser.hh"
#include "clingo/heuristic_symbol.hh"

#include <algorithm>
#include <stdexcept>
#include <unordered_set>
#include <utility>

static int normalize_sign(int value) {
    if (value > 0) return +1;
    if (value < 0) return -1;
    return 0;
}

static Clingo::Symbol predicate_name_symbol(Clingo::Symbol const &atom_symbol) {
    return Clingo::Id(atom_symbol.name());
}

enum class MatchKeySide {
    Body,
    Target
};

static bool build_body_match_key(BodyPredicateSpec const &spec,
                                 NumericTupleKey const &key,
                                 MatchKeySide side,
                                 NumericTupleKey &match_key) {
    match_key.values.clear();
    match_key.values.reserve(spec.matches.size());
    for (auto const &match : spec.matches) {
        int const index = side == MatchKeySide::Body
            ? match.source_arg_index
            : match.target_arg_index;
        if (index < 0 || static_cast<size_t>(index) >= key.values.size()) {
            return false;
        }
        match_key.values.push_back(key.values[index]);
    }
    return true;
}

static bool collect_body_arg_values(BodyPredicateSpec const &spec,
                                    NumericTupleKey const &body_key,
                                    std::unordered_map<Clingo::Symbol, int> &values) {
    for (auto const &binding : spec.arg_bindings) {
        if (binding.source_arg_index < 0 ||
            static_cast<size_t>(binding.source_arg_index) >= body_key.values.size()) {
            return false;
        }
        int const value = body_key.values[binding.source_arg_index];
        auto inserted = values.emplace(binding.variable_name, value);
        if (!inserted.second && inserted.first->second != value) {
            return false;
        }
    }
    return true;
}

struct BodyLiteralMatch {
    Clingo::literal_t lit = 0;
    std::unordered_map<Clingo::Symbol, int> variable_values;
};

using BodyMatchIndex = std::unordered_map<NumericTupleKey, std::vector<BodyLiteralMatch>, NumericTupleKeyHash>;
using LiteralByTuple = std::unordered_map<NumericTupleKey, Clingo::literal_t, NumericTupleKeyHash>;
using GroundLiteralIndexView = std::unordered_map<Clingo::Symbol, LiteralByTuple>;

struct BodyMatchSource {
    BodyPredicateSpec const *spec = nullptr;
    LiteralByTuple const *body_map = nullptr;
    BodyMatchIndex explicit_index;
};

struct PartialMatch {
    std::vector<Clingo::literal_t> pos_lits;
    std::unordered_map<Clingo::Symbol, int> body_var_values;
};

static BodyMatchIndex build_body_match_index(
    BodyPredicateSpec const &spec,
    std::unordered_map<NumericTupleKey, Clingo::literal_t, NumericTupleKeyHash> const &body_map
) {
    BodyMatchIndex index;
    index.reserve(body_map.size());

    for (auto const &entry : body_map) {
        NumericTupleKey match_key;
        if (!build_body_match_key(spec, entry.first, MatchKeySide::Body, match_key)) continue;

        BodyLiteralMatch match;
        match.lit = entry.second;
        if (collect_body_arg_values(spec, entry.first, match.variable_values)) {
            index[std::move(match_key)].push_back(std::move(match));
        }
    }

    return index;
}

static bool merge_variable_values(std::unordered_map<Clingo::Symbol, int> &dst,
                                  std::unordered_map<Clingo::Symbol, int> const &src);

static std::vector<BodyMatchSource> build_body_match_sources_for_template(
    HeuristicRuleTemplate const &tmpl,
    GroundLiteralIndexView const &ground_literal_index
) {
    std::vector<BodyMatchSource> body_sources;
    body_sources.reserve(tmpl.pos_body_preds.size());

    for (auto const &spec : tmpl.pos_body_preds) {
        auto pos_map_it = ground_literal_index.find(spec.pred_name);
        if (pos_map_it == ground_literal_index.end()) {
            body_sources.clear();
            return body_sources;
        }

        BodyMatchSource source;
        source.spec = &spec;
        source.body_map = &pos_map_it->second;
        if (spec.explicit_mapping) {
            source.explicit_index = build_body_match_index(spec, pos_map_it->second);
        }
        body_sources.push_back(std::move(source));
    }

    return body_sources;
}

static std::vector<Clingo::literal_t> collect_negative_body_literals_for_target(
    HeuristicRuleTemplate const &tmpl,
    GroundLiteralIndexView const &ground_literal_index,
    NumericTupleKey const &target_key
) {
    std::vector<Clingo::literal_t> neg_lits;

    for (auto const &neg_pred : tmpl.neg_body_preds) {
        auto neg_map_it = ground_literal_index.find(neg_pred);
        if (neg_map_it == ground_literal_index.end()) continue;

        auto nit = neg_map_it->second.find(target_key);
        if (nit != neg_map_it->second.end()) {
            neg_lits.push_back(nit->second);
        }
    }

    return neg_lits;
}

static std::vector<PartialMatch> collect_positive_body_partials_for_target(
    std::vector<BodyMatchSource> const &body_sources,
    NumericTupleKey const &target_key
) {
    std::vector<PartialMatch> partials(1);

    for (auto const &source : body_sources) {
        std::vector<BodyLiteralMatch> implicit_matches;
        std::vector<BodyLiteralMatch> const *matches = nullptr;

        if (source.spec->explicit_mapping) {
            NumericTupleKey match_key;
            if (build_body_match_key(*source.spec, target_key, MatchKeySide::Target, match_key)) {
                auto match_it = source.explicit_index.find(match_key);
                if (match_it != source.explicit_index.end()) {
                    matches = &match_it->second;
                }
            }
        }
        else {
            auto match_it = source.body_map->find(target_key);
            if (match_it != source.body_map->end()) {
                BodyLiteralMatch match;
                match.lit = match_it->second;
                if (collect_body_arg_values(*source.spec, target_key, match.variable_values)) {
                    implicit_matches.push_back(std::move(match));
                    matches = &implicit_matches;
                }
            }
        }

        if (matches == nullptr || matches->empty()) {
            partials.clear();
            break;
        }

        std::vector<PartialMatch> next_partials;
        for (auto const &partial : partials) {
            for (auto const &match : *matches) {
                PartialMatch next = partial;
                if (!merge_variable_values(next.body_var_values, match.variable_values)) {
                    continue;
                }
                next.pos_lits.push_back(match.lit);
                next_partials.push_back(std::move(next));
            }
        }
        partials = std::move(next_partials);
        if (partials.empty()) break;
    }

    return partials;
}

static bool merge_variable_values(std::unordered_map<Clingo::Symbol, int> &dst,
                                  std::unordered_map<Clingo::Symbol, int> const &src) {
    for (auto const &value : src) {
        auto inserted = dst.emplace(value.first, value.second);
        if (!inserted.second && inserted.first->second != value.second) {
            return false;
        }
    }
    return true;
}

static bool negative_literal_is_satisfied(HeuristicSemantics semantics, Clingo::TruthValue value) {
    return semantics == HeuristicSemantics::Clingo
        ? value == Clingo::TruthValue::False
        : value != Clingo::TruthValue::True;
}

template <class RefreshOne>
static void refresh_candidate_ids(std::vector<size_t> const &candidate_ids, RefreshOne &&refresh_one) {
    for (size_t candidate_id : candidate_ids) {
        refresh_one(candidate_id);
    }
}

static bool build_runtime_key_from_source_atom(AggregateKey const &agg_key,
                                               Clingo::Symbol const &source_atom,
                                               RuntimeAggregateKey &runtime_key) {
    auto const args = source_atom.arguments();

    runtime_key.key = agg_key;
    runtime_key.filter_values.clear();
    runtime_key.filter_values.reserve(agg_key.filters.size());

    for (auto const &filter : agg_key.filters) {
        int value = 0;
        if (!extract_numeric_argument_at(args, filter.source_arg_index, value)) {
            return false;
        }
        runtime_key.filter_values.push_back(value);
    }

    return true;
}

static bool build_runtime_key_from_target_tuple(AggregateKey const &agg_key,
                                                std::vector<int> const &tuple_values,
                                                RuntimeAggregateKey &runtime_key) {
    runtime_key.key = agg_key;
    runtime_key.filter_values.clear();
    runtime_key.filter_values.reserve(agg_key.filters.size());

    for (auto const &filter : agg_key.filters) {
        if (filter.target_arg_index < 0 ||
            static_cast<size_t>(filter.target_arg_index) >= tuple_values.size()) {
            return false;
        }
        runtime_key.filter_values.push_back(tuple_values[filter.target_arg_index] + filter.target_offset);
    }

    return true;
}

void HeuristicPropagator::init(Clingo::PropagateInit &init) {
    runtime_aggregate_states_.clear();
    aggregate_contributions_by_lit_.clear();
    heuristic_rule_templates_.clear();
    heuristic_candidates_.clear();
    candidate_effects_.clear();
    candidate_ids_by_target_.clear();
    target_states_.clear();
    active_decision_ranks_.clear();
    candidate_ids_to_refresh_by_lit_.clear();
    aggregate_keys_to_refresh_by_lit_.clear();
    candidate_ids_by_aggregate_.clear();
    aggregates_requiring_complete_sources_.clear();
    aggregate_source_lits_.clear();
    registered_watch_lits_.clear();

    std::vector<Clingo::Symbol> heuristic_symbols;
    auto const atoms = init.symbolic_atoms();
    for (auto it = atoms.begin(); it != atoms.end(); ++it) {
        if (is_named_function(it->symbol(), "__heuristic")) {
            heuristic_symbols.push_back(it->symbol());
        }
    }

    auto rule_templates = parse_lazy_heuristic_templates(heuristic_symbols);
    if (rule_templates.empty()) return;

    init_lazy_mode(init, atoms, std::move(rule_templates));
}

std::unordered_set<Clingo::Symbol> HeuristicPropagator::collect_predicates_used_by_lazy_templates() const {
    std::unordered_set<Clingo::Symbol> predicates;

    for (auto const &tmpl : heuristic_rule_templates_) {
        predicates.insert(tmpl.target_pred);

        for (auto const &pos_pred : tmpl.pos_body_preds) {
            predicates.insert(pos_pred.pred_name);
        }

        for (auto const &neg_pred : tmpl.neg_body_preds) {
            predicates.insert(neg_pred);
        }
    }

    return predicates;
}

HeuristicPropagator::GroundLiteralIndex HeuristicPropagator::build_ground_literal_index_for_predicates(
    Clingo::PropagateInit &init,
    Clingo::SymbolicAtoms const &atoms
) const {
    GroundLiteralIndex ground_literal_index;
    auto const predicates = collect_predicates_used_by_lazy_templates();

    for (auto it = atoms.begin(); it != atoms.end(); ++it) {
        auto const symbol = it->symbol();
        if (!is_clingo_symbol_function(symbol)) continue;

        auto const predicate_name = predicate_name_symbol(symbol);
        if (predicates.find(predicate_name) == predicates.end()) continue;

        std::vector<int> numeric_tuple;
        if (!extract_numeric_tuple(symbol, numeric_tuple)) continue;

        Clingo::literal_t const solver_lit = init.solver_literal(it->literal());
        if (solver_lit != 0) {
            ground_literal_index[predicate_name][NumericTupleKey{std::move(numeric_tuple)}] = solver_lit;
        }
    }
    return ground_literal_index;
}

AggregateState *HeuristicPropagator::ensure_aggregate_state(RuntimeAggregateKey const &runtime_key) {
    auto &state = runtime_aggregate_states_[runtime_key];
    if (!state) {
        state = make_aggregate(runtime_key.key.op_symbol.name());
    }
    return state.get();
}

void HeuristicPropagator::add_solver_watch(Clingo::PropagateInit &init, Clingo::literal_t lit) {
    if (lit == 0) return;
    if (registered_watch_lits_.insert(lit).second) {
        init.add_watch(lit);
    }
}

void HeuristicPropagator::watch_literal_for_candidate_refresh(Clingo::PropagateInit &init,
                                                              Clingo::literal_t lit,
                                                              size_t candidate_id) {
    if (lit == 0) return;

    auto &ids = candidate_ids_to_refresh_by_lit_[lit];
    if (std::find(ids.begin(), ids.end(), candidate_id) == ids.end()) {
        ids.push_back(candidate_id);
    }
    add_solver_watch(init, lit);
}

void HeuristicPropagator::watch_literal_for_aggregate_refresh(Clingo::PropagateInit &init,
                                                              Clingo::literal_t lit,
                                                              RuntimeAggregateKey const &runtime_key) {
    if (lit == 0) return;

    auto &runtime_keys = aggregate_keys_to_refresh_by_lit_[lit];
    if (std::find(runtime_keys.begin(), runtime_keys.end(), runtime_key) == runtime_keys.end()) {
        runtime_keys.push_back(runtime_key);
    }
    add_solver_watch(init, lit);
}

HeuristicPropagator::RuntimeHeuristicCandidate HeuristicPropagator::build_runtime_candidate(
    size_t rule_idx,
    Clingo::literal_t target_lit,
    std::vector<int> const &tuple_values,
    std::vector<Clingo::literal_t> pos_body_lits,
    std::vector<Clingo::literal_t> neg_body_lits,
    std::unordered_map<Clingo::Symbol, int> body_var_values
) const {
    auto const &tmpl = heuristic_rule_templates_[rule_idx];

    RuntimeHeuristicCandidate candidate;
    candidate.rule_idx = rule_idx;
    candidate.target_lit = target_lit;
    candidate.self_value = tuple_values.empty() ? 0 : tuple_values[0];
    candidate.tuple_values = tuple_values;
    candidate.body_var_values = std::move(body_var_values);
    candidate.pos_body_lits = std::move(pos_body_lits);
    candidate.neg_body_lits = std::move(neg_body_lits);
    candidate.aggregate_bindings.reserve(tmpl.var_bindings.size());

    for (auto const &vb : tmpl.var_bindings) {
        CandidateAggregateBinding aggregate_binding;
        aggregate_binding.variable_name = vb.first;
        aggregate_binding.has_valid_runtime_key = build_runtime_key_from_target_tuple(
            vb.second,
            candidate.tuple_values,
            aggregate_binding.runtime_key
        );
        candidate.aggregate_bindings.push_back(std::move(aggregate_binding));
    }

    return candidate;
}

size_t HeuristicPropagator::store_runtime_candidate(RuntimeHeuristicCandidate candidate) {
    size_t const candidate_id = heuristic_candidates_.size();
    heuristic_candidates_.push_back(std::move(candidate));
    CandidateHeuristicEffect inactive_effect;
    inactive_effect.candidate_id = candidate_id;
    inactive_effect.target_lit = heuristic_candidates_.back().target_lit;
    inactive_effect.active = false;
    candidate_effects_.push_back(inactive_effect);
    candidate_ids_by_target_[inactive_effect.target_lit].push_back(candidate_id);
    return candidate_id;
}

void HeuristicPropagator::index_candidate_aggregate_dependencies(size_t candidate_id) {
    if (candidate_id >= heuristic_candidates_.size()) return;

    auto const &candidate = heuristic_candidates_[candidate_id];
    bool const uses_clingo_semantics = candidate.rule_idx < heuristic_rule_templates_.size() &&
        heuristic_rule_templates_[candidate.rule_idx].semantics == HeuristicSemantics::Clingo;

    for (auto const &aggregate_binding : candidate.aggregate_bindings) {
        if (!aggregate_binding.has_valid_runtime_key) continue;

        auto &ids = candidate_ids_by_aggregate_[aggregate_binding.runtime_key];
        if (std::find(ids.begin(), ids.end(), candidate_id) == ids.end()) {
            ids.push_back(candidate_id);
        }
        if (uses_clingo_semantics) {
            aggregates_requiring_complete_sources_.insert(aggregate_binding.runtime_key);
        }
    }
}

void HeuristicPropagator::watch_candidate_refresh_literals(Clingo::PropagateInit &init,
                                                           size_t candidate_id) {
    if (candidate_id >= heuristic_candidates_.size()) return;

    auto const &candidate = heuristic_candidates_[candidate_id];

    watch_literal_for_candidate_refresh(init, candidate.target_lit, candidate_id);
    watch_literal_for_candidate_refresh(init, -candidate.target_lit, candidate_id);

    for (auto neg_lit : candidate.neg_body_lits) {
        watch_literal_for_candidate_refresh(init, neg_lit, candidate_id);
        watch_literal_for_candidate_refresh(init, -neg_lit, candidate_id);
    }

    for (auto body_lit : candidate.pos_body_lits) {
        watch_literal_for_candidate_refresh(init, body_lit, candidate_id);
    }
}

void HeuristicPropagator::add_runtime_candidate(
    Clingo::PropagateInit &init,
    size_t rule_idx,
    Clingo::literal_t target_lit,
    std::vector<int> const &tuple_values,
    std::vector<Clingo::literal_t> pos_body_lits,
    std::vector<Clingo::literal_t> neg_body_lits,
    std::unordered_map<Clingo::Symbol, int> body_var_values
) {
    if (target_lit == 0 || rule_idx >= heuristic_rule_templates_.size()) return;

    auto candidate = build_runtime_candidate(rule_idx,
                                             target_lit,
                                             tuple_values,
                                             std::move(pos_body_lits),
                                             std::move(neg_body_lits),
                                             std::move(body_var_values));

    size_t const candidate_id = store_runtime_candidate(std::move(candidate));

    index_candidate_aggregate_dependencies(candidate_id);
    watch_candidate_refresh_literals(init, candidate_id);
}

void HeuristicPropagator::erase_target_decision_rank(Clingo::literal_t target_lit) noexcept {
    auto state_it = target_states_.find(target_lit);
    if (state_it == target_states_.end() || !state_it->second.decision_ranked) return;

    active_decision_ranks_.erase(DecisionRankKey{state_it->second.ranked_level, target_lit});
    state_it->second.decision_ranked = false;
    state_it->second.ranked_level = 0;
}

bool HeuristicPropagator::candidate_target_is_free(RuntimeHeuristicCandidate const &candidate,
                                                   Clingo::Assignment const &assignment) const {
    return candidate.target_lit != 0 &&
           assignment.truth_value(candidate.target_lit) == Clingo::TruthValue::Free;
}

bool HeuristicPropagator::positive_body_is_satisfied(RuntimeHeuristicCandidate const &candidate,
                                                     Clingo::Assignment const &assignment) const {
    for (auto pos_lit : candidate.pos_body_lits) {
        if (pos_lit == 0 ||
            assignment.truth_value(pos_lit) != Clingo::TruthValue::True) {
            return false;
        }
    }
    return true;
}

bool HeuristicPropagator::negative_body_is_satisfied(HeuristicRuleTemplate const &tmpl,
                                                     RuntimeHeuristicCandidate const &candidate,
                                                     Clingo::Assignment const &assignment) const {
    for (auto neg_lit : candidate.neg_body_lits) {
        if (neg_lit == 0) continue;
        if (!negative_literal_is_satisfied(tmpl.semantics, assignment.truth_value(neg_lit))) {
            return false;
        }
    }
    return true;
}

bool HeuristicPropagator::aggregate_sources_are_determined(
    RuntimeAggregateKey const &runtime_key,
    Clingo::Assignment const &assignment
) const {
    auto source_it = aggregate_source_lits_.find(runtime_key);
    if (source_it == aggregate_source_lits_.end()) return true;

    for (auto source_lit : source_it->second) {
        if (assignment.truth_value(source_lit) == Clingo::TruthValue::Free) {
            return false;
        }
    }
    return true;
}

bool HeuristicPropagator::build_variable_environment(
    HeuristicRuleTemplate const &tmpl,
    RuntimeHeuristicCandidate const &candidate,
    Clingo::Assignment const &assignment,
    std::unordered_map<Clingo::Symbol, int> &var_env
) const {
    var_env.clear();
    var_env.reserve(candidate.body_var_values.size() + candidate.aggregate_bindings.size());
    var_env.insert(candidate.body_var_values.begin(), candidate.body_var_values.end());

    for (auto const &binding : candidate.aggregate_bindings) {
        if (!binding.has_valid_runtime_key) {
            if (tmpl.semantics == HeuristicSemantics::Clingo) return false;
            var_env[binding.variable_name] = 0;
            continue;
        }

        if (tmpl.semantics == HeuristicSemantics::Clingo &&
            !aggregate_sources_are_determined(binding.runtime_key, assignment)) {
            return false;
        }

        int val = 0;
        auto state_it = runtime_aggregate_states_.find(binding.runtime_key);
        if (state_it != runtime_aggregate_states_.end() && state_it->second) {
            val = state_it->second->result();
        }
        var_env[binding.variable_name] = val;
    }

    return true;
}

bool HeuristicPropagator::evaluate_candidate_effect(size_t candidate_id,
                                                    Clingo::Assignment const &assignment,
                                                    CandidateHeuristicEffect &effect) const {
    if (candidate_id >= heuristic_candidates_.size()) return false;

    auto const &candidate = heuristic_candidates_[candidate_id];
    if (candidate.rule_idx >= heuristic_rule_templates_.size()) return false;
    auto const &tmpl = heuristic_rule_templates_[candidate.rule_idx];

    if (!candidate_target_is_free(candidate, assignment)) return false;
    if (!positive_body_is_satisfied(candidate, assignment)) return false;
    if (!negative_body_is_satisfied(tmpl, candidate, assignment)) return false;

    std::unordered_map<Clingo::Symbol, int> var_env;
    if (!build_variable_environment(tmpl, candidate, assignment, var_env)) return false;

    int const local_priority = evaluate_arithmetic_expression(
        tmpl.local_priority_expr,
        candidate.self_value,
        var_env
    );
    if (local_priority < 0) {
        throw std::runtime_error("Lazy heuristic clingo-like: __priority locale negativa non supportata.");
    }

    effect.active = true;
    effect.target_lit = candidate.target_lit;
    effect.bias = evaluate_arithmetic_expression(tmpl.bias_expr, candidate.self_value, var_env);
    effect.local_priority = local_priority;
    effect.modifier = tmpl.modifier;
    effect.candidate_id = candidate_id;
    return true;
}

void HeuristicPropagator::update_best_by_local_priority(ResolvedModifierValue &current,
                                                        int local_priority,
                                                        int value,
                                                        size_t candidate_id) const {
    if (!current.active ||
        local_priority > current.local_priority ||
        (local_priority == current.local_priority && candidate_id < current.source_candidate_id)) {
        current.active = true;
        current.local_priority = local_priority;
        current.value = value;
        current.source_candidate_id = candidate_id;
    }
}

void HeuristicPropagator::apply_effect_to_target_state(CandidateHeuristicEffect const &effect,
                                                       TargetHeuristicState &state) const {
    switch (effect.modifier) {
        case HeuristicModifier::Level:
            update_best_by_local_priority(state.level, effect.local_priority, effect.bias, effect.candidate_id);
            break;

        case HeuristicModifier::Sign:
            update_best_by_local_priority(state.sign,
                                          effect.local_priority,
                                          normalize_sign(effect.bias),
                                          effect.candidate_id);
            break;

        case HeuristicModifier::True:
            update_best_by_local_priority(state.level, effect.local_priority, effect.bias, effect.candidate_id);
            update_best_by_local_priority(state.sign, effect.local_priority, +1, effect.candidate_id);
            break;

        case HeuristicModifier::False:
            update_best_by_local_priority(state.level, effect.local_priority, effect.bias, effect.candidate_id);
            update_best_by_local_priority(state.sign, effect.local_priority, -1, effect.candidate_id);
            break;

        case HeuristicModifier::Init:
        case HeuristicModifier::Factor:
            throw std::runtime_error("init/factor non supportati dal lazy heuristic propagator clingo-like.");
    }
}

Clingo::literal_t HeuristicPropagator::apply_resolved_sign(ResolvedModifierValue const &sign,
                                                           Clingo::literal_t target_lit,
                                                           Clingo::literal_t fallback) const {
    if (!sign.active || sign.value == 0) {
        Clingo::literal_t const fallback_target = fallback > 0 ? fallback : -fallback;
        if (fallback_target == target_lit) {
            return fallback;
        }
        return target_lit;
    }

    return sign.value > 0 ? target_lit : -target_lit;
}

void HeuristicPropagator::refresh_target(Clingo::literal_t target_lit, Clingo::Assignment const &assignment) {
    erase_target_decision_rank(target_lit);

    TargetHeuristicState new_state;
    new_state.target_lit = target_lit;

    auto ids_it = candidate_ids_by_target_.find(target_lit);
    if (ids_it != candidate_ids_by_target_.end()) {
        for (size_t candidate_id : ids_it->second) {
            if (candidate_id >= candidate_effects_.size()) continue;

            auto const &effect = candidate_effects_[candidate_id];
            if (!effect.active) continue;

            apply_effect_to_target_state(effect, new_state);
        }
    }

    target_states_[target_lit] = new_state;

    if (new_state.level.active &&
        new_state.level.value > 0 &&
        assignment.truth_value(target_lit) == Clingo::TruthValue::Free) {
        active_decision_ranks_.insert(DecisionRankKey{new_state.level.value, target_lit});
        auto &stored_state = target_states_[target_lit];
        stored_state.decision_ranked = true;
        stored_state.ranked_level = new_state.level.value;
    }
}

void HeuristicPropagator::refresh_candidate(size_t candidate_id, Clingo::Assignment const &assignment) {
    if (candidate_id >= heuristic_candidates_.size()) return;

    Clingo::literal_t const target_lit = heuristic_candidates_[candidate_id].target_lit;
    CandidateHeuristicEffect effect;
    effect.active = false;
    effect.target_lit = target_lit;
    effect.candidate_id = candidate_id;

    evaluate_candidate_effect(candidate_id, assignment, effect);

    if (candidate_id < candidate_effects_.size()) {
        candidate_effects_[candidate_id] = effect;
    }
    refresh_target(target_lit, assignment);
}

void HeuristicPropagator::refresh_candidate_noexcept(size_t candidate_id,
                                                     Clingo::Assignment const &assignment) noexcept {
    try {
        refresh_candidate(candidate_id, assignment);
    }
    catch (...) {
        if (candidate_id >= heuristic_candidates_.size()) return;

        Clingo::literal_t const target_lit = heuristic_candidates_[candidate_id].target_lit;
        if (candidate_id < candidate_effects_.size()) {
            candidate_effects_[candidate_id].active = false;
        }
        try {
            refresh_target(target_lit, assignment);
        }
        catch (...) {
            erase_target_decision_rank(target_lit);
        }
    }
}

void HeuristicPropagator::refresh_aggregates_for_literal(Clingo::literal_t lit,
                                                         Clingo::Assignment const &assignment) {
    auto refresh_it = aggregate_keys_to_refresh_by_lit_.find(lit);
    if (refresh_it == aggregate_keys_to_refresh_by_lit_.end()) return;

    for (auto const &runtime_key : refresh_it->second) {
        refresh_candidates_for_aggregate(runtime_key, assignment);
    }
}

void HeuristicPropagator::refresh_aggregates_for_literal_noexcept(
    Clingo::literal_t lit,
    Clingo::Assignment const &assignment
) noexcept {
    auto refresh_it = aggregate_keys_to_refresh_by_lit_.find(lit);
    if (refresh_it == aggregate_keys_to_refresh_by_lit_.end()) return;

    for (auto const &runtime_key : refresh_it->second) {
        refresh_candidates_for_aggregate_noexcept(runtime_key, assignment);
    }
}

void HeuristicPropagator::refresh_candidates_for_literal(Clingo::literal_t lit,
                                                         Clingo::Assignment const &assignment) {
    auto refresh_it = candidate_ids_to_refresh_by_lit_.find(lit);
    if (refresh_it == candidate_ids_to_refresh_by_lit_.end()) return;

    refresh_candidate_ids(refresh_it->second, [this, &assignment](size_t candidate_id) {
        refresh_candidate(candidate_id, assignment);
    });
}

void HeuristicPropagator::refresh_candidates_for_literal_noexcept(Clingo::literal_t lit,
                                                                  Clingo::Assignment const &assignment) noexcept {
    auto refresh_it = candidate_ids_to_refresh_by_lit_.find(lit);
    if (refresh_it == candidate_ids_to_refresh_by_lit_.end()) return;

    refresh_candidate_ids(refresh_it->second, [this, &assignment](size_t candidate_id) {
        refresh_candidate_noexcept(candidate_id, assignment);
    });
}

void HeuristicPropagator::refresh_candidates_for_aggregate(RuntimeAggregateKey const &runtime_key,
                                                           Clingo::Assignment const &assignment) {
    auto candidate_it = candidate_ids_by_aggregate_.find(runtime_key);
    if (candidate_it == candidate_ids_by_aggregate_.end()) return;

    refresh_candidate_ids(candidate_it->second, [this, &assignment](size_t candidate_id) {
        refresh_candidate(candidate_id, assignment);
    });
}

void HeuristicPropagator::refresh_candidates_for_aggregate_noexcept(
    RuntimeAggregateKey const &runtime_key,
    Clingo::Assignment const &assignment
) noexcept {
    auto candidate_it = candidate_ids_by_aggregate_.find(runtime_key);
    if (candidate_it == candidate_ids_by_aggregate_.end()) return;

    refresh_candidate_ids(candidate_it->second, [this, &assignment](size_t candidate_id) {
        refresh_candidate_noexcept(candidate_id, assignment);
    });
}

void HeuristicPropagator::refresh_all_candidates(Clingo::Assignment const &assignment) {
    for (size_t candidate_id = 0; candidate_id < heuristic_candidates_.size(); ++candidate_id) {
        refresh_candidate(candidate_id, assignment);
    }
}

void HeuristicPropagator::materialize_lazy_candidates_and_register_watches(
    Clingo::PropagateInit &init,
    GroundLiteralIndex const &ground_literal_index
) {
    for (size_t rule_idx = 0; rule_idx < heuristic_rule_templates_.size(); ++rule_idx) {
        materialize_candidates_for_template(init, rule_idx, ground_literal_index);
    }
}

void HeuristicPropagator::materialize_candidates_for_template(
    Clingo::PropagateInit &init,
    size_t rule_idx,
    GroundLiteralIndex const &ground_literal_index
) {
    auto const &tmpl = heuristic_rule_templates_[rule_idx];

    auto target_map_it = ground_literal_index.find(tmpl.target_pred);
    if (target_map_it == ground_literal_index.end()) return;

    auto body_sources = build_body_match_sources_for_template(tmpl, ground_literal_index);
    if (body_sources.size() != tmpl.pos_body_preds.size()) return;

    for (auto const &target_entry : target_map_it->second) {
        NumericTupleKey const &target_key = target_entry.first;
        Clingo::literal_t const target_lit = target_entry.second;
        if (target_lit == 0) continue;

        auto neg_lits = collect_negative_body_literals_for_target(tmpl, ground_literal_index, target_key);
        auto partials = collect_positive_body_partials_for_target(body_sources, target_key);

        for (auto &partial : partials) {
            add_runtime_candidate(init,
                                  rule_idx,
                                  target_lit,
                                  target_key.values,
                                  std::move(partial.pos_lits),
                                  neg_lits,
                                  std::move(partial.body_var_values));
        }
    }
}

std::unordered_map<Clingo::Symbol, std::vector<AggregateKey>>
HeuristicPropagator::collect_aggregate_keys_by_source_predicate() const {
    std::unordered_map<Clingo::Symbol, std::vector<AggregateKey>> aggregate_keys_by_pred;

    for (auto const &tmpl : heuristic_rule_templates_) {
        for (auto const &vb : tmpl.var_bindings) {
            AggregateKey const &agg_key = vb.second;
            auto &keys = aggregate_keys_by_pred[agg_key.pred_symbol];
            if (std::find(keys.begin(), keys.end(), agg_key) == keys.end()) {
                keys.push_back(agg_key);
            }
        }
    }

    return aggregate_keys_by_pred;
}

bool HeuristicPropagator::aggregate_requires_complete_sources(RuntimeAggregateKey const &runtime_key) const {
    return aggregates_requiring_complete_sources_.find(runtime_key) != aggregates_requiring_complete_sources_.end();
}

void HeuristicPropagator::initialize_aggregate_source_atom(
    Clingo::PropagateInit &init,
    Clingo::Assignment const &assignment,
    Clingo::Symbol const &source_symbol,
    Clingo::literal_t source_lit,
    AggregateKey const &aggregate_key
) {
    int value = 0;
    if (!extract_numeric_aggregate_value(source_symbol, aggregate_key.arg_index, value)) return;

    RuntimeAggregateKey runtime_key;
    if (!build_runtime_key_from_source_atom(aggregate_key, source_symbol, runtime_key)) return;

    auto &source_lits = aggregate_source_lits_[runtime_key];
    if (std::find(source_lits.begin(), source_lits.end(), source_lit) == source_lits.end()) {
        source_lits.push_back(source_lit);
    }

    add_solver_watch(init, source_lit);

    if (aggregate_requires_complete_sources(runtime_key)) {
        watch_literal_for_aggregate_refresh(init, -source_lit, runtime_key);
    }

    auto &contributions = aggregate_contributions_by_lit_[source_lit].values;
    bool already = false;
    for (auto const &contribution : contributions) {
        if (contribution.runtime_key == runtime_key && contribution.value == value) {
            already = true;
            break;
        }
    }
    if (already) return;

    AggregateContribution contribution{runtime_key, value};
    auto *state = ensure_aggregate_state(contribution.runtime_key);
    if (assignment.is_true(source_lit) && state != nullptr) {
        state->add(contribution.value);
    }
    contributions.push_back(std::move(contribution));
}

void HeuristicPropagator::initialize_aggregate_sources(Clingo::PropagateInit &init,
                                                       Clingo::SymbolicAtoms const &atoms) {
    auto assignment = init.assignment();
    auto aggregate_keys_by_pred = collect_aggregate_keys_by_source_predicate();

    if (aggregate_keys_by_pred.empty()) return;

    for (auto it = atoms.begin(); it != atoms.end(); ++it) {
        auto const sym = it->symbol();
        if (!is_clingo_symbol_function(sym)) continue;

        auto key_it = aggregate_keys_by_pred.find(predicate_name_symbol(sym));
        if (key_it == aggregate_keys_by_pred.end()) continue;

        Clingo::literal_t const slit = init.solver_literal(it->literal());
        if (slit == 0) continue;

        for (auto const &agg_key : key_it->second) {
            initialize_aggregate_source_atom(init, assignment, sym, slit, agg_key);
        }
    }
}

void HeuristicPropagator::init_lazy_mode(Clingo::PropagateInit &init,
                                         Clingo::SymbolicAtoms const &atoms,
                                         std::vector<HeuristicRuleTemplate> rule_templates) {
    heuristic_rule_templates_ = std::move(rule_templates);
    if (heuristic_rule_templates_.empty()) return;

    GroundLiteralIndex ground_literal_index = build_ground_literal_index_for_predicates(init, atoms);

    materialize_lazy_candidates_and_register_watches(init, ground_literal_index);

    initialize_aggregate_sources(init, atoms);

    refresh_all_candidates(init.assignment());
}

void HeuristicPropagator::propagate(Clingo::PropagateControl &control, Clingo::LiteralSpan changes) {
    auto assignment = control.assignment();

    for (auto lit : changes) {
        auto contribution_it = aggregate_contributions_by_lit_.find(lit);
        if (contribution_it != aggregate_contributions_by_lit_.end()) {
            for (auto const &contrib : contribution_it->second.values) {
                auto *state = ensure_aggregate_state(contrib.runtime_key);
                if (state != nullptr) {
                    state->add(contrib.value);
                }
                refresh_candidates_for_aggregate(contrib.runtime_key, assignment);
            }
        }

        refresh_aggregates_for_literal(lit, assignment);
        refresh_candidates_for_literal(lit, assignment);
    }
}

void HeuristicPropagator::undo(Clingo::PropagateControl const &control, Clingo::LiteralSpan changes) noexcept {
    auto assignment = control.assignment();

    for (auto lit : changes) {
        auto contribution_it = aggregate_contributions_by_lit_.find(lit);
        if (contribution_it != aggregate_contributions_by_lit_.end()) {
            for (auto const &contrib : contribution_it->second.values) {
                auto state_it = runtime_aggregate_states_.find(contrib.runtime_key);
                if (state_it != runtime_aggregate_states_.end() && state_it->second) {
                    state_it->second->remove(contrib.value);
                }
                refresh_candidates_for_aggregate_noexcept(contrib.runtime_key, assignment);
            }
        }

        refresh_aggregates_for_literal_noexcept(lit, assignment);
        refresh_candidates_for_literal_noexcept(lit, assignment);
    }
}

Clingo::literal_t HeuristicPropagator::decide(Clingo::id_t thread_id,
                                               Clingo::Assignment const &assignment,
                                               Clingo::literal_t fallback) noexcept {
    static_cast<void>(thread_id);

    try {
        while (!active_decision_ranks_.empty()) {
            DecisionRankKey const rank_key = *active_decision_ranks_.begin();
            auto state_it = target_states_.find(rank_key.target_lit);
            if (state_it == target_states_.end()) {
                active_decision_ranks_.erase(active_decision_ranks_.begin());
                continue;
            }

            auto const &state = state_it->second;
            if (assignment.truth_value(rank_key.target_lit) != Clingo::TruthValue::Free) {
                erase_target_decision_rank(rank_key.target_lit);
                continue;
            }

            if (!state.level.active ||
                state.level.value != rank_key.level ||
                state.level.value <= 0) {
                erase_target_decision_rank(rank_key.target_lit);
                continue;
            }

            return apply_resolved_sign(state.sign, rank_key.target_lit, fallback);
        }

        Clingo::literal_t const fallback_target = fallback > 0 ? fallback : -fallback;
        if (fallback_target != 0 &&
            assignment.truth_value(fallback_target) == Clingo::TruthValue::Free) {
            auto state_it = target_states_.find(fallback_target);
            if (state_it != target_states_.end() && state_it->second.sign.active) {
                return apply_resolved_sign(state_it->second.sign, fallback_target, fallback);
            }
        }
    }
    catch (...) {
        return 0;
    }

    return 0;
}
