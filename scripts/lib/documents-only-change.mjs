// WHICH PULL REQUESTS ARE "DOCUMENTS ONLY" (issue #2102, owner decision 2026-09-02).
//
// A pull request whose changed files are all prose documents still runs every
// automated check and still merges through the guarded merge lane. What it no
// longer does is consume a slot from the small external database-reviewer pool
// that exists for migrations. PR #2034 -- a two-file documentation change --
// spent two reviewer draws, two dead-reviewer replacements and three full review
// runs; PR #2070 was the same shape. That is pool capacity migrations needed.
//
// Review is NOT removed. The review of PR #2034 caught a real customer order
// number heading into this PUBLIC repository, so the content risk is real. What
// changes is only WHICH pool answers for it: the documents-only lane is answered
// by the automated checks and the guarded merge, not by an external reviewer
// draw.
//
// RULEBOOK FILES ARE NOT DOCUMENTS HERE, and that is the whole safety of this
// module. `AGENTS.md`, anything under `.claude/skills/` or `skills/`, and
// `plan_*.md` files are prose by extension but they are INSTRUCTIONS TO AGENTS:
// a bad edit to one of them is as dangerous as a bad migration, because every
// later session obeys it. They keep the full treatment.
//
// Everything here is deterministic and path-based. It never reads file content,
// never calls GitHub, and never guesses: anything it does not positively
// recognise as a document makes the whole change non-exempt. An empty or
// unreadable file list is NOT documents-only -- "we could not tell" must cost a
// review, never grant an exemption.

// Rulebook exclusions, listed explicitly rather than derived, so a reader can
// check the list against the rule without running anything.
const RULEBOOK_BASENAMES = new Set(['agents.md', 'claude.md'])
const RULEBOOK_DIRECTORY_SEGMENTS = ['.claude/skills/', 'skills/', '.claude/agents/', '.claude/commands/']
const RULEBOOK_BASENAME_PATTERN = /^plan_.*\.md$/

// Prose document extensions. Deliberately short: a new extension is a decision,
// not an oversight, and the safe default for an unlisted one is "not a document".
const DOCUMENT_EXTENSIONS = new Set(['.md', '.markdown', '.txt', '.rst'])

function normalize(path) {
  return String(path ?? '').trim().replace(/\\/g, '/').replace(/^\.\//, '').toLowerCase()
}

// A rulebook path tells agents how to behave. `.claude/skills/x/SKILL.md` and a
// top-level `skills/...` file both qualify wherever they sit in the tree, because
// a nested copy instructs just as loudly as a top-level one.
export function isRulebookPath(path) {
  const normalized = normalize(path)
  if (!normalized) return true
  const basename = normalized.slice(normalized.lastIndexOf('/') + 1)
  if (RULEBOOK_BASENAMES.has(basename)) return true
  if (RULEBOOK_BASENAME_PATTERN.test(basename)) return true
  const probe = `/${normalized}`
  return RULEBOOK_DIRECTORY_SEGMENTS.some((segment) => probe.includes(`/${segment}`))
}

// A prose document: recognised extension, and not a rulebook file.
export function isDocumentPath(path) {
  const normalized = normalize(path)
  if (!normalized) return false
  if (normalized.endsWith('/')) return false
  if (isRulebookPath(normalized)) return false
  const dot = normalized.lastIndexOf('.')
  const slash = normalized.lastIndexOf('/')
  if (dot <= slash) return false
  return DOCUMENT_EXTENSIONS.has(normalized.slice(dot))
}

// The required-status lane has a slightly wider, separately named policy than
// the scarce database-reviewer exemption. Plans are prose delivery records and
// may use the lightweight required-status path (#2715), but they remain
// rulebooks for reviewer assignment under #2102. Executable agent instructions
// (AGENTS/CLAUDE and skill/agent/command directories) are never lightweight.
export function isLightweightMergeDocumentPath(path) {
  const normalized = normalize(path)
  if (!normalized || normalized.endsWith('/')) return false
  const basename = normalized.slice(normalized.lastIndexOf('/') + 1)
  if (RULEBOOK_BASENAMES.has(basename)) return false
  const probe = `/${normalized}`
  if (RULEBOOK_DIRECTORY_SEGMENTS.some((segment) => probe.includes(`/${segment}`))) return false
  const dot = normalized.lastIndexOf('.')
  const slash = normalized.lastIndexOf('/')
  return dot > slash && DOCUMENT_EXTENSIONS.has(normalized.slice(dot))
}

const DECLARATIVE_POINTER_BASENAMES = new Set(['agents.md', 'claude.md', 'task-router.md'])
const BEHAVIOR_WORDS = /\b(?:must|never|always|shall|required?|requires?|do not|don't|runs?|executes?|enforces?|forbids?|refuses?|bypasses?|disables?|enables?|merges?|deploys?|applies?|writes?|deletes?|removes?|accepts?|rejects?|classifies?|grants?|skips?|weakens?|changes?|modifies?|edits?|updates?|uses?|follows?|loads?|sends?|starts?|stops?|closes?|opens?|invokes?|calls?|sets?|allows?|denies?)\b/i
const LOCAL_MARKDOWN_LINK = /\[[^\]\r\n]+\]\((?!https?:|mailto:|#)[^)\r\n]+\.md(?:#[^)\r\n]*)?\)/gi

function isInstructionBearingPath(path) {
  const normalized = normalize(path)
  const basename = normalized.slice(normalized.lastIndexOf('/') + 1)
  if (DECLARATIVE_POINTER_BASENAMES.has(basename)) return true
  const probe = `/${normalized}`
  return RULEBOOK_DIRECTORY_SEGMENTS.some((segment) => probe.includes(`/${segment}`))
}

// A path-only Markdown test cannot safely distinguish a routing pointer from a
// new operating instruction. For instruction-bearing files, inspect every
// changed hunk line. The accepted grammar is intentionally small: a list/table
// row containing a local Markdown link, with no imperative safety verb. Missing
// or truncated patches are not pointers.
export function isDeclarativePointerPatch(patch) {
  if (typeof patch !== 'string' || !patch.trim() || patch.includes('\\ No newline at end of file')) return false
  const changed = patch.split(/\r?\n/).filter((line) => (/^[+-]/.test(line) && !/^\+\+\+|^---/.test(line))).map((line) => line.slice(1))
  if (!changed.length) return false
  return changed.every((line) => {
    const trimmed = line.trim()
    if (!trimmed) return true
    if (!/^(?:[-*+]\s+|\|)/.test(trimmed)) return false
    const links = [...trimmed.matchAll(LOCAL_MARKDOWN_LINK)]
    if (!links.length || BEHAVIOR_WORDS.test(trimmed)) return false
    const remainder = trimmed.replace(LOCAL_MARKDOWN_LINK, '').replace(/`[^`\r\n]+`/g, '')
    return !/[.!?]/.test(remainder) && remainder.length <= 120
  })
}

export function classifyLightweightMergePullRequestFiles(rows) {
  if (!Array.isArray(rows) || !rows.length) return { documentsOnly: false, reason: 'the pull request file list was empty or unreadable' }
  const paths = changedPathsFromPullRequestFiles(rows)
  const pathVerdict = classifyLightweightMergePaths(paths)
  if (!pathVerdict.documentsOnly) return pathVerdict
  for (const row of rows) {
    const current = normalize(row?.filename)
    const previous = normalize(row?.previous_filename)
    if (previous && (isInstructionBearingPath(current) || isInstructionBearingPath(previous))) {
      return { documentsOnly: false, reason: `an instruction-bearing rename always retains the guarded path: ${previous} -> ${current}` }
    }
    for (const path of [current, previous].filter(Boolean)) {
      if (isInstructionBearingPath(path) && !isDeclarativePointerPatch(row?.patch)) {
        return { documentsOnly: false, reason: `instruction-bearing file does not contain only declarative routing pointers: ${path}` }
      }
    }
  }
  return pathVerdict
}

export function classifyLightweightMergePaths(paths) {
  if (!Array.isArray(paths)) return { documentsOnly: false, reason: 'the changed-file list could not be read', documents: [], other: [] }
  if (paths.some((path) => typeof path !== 'string' || !normalize(path))) {
    return { documentsOnly: false, reason: 'the changed-file list contains an unreadable entry', documents: [], other: [] }
  }
  if (!paths.length) return { documentsOnly: false, reason: 'no changed files were reported; an unknown change is never documents-only', documents: [], other: [] }
  const documents = paths.filter((path) => isLightweightMergeDocumentPath(path) || isInstructionBearingPath(path))
  const other = paths.filter((path) => !isLightweightMergeDocumentPath(path) && !isInstructionBearingPath(path))
  if (other.length) return { documentsOnly: false, reason: `non-lightweight file(s) changed: ${other.join(', ')}`, documents, other }
  return { documentsOnly: true, reason: `all ${documents.length} changed file(s) are lightweight prose documents`, documents, other }
}

// The classification the merge gate and the reviewer draw both use. `paths` must
// be the COMPLETE changed-file list for the head being merged, including the
// previous name of every rename -- a file renamed out of `supabase/migrations/`
// into a `.md` is a migration change wearing a document's name.
export function classifyChangedPaths(paths) {
  if (!Array.isArray(paths)) return { documentsOnly: false, reason: 'the changed-file list could not be read', documents: [], rulebook: [], other: [] }
  if (paths.some((path) => typeof path !== 'string' || !normalize(path))) {
    return { documentsOnly: false, reason: 'the changed-file list contains an unreadable entry', documents: [], rulebook: [], other: [] }
  }
  if (!paths.length) return { documentsOnly: false, reason: 'no changed files were reported; an unknown change is never documents-only', documents: [], rulebook: [], other: [] }

  const rulebook = paths.filter((path) => isRulebookPath(path))
  const documents = paths.filter((path) => isDocumentPath(path))
  const other = paths.filter((path) => !isRulebookPath(path) && !isDocumentPath(path))
  if (rulebook.length) return { documentsOnly: false, reason: `rulebook file(s) changed, which are never documents for this purpose: ${rulebook.join(', ')}`, documents, rulebook, other }
  if (other.length) return { documentsOnly: false, reason: `non-document file(s) changed: ${other.join(', ')}`, documents, rulebook, other }
  return { documentsOnly: true, reason: `all ${documents.length} changed file(s) are prose documents`, documents, rulebook, other }
}

export function isDocumentsOnlyChange(paths) {
  return classifyChangedPaths(paths).documentsOnly
}

// GitHub's `pulls/{n}/files` rows, reduced to the path list this module judges.
// Both `filename` and `previous_filename` are taken: a rename must be judged on
// where the bytes came from as well as where they landed. A row that does not
// carry a usable filename yields an unreadable marker, which fails the whole
// classification closed rather than silently shrinking the list.
export function changedPathsFromPullRequestFiles(rows) {
  if (!Array.isArray(rows)) return null
  return rows.flatMap((row) => {
    const filename = row && typeof row === 'object' ? row.filename : undefined
    if (typeof filename !== 'string' || !filename.trim()) return [null]
    const previous = row.previous_filename
    return typeof previous === 'string' && previous.trim() ? [filename, previous] : [filename]
  })
}
