#!/usr/bin/env python3
"""Disable one refusal guard at a time and report the ones no test notices.

WHY THIS EXISTS (issue #1223). Eight rounds of careful human review of the
production promotion gate found eight real defects. A single mechanical sweep of
the same code found forty-one more in an afternoon: guards that could be turned
off with the whole offline suite still green. A guard nothing can falsify is
either untested or dead, and both are worth knowing -- but only a machine finds
them reliably, because the failure mode is a check that silently passes.

A GUARD, here, is an `if` statement that raises directly in its own body. That is
how every refusal in the promotion-evidence chain is written. The mutation is to
replace the `if` test with `False`, so the raise becomes unreachable and nothing
else about the file moves.

THE BASELINE IS ASSERTED BEFORE ANY MUTATION, AND THAT IS NOT CEREMONY. An early
hand-run sweep timed out and left a file mutated; the next two sweeps inherited
the corruption and reported confident nonsense against a baseline that was
already red. This tool refuses to start unless the suite is green, restores the
file from an in-memory copy of the original bytes in a `finally`, and re-asserts
the file is byte-identical when it finishes. A sweep that cannot prove it put the
tree back reports nothing at all.
"""
from __future__ import annotations
import argparse, ast, hashlib, json, subprocess, sys, time
from pathlib import Path


def line_offsets(text: str) -> list[int]:
    offsets, total = [0], 0
    for line in text.splitlines(keepends=True):
        total += len(line)
        offsets.append(total)
    return offsets


def guards(path: Path):
    """Every `if`/`elif` whose OWN body raises, innermost first.

    `orelse` of an `if` is where `elif` lives, and an `elif` is a guard in its own
    right, so the walk descends into it. A raise nested inside a further `if` or a
    loop belongs to THAT guard, not this one, which is why only the direct body is
    inspected -- crediting an outer `if` with an inner guard's raise would report a
    survivor whose real guard was never disabled.
    """
    text = path.read_text(encoding='utf-8')
    offsets = line_offsets(text)
    found = []
    for node in ast.walk(ast.parse(text)):
        if not isinstance(node, ast.If):
            continue
        if not any(isinstance(stmt, ast.Raise) for stmt in node.body):
            continue
        start = offsets[node.test.lineno - 1] + node.test.col_offset
        end = offsets[node.test.end_lineno - 1] + node.test.end_col_offset
        found.append({'line': node.test.lineno, 'test': text[start:end], 'start': start, 'end': end})
    found.sort(key=lambda row: row['start'])
    return text, found


def run_suite(command: list[str], repo: Path) -> tuple[bool, str]:
    proc = subprocess.run(command, cwd=repo, capture_output=True, text=True)
    return proc.returncode == 0, (proc.stdout + proc.stderr)[-2000:]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--file', required=True, action='append', dest='files')
    parser.add_argument('--command', required=True, help='shell-free test command, space separated')
    parser.add_argument('--out', required=True)
    parser.add_argument('--limit', type=int, default=0, help='stop after N mutations (for a smoke run)')
    args = parser.parse_args()

    repo = Path(__file__).resolve().parent.parent
    command = args.command.split()

    green, tail = run_suite(command, repo)
    if not green:
        print('REFUSED: the baseline is not green, so no survivor found by this sweep would mean anything.', file=sys.stderr)
        print(tail, file=sys.stderr)
        return 2
    print('baseline green')

    results = []
    for name in args.files:
        path = repo / name
        original = path.read_bytes()
        digest = hashlib.sha256(original).hexdigest()
        text, found = guards(path)
        print(f'{name}: {len(found)} guards')
        try:
            for index, guard in enumerate(found, start=1):
                if args.limit and len(results) >= args.limit:
                    break
                mutated = text[:guard['start']] + 'False' + text[guard['end']:]
                path.write_text(mutated, encoding='utf-8', newline='')
                started = time.time()
                still_green, tail = run_suite(command, repo)
                results.append({
                    'file': name,
                    'line': guard['line'],
                    'test': ' '.join(guard['test'].split())[:200],
                    'survived': still_green,
                    'seconds': round(time.time() - started, 1),
                })
                print(f"  [{index}/{len(found)}] line {guard['line']}: {'SURVIVED' if still_green else 'caught'}")
        finally:
            path.write_bytes(original)
        if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            print(f'REFUSED: {name} was not restored byte-identically; this sweep reports nothing.', file=sys.stderr)
            return 2

    green, tail = run_suite(command, repo)
    if not green:
        print('REFUSED: the suite is red after restoration, so the sweep cannot be trusted.', file=sys.stderr)
        print(tail, file=sys.stderr)
        return 2

    survivors = [row for row in results if row['survived']]
    Path(repo / args.out).write_text(json.dumps({
        'command': command,
        'total_guards': len(results),
        'survivors': len(survivors),
        'results': results,
    }, indent=2) + '\n', encoding='utf-8')
    print(f'{len(survivors)} of {len(results)} guards survived; wrote {args.out}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
