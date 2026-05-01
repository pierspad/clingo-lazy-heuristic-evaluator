#include "clingo/heuristic_propagator.hh"
#include "clingo/heuristic_parser.hh"
#include "clingo/heuristic_symbol.hh"

#include <algorithm>
#include <unordered_set>
#include <utility>

static Clingo::literal_t apply_sign(HeuristicSign sign, Clingo::literal_t target_lit, Clingo::literal_t fallback) {
    switch (sign) {
        case HeuristicSign::True:  return target_lit;
        case HeuristicSign::False: return -target_lit;
        case HeuristicSign::FollowFallback: return fallback < 0 ? -target_lit : target_lit;
    }
    return target_lit;
}

static bool build_body_match_key_from_body(BodyPredicateSpec const &spec,
                                           AtomKey const &body_key,
                                           AtomKey &match_key) {
    match_key.values.clear();
    match_key.values.reserve(spec.matches.size());
    for (auto const &match : spec.matches) {
        if (match.source_arg_index < 0 ||
            static_cast<size_t>(match.source_arg_index) >= body_key.values.size()) {
            return false;
        }
        match_key.values.push_back(body_key.values[match.source_arg_index]);
    }
    return true;
}

static bool build_body_match_key_from_target(BodyPredicateSpec const &spec,
                                             AtomKey const &target_key,
                                             AtomKey &match_key) {
    match_key.values.clear();
    match_key.values.reserve(spec.matches.size());
    for (auto const &match : spec.matches) {
        if (match.target_arg_index < 0 ||
            static_cast<size_t>(match.target_arg_index) >= target_key.values.size()) {
            return false;
        }
        match_key.values.push_back(target_key.values[match.target_arg_index]);
    }
    return true;
}

static bool collect_body_arg_values(BodyPredicateSpec const &spec,
                                    AtomKey const &body_key,
                                    std::unordered_map<std::string, int> &values) {
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
    std::unordered_map<std::string, int> variable_values;
};

using BodyMatchIndex = std::unordered_map<AtomKey, std::vector<BodyLiteralMatch>, AtomKeyHash>;

static BodyMatchIndex build_body_match_index(
    BodyPredicateSpec const &spec,
    std::unordered_map<AtomKey, Clingo::literal_t, AtomKeyHash> const &body_map
) {
    BodyMatchIndex index;
    index.reserve(body_map.size());

    for (auto const &entry : body_map) {
        AtomKey match_key;
        if (!build_body_match_key_from_body(spec, entry.first, match_key)) continue;

        BodyLiteralMatch match;
        match.lit = entry.second;
        if (collect_body_arg_values(spec, entry.first, match.variable_values)) {
            index[std::move(match_key)].push_back(std::move(match));
        }
    }

    return index;
}

static bool merge_variable_values(std::unordered_map<std::string, int> &dst,
                                  std::unordered_map<std::string, int> const &src) {
    for (auto const &value : src) {
        auto inserted = dst.emplace(value.first, value.second);
        if (!inserted.second && inserted.first->second != value.second) {
            return false;
        }
    }
    return true;
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
        if (!extract_numeric_argument_from_args(args, filter.source_arg_index, value)) {
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
    aggregate_states_.clear();
    watched_atoms_.clear();
    rule_templates_.clear();
    candidates_.clear();
    candidate_queue_.clear();
    candidate_refresh_lits_.clear();
    aggregate_candidates_.clear();
    aggregate_source_lits_.clear();
    registered_watches_.clear();

    auto atoms = init.symbolic_atoms();
    for (auto it = atoms.begin(); it != atoms.end(); ++it) {
        if (is_named_function(it->symbol(), "__heuristic")) {
            init_lazy_mode(init);
            return;
        }
    }
}

HeuristicPropagator::RulePredicateSets HeuristicPropagator::extract_lazy_predicate_sets() const {
    RulePredicateSets predicates;

    for (auto const &tmpl : rule_templates_) {
        predicates.target_preds.insert(tmpl.target_pred);

        for (auto const &pos_pred : tmpl.pos_body_preds) {
            predicates.body_preds.insert(pos_pred.pred_name);
        }

        for (auto const &neg_pred : tmpl.neg_body_preds) {
            predicates.neg_preds.insert(neg_pred);
        }

    }

    return predicates;
}

HeuristicPropagator::PredLitMap HeuristicPropagator::build_lazy_predicate_literal_map(
    Clingo::PropagateInit &init,
    Clingo::SymbolicAtoms const &atoms,
    RulePredicateSets const &predicates
) const {
    PredLitMap pred_lit_map;

    std::unordered_set<std::string> all_preds;
    all_preds.insert(predicates.body_preds.begin(), predicates.body_preds.end());
    all_preds.insert(predicates.target_preds.begin(), predicates.target_preds.end());
    all_preds.insert(predicates.neg_preds.begin(), predicates.neg_preds.end());

    for (auto it = atoms.begin(); it != atoms.end(); ++it) {
        auto const symbol = it->symbol();
        if (!is_clingo_symbol_function(symbol)) continue;

        auto const pname = symbol.name();
        if (all_preds.find(pname) == all_preds.end()) continue;

        auto const sym_args = symbol.arguments();
        if (sym_args.empty()) continue;

        std::vector<int> tuple_values;
        if (!extract_numeric_arguments(symbol, tuple_values)) continue;

        Clingo::literal_t slit = init.solver_literal(it->literal());
        if (slit != 0) pred_lit_map[pname][AtomKey{std::move(tuple_values)}] = slit;
    }
    return pred_lit_map;
}

void HeuristicPropagator::add_solver_watch(Clingo::PropagateInit &init, Clingo::literal_t lit) {
    if (lit == 0) return;
    if (registered_watches_.insert(lit).second) {
        init.add_watch(lit);
    }
}

void HeuristicPropagator::register_candidate_refresh_watch(Clingo::PropagateInit &init,
                                                           Clingo::literal_t lit,
                                                           size_t candidate_id) {
    if (lit == 0) return;

    auto &ids = candidate_refresh_lits_[lit];
    if (std::find(ids.begin(), ids.end(), candidate_id) == ids.end()) {
        ids.push_back(candidate_id);
    }
    add_solver_watch(init, lit);
}

void HeuristicPropagator::add_candidate(Clingo::PropagateInit &init,
                                        size_t rule_idx,
                                        Clingo::literal_t target_lit,
                                        std::vector<int> const &tuple_values,
                                        std::vector<Clingo::literal_t> pos_body_lits,
                                        std::vector<Clingo::literal_t> neg_body_lits,
                                        std::unordered_map<std::string, int> body_var_values) {
    if (target_lit == 0 || rule_idx >= rule_templates_.size()) return;

    auto const candidate_id = candidates_.size();
    auto const &tmpl = rule_templates_[rule_idx];

    CandidateState candidate;
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
        aggregate_binding.valid_key = build_runtime_key_from_target_tuple(
            vb.second,
            candidate.tuple_values,
            aggregate_binding.runtime_key
        );
        if (aggregate_binding.valid_key) {
            auto &ids = aggregate_candidates_[aggregate_binding.runtime_key];
            if (std::find(ids.begin(), ids.end(), candidate_id) == ids.end()) {
                ids.push_back(candidate_id);
            }
        }
        candidate.aggregate_bindings.push_back(std::move(aggregate_binding));
    }

    candidates_.push_back(std::move(candidate));

    register_candidate_refresh_watch(init, target_lit, candidate_id);
    register_candidate_refresh_watch(init, -target_lit, candidate_id);

    for (auto neg_lit : candidates_[candidate_id].neg_body_lits) {
        register_candidate_refresh_watch(init, neg_lit, candidate_id);
        register_candidate_refresh_watch(init, -neg_lit, candidate_id);
    }

    for (auto body_lit : candidates_[candidate_id].pos_body_lits) {
        register_candidate_refresh_watch(init, body_lit, candidate_id);
    }
}

void HeuristicPropagator::erase_candidate_from_queue(size_t candidate_id) noexcept {
    if (candidate_id >= candidates_.size()) return;

    auto &candidate = candidates_[candidate_id];
    if (candidate.queued) {
        candidate_queue_.erase(candidate.queue_entry);
        candidate.queued = false;
    }
}

bool HeuristicPropagator::compute_candidate_entry(size_t candidate_id,
                                                  Clingo::Assignment const &assignment,
                                                  CandidateQueueEntry &entry) const {
    if (candidate_id >= candidates_.size()) return false;

    auto const &candidate = candidates_[candidate_id];
    auto const &tmpl = rule_templates_[candidate.rule_idx];

    if (candidate.target_lit == 0 ||
        assignment.truth_value(candidate.target_lit) != Clingo::TruthValue::Free) {
        return false;
    }

    for (auto pos_lit : candidate.pos_body_lits) {
        if (pos_lit == 0 ||
            assignment.truth_value(pos_lit) != Clingo::TruthValue::True) {
            return false;
        }
    }

    for (auto neg_lit : candidate.neg_body_lits) {
        if (neg_lit == 0) continue;
        auto const value = assignment.truth_value(neg_lit);
        if (tmpl.semantics == HeuristicSemantics::Clingo) {
            if (value != Clingo::TruthValue::False) return false;
        }
        else if (value == Clingo::TruthValue::True) {
            return false;
        }
    }

    std::unordered_map<std::string, int> var_env;
    var_env.reserve(candidate.body_var_values.size() + candidate.aggregate_bindings.size());
    var_env.insert(candidate.body_var_values.begin(), candidate.body_var_values.end());
    for (auto const &binding : candidate.aggregate_bindings) {
        if (!binding.valid_key) {
            if (tmpl.semantics == HeuristicSemantics::Clingo) return false;
            var_env[binding.variable_name] = 0;
            continue;
        }

        if (tmpl.semantics == HeuristicSemantics::Clingo) {
            auto source_it = aggregate_source_lits_.find(binding.runtime_key);
            if (source_it != aggregate_source_lits_.end()) {
                for (auto source_lit : source_it->second) {
                    if (assignment.truth_value(source_lit) == Clingo::TruthValue::Free) {
                        return false;
                    }
                }
            }
        }

        int val = 0;
        auto state_it = aggregate_states_.find(binding.runtime_key);
        if (state_it != aggregate_states_.end() && state_it->second) {
            val = state_it->second->result();
        }
        var_env[binding.variable_name] = val;
    }

    entry.priority = evaluate_arithmetic_expression(tmpl.priority_expr, candidate.self_value, var_env);
    entry.weight = evaluate_arithmetic_expression(tmpl.weight_expr, candidate.self_value, var_env);
    entry.target_lit = candidate.target_lit;
    entry.candidate_id = candidate_id;
    return true;
}

void HeuristicPropagator::refresh_candidate(size_t candidate_id, Clingo::Assignment const &assignment) {
    if (candidate_id >= candidates_.size()) return;

    erase_candidate_from_queue(candidate_id);

    CandidateQueueEntry entry;
    if (compute_candidate_entry(candidate_id, assignment, entry)) {
        candidate_queue_.insert(entry);
        candidates_[candidate_id].queue_entry = entry;
        candidates_[candidate_id].queued = true;
    }
}

void HeuristicPropagator::refresh_candidate_noexcept(size_t candidate_id,
                                                     Clingo::Assignment const &assignment) noexcept {
    try {
        refresh_candidate(candidate_id, assignment);
    }
    catch (...) {
        erase_candidate_from_queue(candidate_id);
    }
}

void HeuristicPropagator::refresh_candidates_for_literal(Clingo::literal_t lit,
                                                         Clingo::Assignment const &assignment) {
    auto refresh_it = candidate_refresh_lits_.find(lit);
    if (refresh_it == candidate_refresh_lits_.end()) return;

    for (size_t candidate_id : refresh_it->second) {
        refresh_candidate(candidate_id, assignment);
    }
}

void HeuristicPropagator::refresh_candidates_for_literal_noexcept(Clingo::literal_t lit,
                                                                  Clingo::Assignment const &assignment) noexcept {
    auto refresh_it = candidate_refresh_lits_.find(lit);
    if (refresh_it == candidate_refresh_lits_.end()) return;

    for (size_t candidate_id : refresh_it->second) {
        refresh_candidate_noexcept(candidate_id, assignment);
    }
}

void HeuristicPropagator::refresh_candidates_for_aggregate(RuntimeAggregateKey const &runtime_key,
                                                           Clingo::Assignment const &assignment) {
    auto candidate_it = aggregate_candidates_.find(runtime_key);
    if (candidate_it == aggregate_candidates_.end()) return;

    for (size_t candidate_id : candidate_it->second) {
        refresh_candidate(candidate_id, assignment);
    }
}

void HeuristicPropagator::refresh_candidates_for_aggregate_noexcept(
    RuntimeAggregateKey const &runtime_key,
    Clingo::Assignment const &assignment
) noexcept {
    auto candidate_it = aggregate_candidates_.find(runtime_key);
    if (candidate_it == aggregate_candidates_.end()) return;

    for (size_t candidate_id : candidate_it->second) {
        refresh_candidate_noexcept(candidate_id, assignment);
    }
}

void HeuristicPropagator::refresh_all_candidates(Clingo::Assignment const &assignment) {
    for (size_t candidate_id = 0; candidate_id < candidates_.size(); ++candidate_id) {
        refresh_candidate(candidate_id, assignment);
    }
}

void HeuristicPropagator::register_lazy_body_triggers(Clingo::PropagateInit &init,
                                                      PredLitMap const &pred_lit_map) {
    struct BodyMatchSource {
        BodyPredicateSpec const *spec = nullptr;
        std::unordered_map<AtomKey, Clingo::literal_t, AtomKeyHash> const *body_map = nullptr;
        BodyMatchIndex explicit_index;
    };

    for (size_t ri = 0; ri < rule_templates_.size(); ++ri) {
        auto const &tmpl = rule_templates_[ri];

        auto target_map_it = pred_lit_map.find(tmpl.target_pred);
        if (target_map_it == pred_lit_map.end()) continue;

        std::vector<BodyMatchSource> body_sources;
        body_sources.reserve(tmpl.pos_body_preds.size());

        bool missing_body_predicate = false;
        for (auto const &spec : tmpl.pos_body_preds) {
            auto pos_map_it = pred_lit_map.find(spec.pred_name);
            if (pos_map_it == pred_lit_map.end()) {
                missing_body_predicate = true;
                break;
            }

            BodyMatchSource source;
            source.spec = &spec;
            source.body_map = &pos_map_it->second;
            if (spec.explicit_mapping) {
                source.explicit_index = build_body_match_index(spec, pos_map_it->second);
            }
            body_sources.push_back(std::move(source));
        }

        if (missing_body_predicate) continue;

        for (auto const &target_entry : target_map_it->second) {
            AtomKey const &target_key = target_entry.first;
            Clingo::literal_t const target_lit = target_entry.second;
            if (target_lit == 0) continue;

            std::vector<Clingo::literal_t> neg_lits;
            for (auto const &neg_pred : tmpl.neg_body_preds) {
                auto neg_map_it = pred_lit_map.find(neg_pred);
                if (neg_map_it != pred_lit_map.end()) {
                    auto nit = neg_map_it->second.find(target_key);
                    if (nit != neg_map_it->second.end()) neg_lits.push_back(nit->second);
                }
            }

            struct PartialMatch {
                std::vector<Clingo::literal_t> pos_lits;
                std::unordered_map<std::string, int> body_var_values;
            };

            std::vector<PartialMatch> partials(1);

            for (auto const &source : body_sources) {
                std::vector<BodyLiteralMatch> implicit_matches;
                std::vector<BodyLiteralMatch> const *matches = nullptr;

                if (source.spec->explicit_mapping) {
                    AtomKey match_key;
                    if (build_body_match_key_from_target(*source.spec, target_key, match_key)) {
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

            for (auto &partial : partials) {
                add_candidate(init,
                              ri,
                              target_lit,
                              target_key.values,
                              std::move(partial.pos_lits),
                              neg_lits,
                              std::move(partial.body_var_values));
            }
        }
    }
}

void HeuristicPropagator::register_lazy_aggregate_watches(Clingo::PropagateInit &init,
                                                          Clingo::SymbolicAtoms const &atoms) {
    auto assignment = init.assignment();

    std::unordered_map<std::string, std::vector<AggregateKey>> aggregate_keys_by_pred;
    for (auto const &tmpl : rule_templates_) {
        for (auto const &vb : tmpl.var_bindings) {
            AggregateKey const &agg_key = vb.second;
            auto &keys = aggregate_keys_by_pred[agg_key.pred_name];
            if (std::find(keys.begin(), keys.end(), agg_key) == keys.end()) {
                keys.push_back(agg_key);
            }
        }
    }

    if (aggregate_keys_by_pred.empty()) return;

    for (auto it = atoms.begin(); it != atoms.end(); ++it) {
        auto const sym = it->symbol();
        if (!is_clingo_symbol_function(sym)) continue;

        auto key_it = aggregate_keys_by_pred.find(sym.name());
        if (key_it == aggregate_keys_by_pred.end()) continue;

        Clingo::literal_t const slit = init.solver_literal(it->literal());
        if (slit == 0) continue;

        for (auto const &agg_key : key_it->second) {
            int value = 0;
            if (!extract_numeric_argument(sym, agg_key.arg_index, value)) continue;

            RuntimeAggregateKey runtime_key;
            if (!build_runtime_key_from_source_atom(agg_key, sym, runtime_key)) continue;

            auto &source_lits = aggregate_source_lits_[runtime_key];
            if (std::find(source_lits.begin(), source_lits.end(), slit) == source_lits.end()) {
                source_lits.push_back(slit);
            }

            add_solver_watch(init, slit);

            auto aggregate_candidate_it = aggregate_candidates_.find(runtime_key);
            if (aggregate_candidate_it != aggregate_candidates_.end()) {
                for (size_t candidate_id : aggregate_candidate_it->second) {
                    register_candidate_refresh_watch(init, -slit, candidate_id);
                }
            }

            auto &watch_info = watched_atoms_[slit];
            bool already = false;
            for (auto const &c : watch_info.contributions) {
                if (c.runtime_key == runtime_key && c.value == value) {
                    already = true;
                    break;
                }
            }
            if (!already) {
                WatchedAtomContribution contribution{runtime_key, value};
                auto &state = aggregate_states_[contribution.runtime_key];
                if (!state) {
                    state = make_aggregate(contribution.runtime_key.key.op_name);
                }
                if (assignment.is_true(slit) && state) {
                    state->add(contribution.value);
                }
                watch_info.contributions.push_back(std::move(contribution));
            }
        }
    }
}

void HeuristicPropagator::init_lazy_mode(Clingo::PropagateInit &init) {
    auto atoms = init.symbolic_atoms();

    rule_templates_ = parse_lazy_heuristic_templates(atoms);
    if (rule_templates_.empty()) return;

    RulePredicateSets predicates = extract_lazy_predicate_sets();

    PredLitMap pred_lit_map = build_lazy_predicate_literal_map(init, atoms, predicates);

    register_lazy_body_triggers(init, pred_lit_map);

    register_lazy_aggregate_watches(init, atoms);

    refresh_all_candidates(init.assignment());
}

void HeuristicPropagator::propagate(Clingo::PropagateControl &control, Clingo::LiteralSpan changes) {
    auto assignment = control.assignment();

    for (auto lit : changes) {
        auto watch_it = watched_atoms_.find(lit);
        if (watch_it != watched_atoms_.end()) {
            for (auto const &contrib : watch_it->second.contributions) {
                auto &state = aggregate_states_[contrib.runtime_key];
                if (!state) {
                    state = make_aggregate(contrib.runtime_key.key.op_name);
                }
                if (state) {
                    state->add(contrib.value);
                }
                refresh_candidates_for_aggregate(contrib.runtime_key, assignment);
            }
        }

        refresh_candidates_for_literal(lit, assignment);
    }
}

void HeuristicPropagator::undo(Clingo::PropagateControl const &control, Clingo::LiteralSpan changes) noexcept {
    auto assignment = control.assignment();

    for (auto lit : changes) {
        auto watch_it = watched_atoms_.find(lit);
        if (watch_it != watched_atoms_.end()) {
            for (auto const &contrib : watch_it->second.contributions) {
                auto state_it = aggregate_states_.find(contrib.runtime_key);
                if (state_it != aggregate_states_.end())
                    state_it->second->remove(contrib.value);
                refresh_candidates_for_aggregate_noexcept(contrib.runtime_key, assignment);
            }
        }

        refresh_candidates_for_literal_noexcept(lit, assignment);
    }
}

Clingo::literal_t HeuristicPropagator::decide(Clingo::id_t thread_id,
                                               Clingo::Assignment const &assignment,
                                               Clingo::literal_t fallback) noexcept {
    static_cast<void>(thread_id);

    try {
        while (!candidate_queue_.empty()) {
            CandidateQueueEntry const entry = *candidate_queue_.begin();
            size_t const candidate_id = entry.candidate_id;

            if (candidate_id >= candidates_.size() ||
                !candidates_[candidate_id].queued ||
                !(candidates_[candidate_id].queue_entry == entry)) {
                candidate_queue_.erase(candidate_queue_.begin());
                continue;
            }

            CandidateQueueEntry refreshed;
            if (!compute_candidate_entry(candidate_id, assignment, refreshed)) {
                erase_candidate_from_queue(candidate_id);
                continue;
            }

            if (!(refreshed == entry)) {
                try {
                    erase_candidate_from_queue(candidate_id);
                    candidate_queue_.insert(refreshed);
                    candidates_[candidate_id].queue_entry = refreshed;
                    candidates_[candidate_id].queued = true;
                }
                catch (...) {
                    erase_candidate_from_queue(candidate_id);
                }
                continue;
            }

            auto const &tmpl = rule_templates_[candidates_[candidate_id].rule_idx];
            return apply_sign(tmpl.sign, entry.target_lit, fallback);
        }
    }
    catch (...) {
        return 0;
    }

    return 0;
}
