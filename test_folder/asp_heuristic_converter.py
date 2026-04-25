#!/usr/bin/env python3
"""
asp_heuristic_converter.py — Convertitore di euristiche ASP standard → lazy __heuristic/N

Converte le direttive #heuristic native di Clingo nella sintassi __heuristic/N
per il lazy grounding delle euristiche tramite il HeuristicPropagator.

Sintassi nativa supportata:
    #heuristic target(X) : body_lit1(X), ..., not neg_lit(X), S = #agg{Y : pred(...,Y,...)}. [W@P, sign]

Sintassi lazy generata:
    __heuristic(__target(target), body1, ..., __n_neg, __bind(s, __agg(pred, idx)), __weight(W'), __priority(P'), sign).

Uso:
    python asp_heuristic_converter.py input.lp -o output.lp
    python asp_heuristic_converter.py input.lp --mode aux -o output_aux.lp
    python asp_heuristic_converter.py input.lp --mode lazy-aux -o output_aux_lg.lp
    python asp_heuristic_converter.py input.lp --in-place
    python asp_heuristic_converter.py input.lp --dry-run

Limitazioni:
    - Il propagatore C++ fa matching sulla tupla numerica completa del target;
      "self" resta il primo argomento della tupla.
    - I body positivi multipli sono supportati se hanno la stessa tupla del target.
      I body positivi ausiliari con variabili diverse vengono ignorati nel mode lazy diretto.
    - Euristiche senza body positivo non vengono mai attivate nel modo lazy.
    - Gli aggregati nel body sono della forma VAR = #agg{Y : pred(...,Y,...)} con un singolo predicato.
    - I filtri aggregati generati sono semplici uguaglianze su variabili target,
      anche con offset +/- costante (es. U1 = U - 1).
    - Espressioni aritmetiche nel peso/priorità: +, -, * tra variabili e costanti.
    - Non gestisce join tra predicati multi-argomento con variabili distinte.
    - Euristiche con body complessi non convertibili generano un WARNING e vengono
      copiate come commento con la riga originale preservata.
"""

import argparse
import re
import sys
import os
from dataclasses import dataclass, field
from typing import Optional


# =============================================================================
# Strutture dati per la rappresentazione intermedia
# =============================================================================

@dataclass
class AggregateBinding:
    """Rappresenta un binding variabile -> aggregato: VAR = #agg{Y : pred(...,Y,...)}"""
    var_name: str           # Nome variabile locale (es. "S")
    agg_type: str           # Tipo aggregato: sum, count, min, max
    pred_name: str          # Predicato aggregato (es. "c")
    arg_index: Optional[int] = None  # Posizione 0-based della variabile aggregata nel predicato
    filters: list = field(default_factory=list)  # (source_arg_idx, target_arg_idx, offset)


@dataclass
class BodyPredicate:
    """Letterale ordinario del body, positivo o negativo."""
    pred_name: str
    args: list = field(default_factory=list)
    negated: bool = False
    text: str = ""


@dataclass
class HeuristicDirective:
    """Rappresentazione intermedia di una direttiva #heuristic parsata."""
    target_pred: str                                # Predicato target (es. "b")
    target_text: str = ""                           # Target completo (es. "b(X)")
    target_args: list = field(default_factory=list)  # Argomenti del target
    target_var: Optional[str] = None                # Variabile del target (es. "X")
    pos_body: list = field(default_factory=list)     # Body positivi: ["x"]
    neg_body: list = field(default_factory=list)     # Body negativi: ["c"]
    body_predicates: list = field(default_factory=list)  # Letterali ordinari completi
    bindings: list = field(default_factory=list)     # AggregateBinding list
    weight_expr: str = "0"                           # Espressione peso originale
    priority_expr: str = "0"                         # Espressione priorità originale
    sign: str = "true"                               # true/false/sign
    body_str: str = ""                               # Body originale
    original_line: str = ""                          # Riga originale per riferimento


# =============================================================================
# Parser dell'euristica nativa
# =============================================================================

# Regex per riconoscere la struttura di una direttiva #heuristic Clingo:
#   #heuristic target(X) : body. [W@P, sign]
# Nota: il punto separa il body dai modificatori, la parentesi quadra segue.
HEURISTIC_RE = re.compile(
    r'^\s*#heuristic\s+(.+?)\.\s*\[(.+?)\]\s*$',
    re.DOTALL
)

# Regex per parsare il target: pred(Var) o pred(Var1, Var2, ...)
TARGET_RE = re.compile(r'^(\w+)\(([^)]+)\)')

# Regex per aggregati nel body: Var = #agg{Y : pred(Y)}
# Supporta anche forme come: Var = #agg{Y,Z : pred(Y,Z)}
AGGREGATE_RE = re.compile(
    r'(\w+)\s*=\s*#(sum|count|min|max)\s*\{([^}]+)\}'
)

# Regex per i modificatori: W@P, sign  oppure  W@P  oppure  W, sign  oppure  W
MODIFIER_RE = re.compile(
    r'^\s*(.+?)(?:\s*@\s*(.+?))?\s*(?:,\s*(true|false|sign))?\s*$'
)


def _strip_comments(line: str) -> str:
    """Rimuove i commenti ASP (%) da una riga, rispettando le stringhe."""
    in_string = False
    for i, ch in enumerate(line):
        if ch == '"':
            in_string = not in_string
        elif ch == '%' and not in_string:
            return line[:i]
    return line


def _split_top_level(text: str, sep: str = ',') -> list:
    """Divide una stringa su sep, ignorando separatori annidati."""
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
    """
    Trova alias aritmetici semplici del target, usati nei PUP:
        U1 = U - 1, U2 = U + 1
    Restituisce {alias: (target_arg_idx, offset)}.
    """
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
    """Converte un termine del predicato aggregato in filtro target, se possibile."""
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
    """
    Estrae nome predicato e indice posizionale della variabile aggregata.
    Es: "Y : c(Y)" -> ("c", 0)
         "N : p(S,N)" -> ("p", 1)
         "Y,X : cost(Y,X)" -> ("cost", 0)
    Produce anche filtri opzionali per legare gli argomenti del predicato
    aggregato alla tupla target: [(source_arg_idx, target_arg_idx, offset)].
    """
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
    """Verifica se l'espressione è la variabile di dominio del target."""
    return target_var is not None and expr.strip() == target_var


def _convert_arith_expr(
    expr: str,
    target_var: Optional[str],
    binding_vars: dict
) -> str:
    """
    Converte un'espressione aritmetica nella sintassi lazy.

    Mappature:
        X (variabile target)  → self
        S (variabile binding) → s (lowercase)
        42                    → 42
        S + 1                 → __add(s, 1)
        S * 10                → __mul(s, 10)
        S - 1                 → __sub(s, 1)
        X + S                 → __add(self, s)
    """
    expr = expr.strip()

    # Gestione meno unario: -expr → __sub(0, converted_expr)
    # Riconosce pattern come -X, -S, -(expr)
    if expr.startswith('-') and len(expr) > 1:
        rest = expr[1:].strip()
        # Distingui meno unario da numero negativo
        try:
            int(expr)  # Es: -5 è un intero valido → restituisci come costante
            return expr
        except ValueError:
            pass
        # Non è un numero negativo → meno unario
        inner = _convert_arith_expr(rest, target_var, binding_vars)
        return f"__sub(0, {inner})"

    # Prova a riconoscere operatori binari: a OP b
    # Cerca l'operatore di livello più basso (+ o -), poi *
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

    # Operatore binario trovato (priorità: + e - più bassi di *)
    split_pos = last_add_sub if last_add_sub >= 0 else last_mul
    if split_pos > 0:
        left = expr[:split_pos].strip()
        op_char = expr[split_pos]
        right = expr[split_pos + 1:].strip()

        if not left or not right:
            return expr

        op_name = {'+': '__add', '-': '__sub', '*': '__mul'}[op_char]
        left_conv = _convert_arith_expr(left, target_var, binding_vars)
        right_conv = _convert_arith_expr(right, target_var, binding_vars)
        return f"{op_name}({left_conv}, {right_conv})"

    # Rimuovi parentesi esterne
    if expr.startswith('(') and expr.endswith(')'):
        return _convert_arith_expr(expr[1:-1], target_var, binding_vars)

    # Variabile di dominio → self
    if _is_domain_variable(expr, target_var):
        return "self"

    # Variabile di binding → lowercase
    if expr in binding_vars:
        return binding_vars[expr].lower()

    # Costante numerica (incluso negativo)
    try:
        int(expr)
        return expr
    except ValueError:
        pass

    # Fallback: restituisci come stringa (potrebbe essere una variabile sconosciuta)
    return expr


def _parse_body_predicate(lit: str, negated: bool = False) -> Optional[BodyPredicate]:
    """Parsa pred(args...) oppure pred proposizionale."""
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
    """
    Parsa il body dell'euristica, separando:
    - letterali positivi semplici
    - letterali negativi (not pred(X))
    - aggregati (Var = #agg{...})

    Restituisce: (pos_body, neg_body, bindings, body_predicates)
    """
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

    # Prima estraiamo gli aggregati (che contengono virgole interne)
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
        # Rimuovi l'aggregato dal remaining per non parsarlo come letterale
        remaining = remaining.replace(m.group(0), '', 1)

    # Ora parsiamo i letterali rimanenti separati da virgola
    for lit in _split_top_level(remaining):
        lit = lit.strip()
        if not lit:
            continue

        # Letterale negativo: not pred(...) oppure not pred (ground)
        neg_match = re.match(r'not\s+(\w+)(?:\s*\(|$)', lit)
        if neg_match:
            parsed = _parse_body_predicate(lit, negated=True)
            if parsed:
                neg_body.append(parsed)
                body_predicates.append(parsed)
            continue

        # Letterale positivo: pred(...)
        parsed = _parse_body_predicate(lit, negated=False)
        if parsed and parsed.pred_name != 'not':
            pos_body.append(parsed)
            body_predicates.append(parsed)
            continue

        # Potrebbe essere una variabile residua dall'aggregato, skip
        if re.match(r'^[A-Z_]\w*$', lit):
            continue

    return pos_body, neg_body, bindings, body_predicates


def parse_heuristic_line(line: str) -> Optional[HeuristicDirective]:
    """
    Parsa una direttiva #heuristic completa e restituisce la
    rappresentazione intermedia, o None se non parsabile.
    """
    # Estrai la parte principale e i modificatori
    m = HEURISTIC_RE.match(line)
    if not m:
        return None

    main_part = m.group(1).strip()
    modifiers_str = m.group(2).strip()

    # Parsa i modificatori: W@P, sign
    mod_match = MODIFIER_RE.match(modifiers_str)
    if not mod_match:
        return None

    weight_str = mod_match.group(1).strip()
    priority_str = mod_match.group(2).strip() if mod_match.group(2) else "0"
    sign_str = mod_match.group(3) if mod_match.group(3) else "true"

    # Separa target dal body (separati da ':')
    colon_pos = main_part.find(':')
    if colon_pos < 0:
        target_part = main_part
        body_str = ""
    else:
        target_part = main_part[:colon_pos].strip()
        body_str = main_part[colon_pos + 1:].strip()

    # Parsa il target: pred(Var)
    target_match = TARGET_RE.match(target_part)
    if not target_match:
        return None

    target_pred = target_match.group(1)
    target_args = target_match.group(2).strip()
    target_arg_list = [a.strip() for a in _split_top_level(target_args)]
    target_text = f"{target_pred}({', '.join(target_arg_list)})"

    # self è la prima variabile (uppercase) del target; il matching usa tutta la tupla.
    target_var = None
    for arg in target_arg_list:
        if re.match(r'^[A-Z_]\w*$', arg):
            target_var = arg
            break

    # Warning: target multi-argomento — le variabili extra sono ignorate dal propagatore
    var_args = [a for a in target_arg_list if re.match(r'^[A-Z_]\w*$', a)]
    if len(var_args) > 1:
        print(
            f"  ⚠ WARNING: target '{target_pred}({target_args})' ha {len(var_args)} variabili "
            f"({', '.join(var_args)}). Il propagatore C++ ora fa matching sulla tupla completa; "
            f"'self' resta la prima variabile ('{var_args[0]}').",
            file=sys.stderr
        )

    # Parsa il body
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


# =============================================================================
# Generatore della sintassi __heuristic/N
# =============================================================================

def _matches_target_tuple(pred: BodyPredicate, directive: HeuristicDirective) -> bool:
    """Il propagatore lazy MVP fa join sulla stessa tupla numerica del target."""
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


def generate_lazy_heuristic(directive: HeuristicDirective) -> list:
    """
    Genera la riga __heuristic/N dalla rappresentazione intermedia.
    Restituisce una lista di stringhe: [warning_lines..., output_line].
    """
    warnings = []
    lazy_pos_body = [p for p in directive.pos_body if _matches_target_tuple(p, directive)]
    lazy_neg_body = [p for p in directive.neg_body if _matches_target_tuple(p, directive)]

    ignored_pos = [p for p in directive.pos_body if p not in lazy_pos_body]
    if ignored_pos:
        warnings.append(
            f"% WARNING: body positivi non sulla tupla target ignorati nel lazy diretto: "
            f"{_predicate_names(ignored_pos)}.\n"
        )

    # Warning: body positivi multipli — ora il propagatore li tratta come congiunzione
    if len(lazy_pos_body) > 1:
        warnings.append(
            f"% INFO: body positivi multipli ({_predicate_names(lazy_pos_body)}) "
            f"gestiti come congiunzione sulla stessa tupla.\n"
        )
        print(
            f"  INFO: body positivi multipli ({_predicate_names(lazy_pos_body)}) "
            f"gestiti come congiunzione dal propagatore.",
            file=sys.stderr
        )

    # Warning: euristica senza body positivo — non sarà mai attivata in modo lazy
    if not lazy_pos_body:
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

    # Body positivi
    for pred in lazy_pos_body:
        args.append(pred.pred_name)

    # Body negativi
    for pred in lazy_neg_body:
        args.append(f"__n_{pred.pred_name}")

    # Mappatura variabili di binding
    binding_vars = {}
    for b in directive.bindings:
        var_lower = b.var_name.lower()
        binding_vars[b.var_name] = var_lower
        args.append(_format_binding(b, var_lower))

    # Peso
    weight_conv = _convert_arith_expr(
        directive.weight_expr, directive.target_var, binding_vars
    )
    args.append(f"__weight({weight_conv})")

    # Priorità
    priority_conv = _convert_arith_expr(
        directive.priority_expr, directive.target_var, binding_vars
    )
    args.append(f"__priority({priority_conv})")

    # Segno
    args.append(directive.sign)

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
    """Genera la variante #heuristic con predicato ausiliario."""
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
    """Body ausiliario per lazy-aux: solo letterali ordinari, niente aggregati."""
    parts = [p.text for p in directive.body_predicates]
    return ", ".join(parts) if parts else "1 = 1"


def generate_lazy_aux_heuristic(directive: HeuristicDirective, idx: int) -> list:
    """
    Genera una variante dinamica con predicato ausiliario:
        aux(TargetArgs) :- body_ordinario.
        __heuristic(__target(target), aux, __bind(...), ...).
    """
    aux = _aux_name(directive, idx, "lazy")
    target_args = _target_args_text(directive)
    aux_rule = f"{aux}({target_args}) :- {_lazy_aux_body(directive)}."

    aux_directive = HeuristicDirective(
        target_pred=directive.target_pred,
        target_text=directive.target_text,
        target_args=directive.target_args,
        target_var=directive.target_var,
        pos_body=[BodyPredicate(pred_name=aux, args=directive.target_args, text=f"{aux}({target_args})")],
        neg_body=[],
        body_predicates=[],
        bindings=directive.bindings,
        weight_expr=directive.weight_expr,
        priority_expr=directive.priority_expr,
        sign=directive.sign,
        body_str=f"{aux}({target_args})",
        original_line=directive.original_line,
    )
    warnings, lazy_line = generate_lazy_heuristic(aux_directive)
    return warnings, f"{aux_rule}\n{lazy_line}"


# =============================================================================
# Processamento del file
# =============================================================================

def _generate_directive_output(directive: HeuristicDirective, idx: int, mode: str) -> tuple:
    if mode == "lazy":
        return generate_lazy_heuristic(directive)
    if mode == "aux":
        return generate_aux_heuristic(directive, idx)
    if mode == "lazy-aux":
        return generate_lazy_aux_heuristic(directive, idx)
    raise ValueError(f"mode non supportato: {mode}")


def process_file(input_path: str, dry_run: bool = False, mode: str = "lazy") -> tuple:
    """
    Processa un file ASP, convertendo le direttive #heuristic.

    Restituisce: (output_lines, conversions_count, warnings)
    """
    with open(input_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    output_lines = []
    conversions = 0
    warnings = []

    # Gestione multi-riga: accumula le righe di una direttiva #heuristic
    accumulating = False
    accumulated = ""
    accumulated_start = 0

    for i, line in enumerate(lines, 1):
        stripped = _strip_comments(line).strip()

        # Inizio di una direttiva #heuristic
        if not accumulating and stripped.startswith('#heuristic'):
            # Controlla se è una direttiva completa (ha sia . che [...])
            if ']' in stripped:
                # Direttiva su singola riga
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
                # Inizio di direttiva multi-riga
                accumulating = True
                accumulated = stripped
                accumulated_start = i
        elif accumulating:
            accumulated += " " + stripped
            if ']' in stripped:
                # Fine della direttiva multi-riga
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
            # Riga non-euristica: copia verbatim
            output_lines.append(line)

    return output_lines, conversions, warnings


# =============================================================================
# CLI
# =============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="Converte le direttive #heuristic ASP nella sintassi lazy __heuristic/N.",
        epilog="""
Esempi:
  %(prog)s input.lp -o output.lp
  %(prog)s input.lp --in-place
  %(prog)s input.lp --dry-run

Sintassi nativa supportata:
  #heuristic b(X) : x(X), not c(X), S = #sum{Y : c(Y)}. [X@S, true]

Sintassi lazy generata:
  __heuristic(__target(b), x, __n_c, __bind(s, __sum(c, 0)), __weight(self), __priority(s), true).
        """,
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        'input',
        help="File ASP di input contenente direttive #heuristic"
    )
    parser.add_argument(
        '-o', '--output',
        help="File di output (default: stdout)"
    )
    parser.add_argument(
        '--in-place',
        action='store_true',
        help="Modifica il file di input in-place (crea un backup .bak)"
    )
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help="Mostra le conversioni senza scrivere"
    )
    parser.add_argument(
        '--mode',
        choices=['lazy', 'aux', 'lazy-aux'],
        default='lazy',
        help="Tipo di riscrittura: lazy __heuristic, #heuristic con ausiliario, oppure lazy con ausiliario"
    )
    parser.add_argument(
        '--no-comments',
        action='store_true',
        help="Non aggiungere il commento con l'euristica originale"
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

    # Rimuovi i commenti "Originale:" se richiesto
    if args.no_comments:
        output_lines = [l for l in output_lines if not l.startswith("% Originale:")]

    # Output
    if args.dry_run:
        print(f"\n--- Riepilogo ---", file=sys.stderr)
        print(f"Conversioni: {conversions}", file=sys.stderr)
        if warnings:
            print(f"Warning: {len(warnings)}", file=sys.stderr)
            for w in warnings:
                print(f"  ⚠ {w}", file=sys.stderr)
        return

    if args.in_place:
        # Crea backup
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
