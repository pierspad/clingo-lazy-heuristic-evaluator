#!/usr/bin/env python3


import argparse
import re
import sys
import os
from dataclasses import dataclass, field
from typing import Optional

try:
    import clingo.ast as clingo_ast
except ImportError:
    clingo_ast = None


@dataclass
class AggregateBinding:

    var_name: str
    agg_type: str
    pred_name: str
    arg_index: Optional[int] = None
    filters: list = field(default_factory=list)


@dataclass
class BodyPredicate:

    pred_name: str
    args: list = field(default_factory=list)
    negated: bool = False
    text: str = ""


@dataclass
class HeuristicDirective:

    target_pred: str
    target_text: str = ""
    target_args: list = field(default_factory=list)
    target_var: Optional[str] = None
    target_var_positions: dict = field(default_factory=dict)
    pos_body: list = field(default_factory=list)
    neg_body: list = field(default_factory=list)
    body_predicates: list = field(default_factory=list)
    bindings: list = field(default_factory=list)
    bias_expr: str = "0"
    local_priority_expr: str = "0"
    modifier: str = "true"
    body_str: str = ""
    original_line: str = ""


@dataclass
class LazyBodyVar:

    var_name: str
    source_arg_index: int


def _is_domain_variable(expr: str, target_var: Optional[str]) -> bool:

    return target_var is not None and expr.strip() == target_var


def _convert_arith_expr(
    expr: str,
    target_var: Optional[str],
    binding_vars: dict,
    body_vars: Optional[dict] = None,
    target_binding_vars: Optional[dict] = None
) -> str:


    expr = expr.strip()


    if expr.startswith('-') and len(expr) > 1:
        rest = expr[1:].strip()

        try:
            int(expr)
            return expr
        except ValueError:
            pass

        inner = _convert_arith_expr(rest, target_var, binding_vars, body_vars, target_binding_vars)
        return f"__sub(0, {inner})"


    depth = 0
    last_add_sub = -1
    last_mul = -1

    for i, ch in enumerate(expr):
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
        elif depth == 0:
            if ch in ('+', '-') and i > 0:
                last_add_sub = i
            elif ch == '*' and i > 0:
                last_mul = i


    split_pos = last_add_sub if last_add_sub >= 0 else last_mul
    if split_pos > 0:
        left = expr[:split_pos].strip()
        op_char = expr[split_pos]
        right = expr[split_pos + 1:].strip()

        if not left or not right:
            return expr

        op_name = {'+': '__add', '-': '__sub', '*': '__mul'}[op_char]
        left_conv = _convert_arith_expr(left, target_var, binding_vars, body_vars, target_binding_vars)
        right_conv = _convert_arith_expr(right, target_var, binding_vars, body_vars, target_binding_vars)
        return f"{op_name}({left_conv}, {right_conv})"


    if expr.startswith('(') and expr.endswith(')'):
        return _convert_arith_expr(expr[1:-1], target_var, binding_vars, body_vars, target_binding_vars)


    if _is_domain_variable(expr, target_var):
        return "self"

    target_binding_vars = target_binding_vars or {}
    if expr in target_binding_vars:
        return target_binding_vars[expr]


    if expr in binding_vars:
        return binding_vars[expr].lower()


    body_vars = body_vars or {}
    if expr in body_vars:
        return body_vars[expr].var_name.lower()


    try:
        int(expr)
        return expr
    except ValueError:
        pass


    return expr


def _matches_target_tuple(pred: BodyPredicate, directive: HeuristicDirective) -> bool:

    return pred.args == directive.target_args


def _predicate_names(predicates: list) -> str:
    return ', '.join(p.pred_name for p in predicates)


def _format_filter(filter_tuple: tuple) -> str:
    source_idx, target_idx, offset = filter_tuple
    if offset == 0:
        return f"__filter({source_idx}, {target_idx})"
    return f"__filter({source_idx}, {target_idx}, {offset})"


def _format_binding(b: AggregateBinding, var_lower: str) -> str:
    filter_suffix = ''.join(f", {_format_filter(f)}" for f in b.filters)
    if b.arg_index is None:
        return f"__bind({var_lower}, __{b.agg_type}({b.pred_name}{filter_suffix}))"
    return f"__bind({var_lower}, __{b.agg_type}({b.pred_name}, {b.arg_index}{filter_suffix}))"


def _expr_symbol_names(*exprs: str) -> list:
    names = []
    seen = set()
    for expr in exprs:
        for name in re.findall(r'\b[A-Z_]\w*\b', expr):
            if name not in seen:
                seen.add(name)
                names.append(name)
    return names


def _target_arg_bindings_used(directive: HeuristicDirective) -> list:
    used = []
    for name in _expr_symbol_names(directive.bias_expr, directive.local_priority_expr):
        target_idx = directive.target_var_positions.get(name)
        if target_idx is None:
            continue
        if target_idx == 0 and name == directive.target_var:
            continue
        used.append((name, target_idx, name.lower()))
    return used


def _format_positive_body(pred: BodyPredicate, directive: HeuristicDirective) -> tuple:


    warnings = []
    body_vars = {}

    if _matches_target_tuple(pred, directive):
        return pred.pred_name, body_vars, warnings

    target_arg_positions = {
        arg: idx
        for idx, arg in enumerate(directive.target_args)
        if re.match(r'^[A-Z_]\w*$', arg)
    }

    matches = []
    matched_targets = set()
    for source_idx, arg in enumerate(pred.args):
        if arg in target_arg_positions:
            target_idx = target_arg_positions[arg]
            matches.append(f"__match({source_idx}, {target_idx})")
            matched_targets.add(target_idx)
            continue

        if re.match(r'^[A-Z_]\w*$', arg):
            body_vars[arg] = LazyBodyVar(arg, source_idx)

    if len(matched_targets) != len(target_arg_positions):
        warnings.append(
            f"% WARNING: body positivo '{pred.text}' non lega tutta la tupla target; "
            f"conversione lazy saltata.\n"
        )
        return "", body_vars, warnings

    bind_args = [
        f"__bind_arg({var.var_name.lower()}, {var.source_arg_index})"
        for var in body_vars.values()
    ]
    body_args = [pred.pred_name] + matches + bind_args
    return f"__body({', '.join(body_args)})", body_vars, warnings


def generate_lazy_heuristic(directive: HeuristicDirective, semantics: str = "alpha") -> list:


    warnings = []
    lazy_neg_body = [p for p in directive.neg_body if _matches_target_tuple(p, directive)]
    lazy_pos_args = []
    body_vars = {}

    for pred in directive.pos_body:
        body_arg, pred_body_vars, pred_warnings = _format_positive_body(pred, directive)
        warnings.extend(pred_warnings)
        if body_arg:
            lazy_pos_args.append(body_arg)
            for name, var in pred_body_vars.items():
                body_vars[name] = var


    if len(lazy_pos_args) > 1:
        warnings.append(
            f"% INFO: body positivi multipli ({_predicate_names(directive.pos_body)}) "
            f"gestiti come congiunzione sulla stessa tupla.\n"
        )
        print(
            f"  INFO: body positivi multipli ({_predicate_names(directive.pos_body)}) "
            f"gestiti come congiunzione dal propagatore.",
            file=sys.stderr
        )


    if not lazy_pos_args:
        warnings.append(
            f"% WARNING: euristica senza body positivo. "
            f"Non sarà mai attivata nel modo lazy (nessun trigger).\n"
        )
        print(
            f"  ⚠ WARNING: euristica per '{directive.target_pred}' senza body positivo. "
            f"Non sarà mai attivata nel modo lazy.",
            file=sys.stderr
        )

    args = [f"__target({directive.target_pred})"]


    args.extend(lazy_pos_args)


    for pred in lazy_neg_body:
        args.append(f"__n_{pred.pred_name}")


    target_binding_vars = {}
    for var_name, target_idx, var_lower in _target_arg_bindings_used(directive):
        target_binding_vars[var_name] = var_lower
        args.append(f"__bind_target_arg({var_lower}, {target_idx})")


    binding_vars = {}
    for b in directive.bindings:
        var_lower = b.var_name.lower()
        binding_vars[b.var_name] = var_lower
        args.append(_format_binding(b, var_lower))


    bias_conv = _convert_arith_expr(
        directive.bias_expr, directive.target_var, binding_vars, body_vars, target_binding_vars
    )
    args.append(f"__weight({bias_conv})")


    local_priority_conv = _convert_arith_expr(
        directive.local_priority_expr, directive.target_var, binding_vars, body_vars, target_binding_vars
    )
    args.append(f"__priority({local_priority_conv})")


    args.append(f"__modifier({directive.modifier})")

    args.append(f"__semantics({semantics})")

    result_line = f"__heuristic({', '.join(args)})."
    return warnings, result_line


def _aux_name(directive: HeuristicDirective, idx: int, suffix: str = "") -> str:
    clean_suffix = f"_{suffix}" if suffix else ""
    return f"__h_{directive.target_pred}_{idx}{clean_suffix}"


def _target_args_text(directive: HeuristicDirective) -> str:
    return ', '.join(directive.target_args)


def _aux_rule_body_with_weights(directive: HeuristicDirective) -> str:
    parts = []
    if directive.body_str:
        parts.append(directive.body_str)
    parts.append(f"AuxWeight = {directive.bias_expr}")
    parts.append(f"AuxPriority = {directive.local_priority_expr}")
    return ", ".join(parts)


def generate_aux_heuristic(directive: HeuristicDirective, idx: int) -> list:

    aux = _aux_name(directive, idx)
    target_args = _target_args_text(directive)
    aux_args = ", ".join([a for a in directive.target_args] + ["AuxWeight", "AuxPriority"])
    body = _aux_rule_body_with_weights(directive)

    aux_rule = f"{aux}({aux_args}) :- {body}."
    heuristic = (
        f"#heuristic {directive.target_text} : "
        f"{aux}({target_args}, AuxWeight, AuxPriority). "
        f"[AuxWeight@AuxPriority, {directive.modifier}]"
    )
    return [], f"{aux_rule}\n{heuristic}"


def _lazy_aux_body(directive: HeuristicDirective) -> str:

    return directive.body_str if directive.body_str else "1 = 1"


def _expr_variables(*exprs: str) -> list:
    variables = []
    seen = set()
    for expr in exprs:
        for name in re.findall(r'\b[A-Z_]\w*\b', expr):
            if name not in seen:
                seen.add(name)
                variables.append(name)
    return variables


def generate_lazy_aux_heuristic(directive: HeuristicDirective, idx: int) -> list:


    aux = _aux_name(directive, idx, "lazy")
    target_arg_list = list(directive.target_args)
    binding_arg_list = [b.var_name for b in directive.bindings]
    existing_args = set(target_arg_list + binding_arg_list)
    extra_arg_list = [
        name
        for name in _expr_variables(directive.bias_expr, directive.local_priority_expr)
        if name not in existing_args
    ]
    aux_arg_list = target_arg_list + binding_arg_list + extra_arg_list
    aux_args = ", ".join(aux_arg_list)
    aux_rule = f"{aux}({aux_args}) :- {_lazy_aux_body(directive)}."

    aux_directive = HeuristicDirective(
        target_pred=directive.target_pred,
        target_text=directive.target_text,
        target_args=directive.target_args,
        target_var=directive.target_var,
        target_var_positions=directive.target_var_positions,
        pos_body=[BodyPredicate(pred_name=aux, args=aux_arg_list, text=f"{aux}({aux_args})")],
        neg_body=[],
        body_predicates=[],
        bindings=[],
        bias_expr=directive.bias_expr,
        local_priority_expr=directive.local_priority_expr,
        modifier=directive.modifier,
        body_str=f"{aux}({aux_args})",
        original_line=directive.original_line,
    )
    warnings, lazy_line = generate_lazy_heuristic(aux_directive)
    return warnings, f"{aux_rule}\n{lazy_line}"


MODES = {"la", "lc", "aux", "la-aux"}


def _validate_mode(mode: str) -> str:
    if mode not in MODES:
        valid = ", ".join(sorted(MODES))
        raise ValueError(f"mode non supportato: {mode}. Mode validi: {valid}")
    return mode


def _generate_directive_output(directive: HeuristicDirective, idx: int, mode: str) -> tuple:
    mode = _validate_mode(mode)
    if mode == "la":
        return generate_lazy_heuristic(directive)
    if mode == "lc":
        return generate_lazy_heuristic(directive, semantics="clingo")
    if mode == "aux":
        return generate_aux_heuristic(directive, idx)
    if mode == "la-aux":
        return generate_lazy_aux_heuristic(directive, idx)
    raise ValueError(f"mode non supportato: {mode}")


def _ast_function(term):
    if clingo_ast is None or term.ast_type != clingo_ast.ASTType.Function:
        return None
    return term


def _ast_symbolic_function(atom):
    if clingo_ast is None or atom.ast_type != clingo_ast.ASTType.SymbolicAtom:
        return None
    return _ast_function(atom.symbol)


def _ast_variable_name(term) -> Optional[str]:
    if clingo_ast is not None and term.ast_type == clingo_ast.ASTType.Variable:
        return term.name
    return None


def _ast_number(term) -> Optional[int]:
    if clingo_ast is None or term.ast_type != clingo_ast.ASTType.SymbolicTerm:
        return None
    symbol = term.symbol
    if symbol.type.name == "Number":
        return symbol.number
    return None


def _ast_term_filter(term, target_positions: dict, aliases: dict) -> Optional[tuple]:
    var_name = _ast_variable_name(term)
    if var_name in target_positions:
        return target_positions[var_name], 0
    if var_name in aliases:
        return aliases[var_name]

    if clingo_ast is None or term.ast_type != clingo_ast.ASTType.BinaryOperation:
        return None
    if term.operator_type not in (clingo_ast.BinaryOperator.Plus, clingo_ast.BinaryOperator.Minus):
        return None

    left_filter = _ast_term_filter(term.left, target_positions, aliases)
    right_number = _ast_number(term.right)
    if left_filter is None or right_number is None:
        return None

    target_idx, offset = left_filter
    if term.operator_type == clingo_ast.BinaryOperator.Minus:
        right_number = -right_number
    return target_idx, offset + right_number


def _ast_target_aliases(body, target_positions: dict) -> dict:
    aliases = {}
    if clingo_ast is None:
        return aliases

    for lit in body:
        if lit.sign != clingo_ast.Sign.NoSign:
            continue
        if lit.atom.ast_type != clingo_ast.ASTType.Comparison:
            continue

        left_name = _ast_variable_name(lit.atom.term)
        if not left_name:
            continue

        for guard in lit.atom.guards:
            if guard.comparison != clingo_ast.ComparisonOperator.Equal:
                continue
            filter_target = _ast_term_filter(guard.term, target_positions, aliases)
            if filter_target is not None:
                aliases[left_name] = filter_target
    return aliases


def _ast_aggregate_name(function_id: int) -> Optional[str]:
    if clingo_ast is None:
        return None
    mapping = {
        clingo_ast.AggregateFunction.Sum: "sum",
        clingo_ast.AggregateFunction.SumPlus: "sum",
        clingo_ast.AggregateFunction.Count: "count",
        clingo_ast.AggregateFunction.Min: "min",
        clingo_ast.AggregateFunction.Max: "max",
    }
    return mapping.get(function_id)


def _ast_predicate_from_literal(lit, negated: bool) -> Optional[BodyPredicate]:
    fn = _ast_symbolic_function(lit.atom)
    if fn is None:
        return None
    return BodyPredicate(
        pred_name=fn.name,
        args=[str(arg) for arg in fn.arguments],
        negated=negated,
        text=str(lit),
    )


def _ast_binding_from_aggregate(lit, target_positions: dict, aliases: dict) -> Optional[AggregateBinding]:
    if clingo_ast is None or lit.sign != clingo_ast.Sign.NoSign:
        return None
    if lit.atom.ast_type != clingo_ast.ASTType.BodyAggregate:
        return None

    aggregate = lit.atom
    if aggregate.left_guard is None:
        return None
    if aggregate.left_guard.comparison != clingo_ast.ComparisonOperator.Equal:
        return None

    var_name = _ast_variable_name(aggregate.left_guard.term)
    agg_type = _ast_aggregate_name(aggregate.function)
    if var_name is None or agg_type is None or not aggregate.elements:
        return None

    element = aggregate.elements[0]
    if not element.terms:
        return None
    target_term = str(element.terms[0])

    source_fn = None
    for cond_lit in element.condition:
        if cond_lit.sign != clingo_ast.Sign.NoSign:
            continue
        source_fn = _ast_symbolic_function(cond_lit.atom)
        if source_fn is not None:
            break
    if source_fn is None:
        return None

    pred_args = list(source_fn.arguments)
    arg_index = None
    for idx, arg in enumerate(pred_args):
        if str(arg) == target_term:
            arg_index = idx
            break

    filters = []
    for idx, arg in enumerate(pred_args):
        if idx == arg_index or str(arg).strip() == "_":
            continue
        filter_target = _ast_term_filter(arg, target_positions, aliases)
        if filter_target is not None:
            target_idx, offset = filter_target
            filters.append((idx, target_idx, offset))

    return AggregateBinding(var_name, agg_type, source_fn.name, arg_index, filters)


def _directive_from_heuristic_ast(ast_node) -> Optional[HeuristicDirective]:
    if clingo_ast is None or ast_node.ast_type != clingo_ast.ASTType.Heuristic:
        return None

    target_fn = _ast_symbolic_function(ast_node.atom)
    if target_fn is None:
        return None

    target_arg_list = [str(arg) for arg in target_fn.arguments]
    target_text = (
        f"{target_fn.name}({', '.join(target_arg_list)})"
        if target_arg_list else target_fn.name
    )
    target_var = None
    if target_fn.arguments:
        target_var = _ast_variable_name(target_fn.arguments[0])

    target_positions = {
        arg: idx
        for idx, arg in enumerate(target_arg_list)
        if re.match(r'^[A-Z_]\w*$', arg)
    }
    aliases = _ast_target_aliases(ast_node.body, target_positions)

    pos_body = []
    neg_body = []
    body_predicates = []
    bindings = []

    for lit in ast_node.body:
        if lit.atom.ast_type == clingo_ast.ASTType.BodyAggregate:
            binding = _ast_binding_from_aggregate(lit, target_positions, aliases)
            if binding is not None:
                bindings.append(binding)
            continue

        if lit.sign == clingo_ast.Sign.Negation:
            parsed = _ast_predicate_from_literal(lit, negated=True)
            if parsed is not None:
                neg_body.append(parsed)
                body_predicates.append(parsed)
            continue

        if lit.sign == clingo_ast.Sign.NoSign:
            parsed = _ast_predicate_from_literal(lit, negated=False)
            if parsed is not None:
                pos_body.append(parsed)
                body_predicates.append(parsed)

    modifier = str(ast_node.modifier)
    if modifier not in {"level", "sign", "true", "false", "init", "factor"}:
        modifier = "true"

    return HeuristicDirective(
        target_pred=target_fn.name,
        target_text=target_text,
        target_args=target_arg_list,
        target_var=target_var,
        target_var_positions=target_positions,
        pos_body=pos_body,
        neg_body=neg_body,
        body_predicates=body_predicates,
        bindings=bindings,
        bias_expr=str(ast_node.bias),
        local_priority_expr=str(ast_node.priority),
        modifier=modifier,
        body_str=", ".join(str(lit) for lit in ast_node.body),
        original_line=str(ast_node),
    )


def _line_offsets(content: str) -> list:
    offsets = [0]
    for line in content.splitlines(keepends=True):
        offsets.append(offsets[-1] + len(line))
    return offsets


def _offset_from_position(offsets: list, position) -> int:
    return offsets[position.line - 1] + position.column - 1


def _process_file_ast(input_path: str, dry_run: bool = False, mode: str = "la") -> tuple:
    if clingo_ast is None:
        raise RuntimeError(
            "clingo.ast non disponibile: installa il pacchetto Python 'clingo' "
            "per usare il converter AST-only."
        )

    with open(input_path, 'r', encoding='utf-8') as f:
        content = f.read()

    offsets = _line_offsets(content)
    replacements = []
    warnings = []
    conversions = 0
    normalized_input = os.path.normpath(input_path)

    def on_ast(ast_node):
        nonlocal conversions
        if ast_node.ast_type != clingo_ast.ASTType.Heuristic:
            return
        if os.path.normpath(ast_node.location.begin.filename) != normalized_input:
            return

        start = _offset_from_position(offsets, ast_node.location.begin)
        end = _offset_from_position(offsets, ast_node.location.end)
        original_text = content[start:end]
        original_one_line = " ".join(original_text.split())

        directive = _directive_from_heuristic_ast(ast_node)
        if directive is None:
            raise ValueError(
                f"Righe {ast_node.location.begin.line}-{ast_node.location.end.line}: "
                "direttiva #heuristic valida per Clingo ma non supportata dal converter AST"
            )

        directive.original_line = original_one_line
        warn_lines, converted = _generate_directive_output(directive, conversions + 1, mode)
        warnings.extend(warn_lines)
        replacement = f"% Originale: {directive.original_line}\n"
        replacement += "".join(warn_lines)
        replacement += f"{converted}\n"
        conversions += 1
        if dry_run:
            print(
                f"  Righe {ast_node.location.begin.line}-{ast_node.location.end.line}: "
                f"{directive.original_line}",
                file=sys.stderr
            )
            print(f"        → {converted}", file=sys.stderr)

        replacements.append((start, end, replacement))

    try:
        clingo_ast.parse_files([input_path], on_ast)
    except Exception as exc:
        raise RuntimeError(f"parsing AST fallito: {exc}") from exc

    if not replacements:
        return content.splitlines(keepends=True), conversions, warnings

    output = []
    cursor = 0
    for start, end, replacement in sorted(replacements, key=lambda item: item[0]):
        output.append(content[cursor:start])
        output.append(replacement)
        cursor = end
    output.append(content[cursor:])

    return "".join(output).splitlines(keepends=True), conversions, warnings


def process_file(input_path: str, dry_run: bool = False, mode: str = "la") -> tuple:
    return _process_file_ast(input_path, dry_run=dry_run, mode=mode)


def _color(text: str, code: str) -> str:

    if not sys.stdout.isatty() or os.environ.get("NO_COLOR") or os.environ.get("TERM") == "dumb":
        return text
    return f"\033[{code}m{text}\033[0m"


def main():
    heading = lambda text: _color(text, "1;36")
    cmd = lambda text: _color(text, "1;32")
    opt = lambda text: _color(text, "1;33")
    value = lambda text: _color(text, "35")

    parser = argparse.ArgumentParser(
        prog="asp_heuristic_converter.py",
        description="Convert ASP #heuristic directives to the encodings used in this project.",
        epilog=f"""
{heading("Commands")}
  {cmd("%(prog)s INPUT.lp")}
      Print the converted ASP program to stdout.

  {cmd("%(prog)s INPUT.lp -o OUTPUT.lp")}
      Write the converted ASP program to OUTPUT.lp.

  {cmd("%(prog)s INPUT.lp --in-place")}
      Replace INPUT.lp and create INPUT.lp.bak.

  {cmd("%(prog)s INPUT.lp --dry-run")}
      Show the conversions that would be performed, without writing files.

{heading("Rewrite modes")}
  {value("la")}            lazy grounding with Alpha body/aggregate semantics; emits clingo-like __heuristic/N facts.
  {value("lc")}            lazy grounding with Clingo body/aggregate semantics; emits clingo-like __heuristic/N facts.
  {value("aux")}           ground and solve with an auxiliary predicate; emits BSP_gc_aux-style native #heuristic.
  {value("la-aux")}        lazy grounding with Alpha body/aggregate semantics through an auxiliary predicate.

{heading("Options")}
  {opt("-o, --output PATH")}
      Output file. Without this option, output goes to stdout.

  {opt("--mode MODE")}
      Select the rewrite mode: la, lc, aux, or la-aux.

  {opt("--in-place")}
      Edit the input file directly. Cannot be combined with -o/--output.

  {opt("--dry-run")}
      Preview conversions and warnings only.

  {opt("--no-comments")}
      Omit the comment that records the original #heuristic directive.

{heading("Examples")}
  {cmd("%(prog)s test_folder/encodings/BSP/BSP_gc.lp --mode la -o test_folder/encodings/BSP/BSP_la.lp")}
      Convert to lazy grounding with Alpha body/aggregate semantics and local @priority.

  {cmd("%(prog)s test_folder/encodings/BSP/BSP_gc.lp --mode la-aux -o test_folder/encodings/BSP/BSP_la_aux.lp")}
      Convert through an auxiliary lazy body predicate.

  {cmd("%(prog)s test_folder/encodings/BSP/BSP_gc.lp --mode lc -o test_folder/encodings/BSP/BSP_lc.lp")}
      Convert to lazy syntax with Clingo body/aggregate semantics and local @priority.

  {cmd("%(prog)s test_folder/encodings/BSP/BSP_gc.lp --dry-run")}
      Check what would change before writing anything.
        """.strip(),
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        'input',
        help="Input ASP file containing Clingo #heuristic directives."
    )
    parser.add_argument(
        '-o', '--output',
        metavar="PATH",
        help="Write the converted ASP program to PATH. Default: print to stdout."
    )
    parser.add_argument(
        '--in-place',
        action='store_true',
        help="Rewrite the input file in place and create a '<input>.bak' backup."
    )
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help="Preview conversions and warnings without writing files."
    )
    parser.add_argument(
        '--mode',
        choices=sorted(MODES),
        default='la',
        help=(
            "Rewrite mode: la, lc, aux, or la-aux. "
            "Default: la."
        )
    )
    parser.add_argument(
        '--no-comments',
        action='store_true',
        help="Do not include the '%% Originale: ...' comment before converted directives."
    )

    args = parser.parse_args()
    if not os.path.isfile(args.input):
        print(f"Errore: file '{args.input}' non trovato.", file=sys.stderr)
        sys.exit(1)

    if args.in_place and args.output:
        print("Errore: --in-place e -o sono mutualmente esclusivi.", file=sys.stderr)
        sys.exit(1)

    print(f"Processando: {args.input} (mode={args.mode})", file=sys.stderr)

    try:
        output_lines, conversions, warnings = process_file(args.input, dry_run=args.dry_run, mode=args.mode)
    except (RuntimeError, ValueError) as exc:
        print(f"Errore: {exc}", file=sys.stderr)
        sys.exit(1)


    if args.no_comments:
        output_lines = [l for l in output_lines if not l.startswith("% Originale:")]


    if args.dry_run:
        print(f"\n--- Riepilogo ---", file=sys.stderr)
        print(f"Conversioni: {conversions}", file=sys.stderr)
        if warnings:
            print(f"Warning: {len(warnings)}", file=sys.stderr)
            for w in warnings:
                print(f"  ⚠ {w}", file=sys.stderr)
        return

    if args.in_place:

        backup_path = args.input + '.bak'
        with open(args.input, 'r', encoding='utf-8') as f:
            backup_content = f.read()
        with open(backup_path, 'w', encoding='utf-8') as f:
            f.write(backup_content)
        print(f"Backup creato: {backup_path}", file=sys.stderr)

        with open(args.input, 'w', encoding='utf-8') as f:
            f.writelines(output_lines)
        print(f"File modificato in-place: {args.input}", file=sys.stderr)
    elif args.output:
        with open(args.output, 'w', encoding='utf-8') as f:
            f.writelines(output_lines)
        print(f"Output scritto: {args.output}", file=sys.stderr)
    else:
        sys.stdout.writelines(output_lines)

    print(f"Conversioni effettuate: {conversions}", file=sys.stderr)
    if warnings:
        print(f"Warning: {len(warnings)}", file=sys.stderr)
        for w in warnings:
            print(f"  ⚠ {w}", file=sys.stderr)


if __name__ == '__main__':
    main()
