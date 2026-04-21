#!/usr/bin/env python3
"""
asp_heuristic_converter.py — Convertitore di euristiche ASP standard → lazy __heuristic/N

Converte le direttive #heuristic native di Clingo nella sintassi __heuristic/N
per il lazy grounding delle euristiche tramite il HeuristicPropagator.

Sintassi nativa supportata:
    #heuristic target(X) : body_lit1(X), ..., not neg_lit(X), S = #agg{Y : pred(Y)}. [W@P, sign]

Sintassi lazy generata:
    __heuristic(target, body1, ..., __n_neg, __bind(s, __agg(pred)), __weight(W'), __priority(P'), sign).

Uso:
    python asp_heuristic_converter.py input.lp -o output.lp
    python asp_heuristic_converter.py input.lp --in-place
    python asp_heuristic_converter.py input.lp --dry-run

Limitazioni:
    - Supporta un singolo predicato di dominio (la variabile X del target).
    - Gli aggregati nel body sono della forma VAR = #agg{Y : pred(Y)} con un singolo predicato.
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
    """Rappresenta un binding variabile → aggregato: VAR = #agg{Y : pred(Y)}"""
    var_name: str           # Nome variabile locale (es. "S")
    agg_type: str           # Tipo aggregato: sum, count, min, max
    pred_name: str          # Predicato aggregato (es. "c")


@dataclass
class HeuristicDirective:
    """Rappresentazione intermedia di una direttiva #heuristic parsata."""
    target_pred: str                                # Predicato target (es. "b")
    target_var: Optional[str] = None                # Variabile del target (es. "X")
    pos_body: list = field(default_factory=list)     # Body positivi: ["x"]
    neg_body: list = field(default_factory=list)     # Body negativi: ["c"]
    bindings: list = field(default_factory=list)     # AggregateBinding list
    weight_expr: str = "0"                           # Espressione peso originale
    priority_expr: str = "0"                         # Espressione priorità originale
    sign: str = "true"                               # true/false/sign
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


def _extract_pred_from_aggregate_body(agg_body: str) -> Optional[str]:
    """
    Estrae il nome del predicato dal body dell'aggregato.
    Es: "Y : c(Y)" → "c"
         "Y,X : cost(Y,X)" → "cost"
    """
    parts = agg_body.split(':')
    if len(parts) < 2:
        return None
    pred_part = parts[1].strip()
    m = re.match(r'(\w+)\s*\(', pred_part)
    if m:
        return m.group(1)
    return None


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


def _parse_body_literals(body_str: str) -> tuple:
    """
    Parsa il body dell'euristica, separando:
    - letterali positivi semplici
    - letterali negativi (not pred(X))
    - aggregati (Var = #agg{...})

    Restituisce: (pos_body, neg_body, bindings)
    """
    pos_body = []
    neg_body = []
    bindings = []

    # Prima estraiamo gli aggregati (che contengono virgole interne)
    remaining = body_str
    for m in AGGREGATE_RE.finditer(body_str):
        var_name = m.group(1)
        agg_type = m.group(2)
        agg_body = m.group(3)
        pred = _extract_pred_from_aggregate_body(agg_body)
        if pred:
            bindings.append(AggregateBinding(var_name, agg_type, pred))
        # Rimuovi l'aggregato dal remaining per non parsarlo come letterale
        remaining = remaining.replace(m.group(0), '', 1)

    # Ora parsiamo i letterali rimanenti separati da virgola
    for lit in remaining.split(','):
        lit = lit.strip()
        if not lit:
            continue

        # Letterale negativo: not pred(...)
        neg_match = re.match(r'not\s+(\w+)\s*\(', lit)
        if neg_match:
            neg_body.append(neg_match.group(1))
            continue

        # Letterale positivo: pred(...)
        pos_match = re.match(r'(\w+)\s*\(', lit)
        if pos_match:
            pred_name = pos_match.group(1)
            if pred_name != 'not':
                pos_body.append(pred_name)
            continue

        # Potrebbe essere una variabile residua dall'aggregato, skip
        if re.match(r'^[A-Z_]\w*$', lit):
            continue

    return pos_body, neg_body, bindings


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

    # La prima variabile (uppercase) è la variabile di dominio
    target_var = None
    for arg in target_args.split(','):
        arg = arg.strip()
        if re.match(r'^[A-Z_]\w*$', arg):
            target_var = arg
            break

    # Parsa il body
    pos_body, neg_body, bindings = _parse_body_literals(body_str)

    directive = HeuristicDirective(
        target_pred=target_pred,
        target_var=target_var,
        pos_body=pos_body,
        neg_body=neg_body,
        bindings=bindings,
        weight_expr=weight_str,
        priority_expr=priority_str,
        sign=sign_str,
        original_line=line.strip()
    )

    return directive


# =============================================================================
# Generatore della sintassi __heuristic/N
# =============================================================================

def generate_lazy_heuristic(directive: HeuristicDirective) -> str:
    """
    Genera la riga __heuristic/N dalla rappresentazione intermedia.
    """
    args = [directive.target_pred]

    # Body positivi
    for pred in directive.pos_body:
        args.append(pred)

    # Body negativi
    for pred in directive.neg_body:
        args.append(f"__n_{pred}")

    # Mappatura variabili di binding
    binding_vars = {}
    for b in directive.bindings:
        var_lower = b.var_name.lower()
        binding_vars[b.var_name] = var_lower
        args.append(f"__bind({var_lower}, __{b.agg_type}({b.pred_name}))")

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

    return f"__heuristic({', '.join(args)})."


# =============================================================================
# Processamento del file
# =============================================================================

def process_file(input_path: str, dry_run: bool = False) -> tuple:
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
                    lazy_line = generate_lazy_heuristic(directive)
                    output_lines.append(f"% Originale: {directive.original_line}\n")
                    output_lines.append(f"{lazy_line}\n")
                    conversions += 1
                    if dry_run:
                        print(f"  Riga {i}: {directive.original_line}")
                        print(f"        → {lazy_line}")
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
                    lazy_line = generate_lazy_heuristic(directive)
                    output_lines.append(f"% Originale: {directive.original_line}\n")
                    output_lines.append(f"{lazy_line}\n")
                    conversions += 1
                    if dry_run:
                        print(f"  Righe {accumulated_start}-{i}: {directive.original_line}")
                        print(f"        → {lazy_line}")
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
  __heuristic(b, x, __n_c, __bind(s, __sum(c)), __weight(self), __priority(s), true).
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

    print(f"Processando: {args.input}", file=sys.stderr)

    output_lines, conversions, warnings = process_file(args.input, dry_run=args.dry_run)

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
