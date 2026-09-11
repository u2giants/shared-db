#!/usr/bin/env node
import { pathToFileURL } from 'node:url'
import { runGitHubCommand } from './lib/github-transport.mjs'

const CONTEXT = 'Migration guarded merge authorization'

export function main(argv, deps = {}) {
  const [repo, headSha, state, description, targetUrl] = argv
  const err = deps.err ?? ((text) => process.stderr.write(text))
  if (argv.length !== 5 || !/^[^/\s]+\/[^/\s]+$/.test(String(repo ?? '')) || !/^[0-9a-f]{40}$/.test(String(headSha ?? '')) || !['success', 'failure'].includes(state) || !description || !/^https:\/\//.test(String(targetUrl ?? ''))) {
    err('usage: write-documents-only-merge-status.mjs <owner/repo> <40-char-head-sha> <success|failure> <description> <https-target-url>\n')
    return 2
  }
  const run = deps.run ?? runGitHubCommand
  try {
    run(['api', `repos/${repo}/statuses/${headSha}`, '-f', `state=${state}`, '-f', `context=${CONTEXT}`, '-f', `description=${description}`, '-f', `target_url=${targetUrl}`], {
      wrapError: (detail, cause) => new Error(`documents-only status write failed: ${detail}${cause ? `: ${cause.message}` : ''}`),
    })
    return 0
  } catch (error) {
    err(`${error.message}\n`)
    return 1
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) process.exit(main(process.argv.slice(2)))
