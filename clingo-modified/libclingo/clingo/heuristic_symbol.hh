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

inline bool extract_numeric_arguments(Clingo::Symbol const &symbol, std::vector<int> &values) {
    if (!is_clingo_symbol_function(symbol)) {
        return false;
    }

    values.clear();
    for (auto const &arg : symbol.arguments()) {
        if (!is_clingo_symbol_number(arg)) {
            return false;
        }
        values.push_back(arg.number());
    }
    return !values.empty();
}

inline bool extract_numeric_argument(Clingo::Symbol const &symbol, int arg_index, int &value) {
    if (!is_clingo_symbol_function(symbol)) {
        return false;
    }

    auto const args = symbol.arguments();
    if (args.empty()) {
        return false;
    }

    if (arg_index >= 0) {
        if (static_cast<size_t>(arg_index) >= args.size()) {
            return false;
        }
        if (!is_clingo_symbol_number(args[arg_index])) {
            return false;
        }
        value = args[arg_index].number();
        return true;
    }

    bool found = false;
    for (auto const &arg : args) {
        if (is_clingo_symbol_number(arg)) {
            value = arg.number();
            found = true;
        }
    }
    return found;
}

inline bool extract_numeric_argument_from_args(Clingo::SymbolSpan const &args, int arg_index, int &value) {
    if (arg_index < 0 || static_cast<size_t>(arg_index) >= args.size()) {
        return false;
    }
    if (!is_clingo_symbol_number(args[arg_index])) {
        return false;
    }
    value = args[arg_index].number();
    return true;
}
