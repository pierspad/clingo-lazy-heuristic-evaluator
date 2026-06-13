#pragma once

#include <clingo.hh>
#include <cstddef>
#include <string>
#include <vector>

inline bool is_clingo_symbol_function(Clingo::Symbol const &symbol) {
    return symbol.type() == Clingo::SymbolType::Function;
}

inline bool is_clingo_symbol_number(Clingo::Symbol const &symbol) {
    return symbol.type() == Clingo::SymbolType::Number;
}

inline bool is_nullary_function(Clingo::Symbol const &symbol) {
    return is_clingo_symbol_function(symbol) && symbol.arguments().empty();
}

inline bool is_named_function(Clingo::Symbol const &symbol, std::string const &name) {
    return is_clingo_symbol_function(symbol) && symbol.name() == name;
}

inline bool extract_numeric_argument_at(Clingo::SymbolSpan const &args, int arg_index, int &value) {
    if (arg_index < 0 || static_cast<size_t>(arg_index) >= args.size()) {
        return false;
    }
    if (!is_clingo_symbol_number(args[arg_index])) {
        return false;
    }
    value = args[arg_index].number();
    return true;
}

inline bool extract_numeric_argument_at(Clingo::Symbol const &symbol, int arg_index, int &value) {
    if (!is_clingo_symbol_function(symbol)) {
        return false;
    }

    return extract_numeric_argument_at(symbol.arguments(), arg_index, value);
}

inline bool extract_last_numeric_argument(Clingo::SymbolSpan const &args, int &value) {
    bool found = false;

    for (auto const &arg : args) {
        if (is_clingo_symbol_number(arg)) {
            value = arg.number();
            found = true;
        }
    }

    return found;
}

inline bool extract_last_numeric_argument(Clingo::Symbol const &symbol, int &value) {
    if (!is_clingo_symbol_function(symbol)) {
        return false;
    }

    return extract_last_numeric_argument(symbol.arguments(), value);
}

inline bool extract_numeric_aggregate_value(Clingo::Symbol const &symbol, int arg_index, int &value) {
    if (!is_clingo_symbol_function(symbol)) {
        return false;
    }

    auto const args = symbol.arguments();
    if (arg_index >= 0) {
        return extract_numeric_argument_at(args, arg_index, value);
    }

    return extract_last_numeric_argument(args, value);
}

inline bool extract_numeric_tuple(Clingo::Symbol const &symbol, std::vector<int> &values) {
    if (!is_clingo_symbol_function(symbol)) {
        return false;
    }

    values.clear();

    auto const args = symbol.arguments();
    values.reserve(args.size());

    for (size_t i = 0; i < args.size(); ++i) {
        int value = 0;
        if (!extract_numeric_argument_at(args, static_cast<int>(i), value)) {
            values.clear();
            return false;
        }
        values.push_back(value);
    }

    return !values.empty();
}
