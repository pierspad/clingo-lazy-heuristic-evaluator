#!/usr/bin/env python3


import argparse
import re
import sys
import os
from dataclasses import dataclass, field
from typing import Optional


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
    pos_body: list = field(default_factory=list)
    neg_body: list = field(default_factory=list)
    body_predicates: list = field(default_factory=list)
    bindings: list = field(default_factory=list)
    weight_expr: str = "0"
    priority_expr: str = "0"
    sign: str = "true"
    body_str: str = ""
    original_line: str = ""


@dataclass
class LazyBodyVar:

    var_name: str
    source_arg_index: int


HEURISTIC_RE = re.compile(
    r'^\s*#heuristic\s+(.+?)\.\s*\[(.+?)\]\s*$',
    re.DOTALL
)


TARGET_RE = re.compile(r'^(\w+)\(([^)]+)\)')


AGGREGATE_RE = re.compile(
    r'(\w+)\s*=\s*#(sum|count|min|max)\s*\{([^}]+)\}'
)


MODIFIER_RE = re.compile(
    r'^\s*(.+?)(?:\s*@\s*(.+?))?\s*(?:,\s*(true|false|sign))?\s*$'
)


def _strip_comments(line: str) -> str:

    in_string = False
    for i, ch in enumerate(line):
        if ch == '"':
            in_string = not in_string
        elif ch == '%' and not in_string:
            return line[:i]
    return line


def _split_top_level(text: str, sep: str = ',') -> list:

    parts = []
    start = 0
    depth = 0
    for i, ch in enumerate(text):
        if ch in '({[':
            depth += 1
        elif ch in ')}]':
            depth = max(0, depth - 1)
        elif ch == sep and depth == 0:
            parts.append(text[start:i].strip())
            start = i + 1
    parts.append(text[start:].strip())
    return parts


def _parse_target_aliases(body_str: str, target_positions: dict) -> dict:


    aliases = {}
    for part in _split_top_level(body_str):
        m = re.match(r'^\s*(\w+)\s*=\s*(\w+)\s*([+-])\s*(\d+)\s*$', part)
        if m and m.group(2) in target_positions:
            sign = 1 if m.group(3) == '+' else -1
            aliases[m.group(1)] = (target_positions[m.group(2)], sign * int(m.group(4)))
            continue

        m = re.match(r'^\s*(\w+)\s*=\s*(\w+)\s*$', part)
        if m and m.group(2) in target_positions:
            aliases[m.group(1)] = (target_positions[m.group(2)], 0)

    return aliases


def _term_to_target_filter(term: str, target_positions: dict, aliases: dict) -> Optional[tuple]:

    term = term.strip()
    if term in target_positions:
        return target_positions[term], 0
    if term in aliases:
        return aliases[term]
    return None


def _extract_pred_and_index_from_aggregate_body(
    agg_body: str,
    target_positions: Optional[dict] = None,
    aliases: Optional[dict] = None,
) -> tuple:


    target_positions = target_positions or {}
    aliases = aliases or {}

    parts = agg_body.split(':')
    if len(parts) < 2:
        return None, None, []

    tuple_terms = _split_top_level(parts[0].strip())
    target_term = tuple_terms[0] if tuple_terms else ""

    pred_part = ':'.join(parts[1:]).strip()
    m = re.match(r'(\w+)\s*\((.*)\)\s*$', pred_part)
    if not m:
        return None, None, []

    pred_name = m.group(1)
    pred_args = _split_top_level(m.group(2))
    arg_index = None
    for idx, arg in enumerate(pred_args):
        if arg == target_term:
            arg_index = idx
            break

    filters = []
    for idx, arg in enumerate(pred_args):
        if idx == arg_index:
            continue
        if arg.strip() == "_":
            continue

        filter_target = _term_to_target_filter(arg, target_positions, aliases)
        if filter_target is None:
            continue

        target_idx, offset = filter_target
        filters.append((idx, target_idx, offset))

    return pred_name, arg_index, filters


def _is_domain_variable(expr: str, target_var: Optional[str]) -> bool:

    return target_var is not None and expr.strip() == target_var


def _convert_arith_expr(
    expr: str,
    target_var: Optional[str],
    binding_vars: dict,
    body_vars: Optional[dict] = None
) -> str:


    expr = expr.strip()


    if expr.startswith('-') and len(expr) > 1:
        rest = expr[1:].strip()

        try:
            int(expr)
            return expr
        except ValueError:
            pass

        inner = _convert_arith_expr(rest, target_var, binding_vars)
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
        left_conv = _convert_arith_expr(left, target_var, binding_vars, body_vars)
        right_conv = _convert_arith_expr(right, target_var, binding_vars, body_vars)
        return f"{op_name}({left_conv}, {right_conv})"


    if expr.startswith('(') and expr.endswith(')'):
        return _convert_arith_expr(expr[1:-1], target_var, binding_vars, body_vars)


    if _is_domain_variable(expr, target_var):
        return "self"


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


def _parse_body_predicate(lit: str, negated: bool = False) -> Optional[BodyPredicate]:

    text = lit.strip()
    if negated:
        text = re.sub(r'^\s*not\s+', '', text).strip()

    m = re.match(r'^(\w+)\s*\((.*)\)\s*$', text)
    if m:
        pred_name = m.group(1)
        args = _split_top_level(m.group(2))
        return BodyPredicate(pred_name=pred_name, args=args, negated=negated, text=lit.strip())

    m = re.match(r'^([a-z_]\w*)\s*$', text)
    if m:
        return BodyPredicate(pred_name=m.group(1), args=[], negated=negated, text=lit.strip())

    return None


def _parse_body_literals(body_str: str, target_args: Optional[list] = None) -> tuple:


    target_args = target_args or []
    target_positions = {
        arg: idx
        for idx, arg in enumerate(target_args)
        if re.match(r'^[A-Z_]\w*$', arg)
    }
    aliases = _parse_target_aliases(body_str, target_positions)

    pos_body = []
    neg_body = []
    body_predicates = []
    bindings = []


    remaining = body_str
    for m in AGGREGATE_RE.finditer(body_str):
        var_name = m.group(1)
        agg_type = m.group(2)
        agg_body = m.group(3)
        pred, arg_index, filters = _extract_pred_and_index_from_aggregate_body(
            agg_body,
            target_positions=target_positions,
            aliases=aliases,
        )
        if pred:
            bindings.append(AggregateBinding(var_name, agg_type, pred, arg_index, filters))

        remaining = remaining.replace(m.group(0), '', 1)


    for lit in _split_top_level(remaining):
        lit = lit.strip()
        if not lit:
            continue


        neg_match = re.match(r'not\s+(\w+)(?:\s*\(|$)', lit)
        if neg_match:
            parsed = _parse_body_predicate(lit, negated=True)
            if parsed:
                neg_body.append(parsed)
                body_predicates.append(parsed)
            continue


        parsed = _parse_body_predicate(lit, negated=False)
        if parsed and parsed.pred_name != 'not':
            pos_body.append(parsed)
            body_predicates.append(parsed)
            continue


        if re.match(r'^[A-Z_]\w*$', lit):
            continue

    return pos_body, neg_body, bindings, body_predicates


def parse_heuristic_line(line: str) -> Optional[HeuristicDirective]:


    m = HEURISTIC_RE.match(line)
    if not m:
        return None

    main_part = m.group(1).strip()
    modifiers_str = m.group(2).strip()


    mod_match = MODIFIER_RE.match(modifiers_str)
    if not mod_match:
        return None

    weight_str = mod_match.group(1).strip()
    priority_str = mod_match.group(2).strip() if mod_match.group(2) else "0"
    sign_str = mod_match.group(3) if mod_match.group(3) else "true"


    colon_pos = main_part.find(':')
    if colon_pos < 0:
        target_part = main_part
        body_str = ""
    else:
        target_part = main_part[:colon_pos].strip()
        body_str = main_part[colon_pos + 1:].strip()


    target_match = TARGET_RE.match(target_part)
    if not target_match:
        return None

    target_pred = target_match.group(1)
    target_args = target_match.group(2).strip()
    target_arg_list = [a.strip() for a in _split_top_level(target_args)]
    target_text = f"{target_pred}({', '.join(target_arg_list)})"


    target_var = None
    for arg in target_arg_list:
        if re.match(r'^[A-Z_]\w*$', arg):
            target_var = arg
            break


    var_args = [a for a in target_arg_list if re.match(r'^[A-Z_]\w*$', a)]
    if len(var_args) > 1:
        print(
            f"  ⚠ WARNING: target '{target_pred}({target_args})' ha {len(var_args)} variabili "
            f"({', '.join(var_args)}). Il propagatore C++ ora fa matching sulla tupla completa; "
            f"'self' resta la prima variabile ('{var_args[0]}').",
            file=sys.stderr
        )


    pos_body, neg_body, bindings, body_predicates = _parse_body_literals(body_str, target_arg_list)

    directive = HeuristicDirective(
        target_pred=target_pred,
        target_text=target_text,
        target_args=target_arg_list,
        target_var=target_var,
        pos_body=pos_body,
        neg_body=neg_body,
        body_predicates=body_predicates,
        bindings=bindings,
        weight_expr=weight_str,
        priority_expr=priority_str,
        sign=sign_str,
        body_str=body_str,
        original_line=line.strip()
    )

    return directive


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


    binding_vars = {}
    for b in directive.bindings:
        var_lower = b.var_name.lower()
        binding_vars[b.var_name] = var_lower
        args.append(_format_binding(b, var_lower))


    weight_conv = _convert_arith_expr(
        directive.weight_expr, directive.target_var, binding_vars, body_vars
    )
    args.append(f"__weight({weight_conv})")


    priority_conv = _convert_arith_expr(
        directive.priority_expr, directive.target_var, binding_vars, body_vars
    )
    args.append(f"__priority({priority_conv})")


    args.append(directive.sign)

    if semantics == "clingo":
        args.append("__semantics(clingo)")

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
    parts.append(f"AuxWeight = {directive.weight_expr}")
    parts.append(f"AuxPriority = {directive.priority_expr}")
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
        f"[AuxWeight@AuxPriority, {directive.sign}]"
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
        for name in _expr_variables(directive.weight_expr, directive.priority_expr)
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
        pos_body=[BodyPredicate(pred_name=aux, args=aux_arg_list, text=f"{aux}({aux_args})")],
        neg_body=[],
        body_predicates=[],
        bindings=[],
        weight_expr=directive.weight_expr,
        priority_expr=directive.priority_expr,
        sign=directive.sign,
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


def process_file(input_path: str, dry_run: bool = False, mode: str = "la") -> tuple:


    with open(input_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    output_lines = []
    conversions = 0
    warnings = []


    accumulating = False
    accumulated = ""
    accumulated_start = 0

    for i, line in enumerate(lines, 1):
        stripped = _strip_comments(line).strip()


        if not accumulating and stripped.startswith('#heuristic'):

            if ']' in stripped:

                directive = parse_heuristic_line(stripped)
                if directive:
                    warn_lines, converted = _generate_directive_output(directive, conversions + 1, mode)
                    output_lines.append(f"% Originale: {directive.original_line}\n")
                    output_lines.extend(warn_lines)
                    output_lines.append(f"{converted}\n")
                    conversions += 1
                    if dry_run:
                        print(f"  Riga {i}: {directive.original_line}")
                        print(f"        → {converted}")
                else:
                    warnings.append(
                        f"Riga {i}: impossibile parsare '{stripped}', preservata come commento"
                    )
                    output_lines.append(f"% WARNING: euristica non convertibile\n")
                    output_lines.append(f"% {stripped}\n")
                    output_lines.append(line)
            else:

                accumulating = True
                accumulated = stripped
                accumulated_start = i
        elif accumulating:
            accumulated += " " + stripped
            if ']' in stripped:

                accumulating = False
                directive = parse_heuristic_line(accumulated)
                if directive:
                    warn_lines, converted = _generate_directive_output(directive, conversions + 1, mode)
                    output_lines.append(f"% Originale: {directive.original_line}\n")
                    output_lines.extend(warn_lines)
                    output_lines.append(f"{converted}\n")
                    conversions += 1
                    if dry_run:
                        print(f"  Righe {accumulated_start}-{i}: {directive.original_line}")
                        print(f"        → {converted}")
                else:
                    warnings.append(
                        f"Righe {accumulated_start}-{i}: impossibile parsare, preservata"
                    )
                    output_lines.append(f"% WARNING: euristica non convertibile\n")
                    output_lines.append(f"% {accumulated}\n")
        else:

            output_lines.append(line)

    return output_lines, conversions, warnings


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
  {value("la")}            lazy grounding with Alpha semantics; emits BSP_la-style __heuristic/N facts.
  {value("lc")}            lazy grounding with Clingo semantics; emits BSP_lc-style __heuristic/N facts.
  {value("aux")}           ground and solve with an auxiliary predicate; emits BSP_gc_aux-style native #heuristic.
  {value("la-aux")}        lazy grounding with Alpha semantics through an auxiliary predicate.

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
  {cmd("%(prog)s BSP/BSP_gc.lp --mode la -o BSP/BSP_la.lp")}
      Convert to lazy grounding with Alpha semantics.

  {cmd("%(prog)s BSP/BSP_gc.lp --mode la-aux -o BSP/BSP_la_aux.lp")}
      Convert through an auxiliary lazy body predicate.

  {cmd("%(prog)s BSP/BSP_gc.lp --mode lc -o BSP/BSP_lc.lp")}
      Convert to lazy syntax with Clingo semantics for negative literals.

  {cmd("%(prog)s BSP/BSP_gc.lp --dry-run")}
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

    output_lines, conversions, warnings = process_file(args.input, dry_run=args.dry_run, mode=args.mode)


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
