// Where licensed row data may be written.
//
// The manifest and the before-state backup both carry licensed item identities.
// This repository is PUBLIC. Nothing previously stopped an operator from passing
// `--out .` and committing ~1,190 licensed rows to a public repository by
// accident, and no gate downstream would have caught it: the PII guard scans for
// email shapes, not item identities.
//
// So the destination is checked before anything is written. A directory inside a
// git working tree is refused unless git itself says the path is ignored, which
// is the only authority that actually decides whether a file can be committed.

import { execFileSync } from 'node:child_process';
import { resolve } from 'node:path';

function gitTopLevel(dir) {
  try {
    return execFileSync('git', ['-C', dir, 'rev-parse', '--show-toplevel'], {
      encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
  } catch { return null; }
}

function gitIgnores(top, dir) {
  try {
    execFileSync('git', ['-C', top, 'check-ignore', '-q', '--', dir], {
      stdio: ['ignore', 'ignore', 'ignore'],
    });
    return true;
  } catch { return false; }
}

/**
 * Prove an output directory may hold licensed row data.
 *
 * @param {string} candidate operator-supplied path
 * @param {{topLevel?:Function, ignores?:Function}} deps injected for tests
 * @returns {string} the resolved absolute directory
 */
export function assertPrivateOutputDir(candidate, deps = {}) {
  if (!candidate || typeof candidate !== 'string' || candidate.trim() === '') {
    throw new Error('REFUSED: an output directory is required');
  }
  const dir = resolve(candidate);
  const top = (deps.topLevel ?? gitTopLevel)(dir);
  if (top === null) return dir; // outside any git working tree
  const ignored = (deps.ignores ?? gitIgnores)(top, dir);
  if (!ignored) {
    throw new Error(
      'REFUSED: licensed row data may not be written inside a git working tree '
      + 'unless git ignores the destination; write it to the private repository '
      + 'or to an ignored directory',
    );
  }
  return dir;
}
