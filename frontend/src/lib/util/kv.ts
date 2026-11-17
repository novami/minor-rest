import type { model } from '../../../wailsjs/go/models'

export interface Row {
  name: string
  value?: string
  enabled?: boolean
  description?: string
  bare?: boolean
  // multipart
  kind?: string
  path?: string
  contentType?: string
}

/** Bulk text: one `name: value` per line, `//` prefix = disabled row. */
export function toBulk(rows: Row[]): string {
  return rows
    .map((r) => `${r.enabled === false ? '//' : ''}${r.name}${r.bare && !r.value ? '' : `: ${r.value ?? ''}`}`)
    .join('\n')
}

/** Parses bulk text; descriptions are kept by name. A line without `:` is a bare row if allowed. */
export function fromBulk(text: string, prev: Row[], allowBare = false): Row[] {
  const desc = new Map<string, string>()
  for (const r of prev) if (r.description && !desc.has(r.name)) desc.set(r.name, r.description)
  const out: Row[] = []
  for (const raw of text.split('\n')) {
    let line = raw.trim()
    if (!line) continue
    const enabled = !line.startsWith('//')
    if (!enabled) line = line.slice(2).trimStart()
    const i = line.indexOf(':')
    const name = (i < 0 ? line : line.slice(0, i)).trim()
    const value = i < 0 ? '' : line.slice(i + 1).trim()
    const row: Row = { name, value, enabled }
    if (desc.has(name)) row.description = desc.get(name)
    if (i < 0 && allowBare) row.bare = true
    out.push(row)
  }
  return out
}

/** Names of `:name` path segments (same rules as vars.BuildURL; a port in the host is not one). */
export function pathParamNames(url: string): string[] {
  let rest = url
  const s = rest.indexOf('://')
  if (s >= 0) rest = rest.slice(s + 3)
  const slash = rest.indexOf('/')
  if (slash < 0) return []
  rest = rest.slice(slash).split(/[?#]/)[0]
  const out: string[] = []
  for (const seg of rest.split('/')) {
    const m = /^:([A-Za-z0-9_-]+)/.exec(seg)
    if (m && !out.includes(m[1])) out.push(m[1])
  }
  return out
}

/** Path rows matching the URL (existing values kept), or null when nothing changes. */
export function syncPath(url: string, path: model.PathParam[]): model.PathParam[] | null {
  const names = pathParamNames(url)
  if (names.length === path.length && names.every((n, i) => path[i].name === n)) return null
  return names.map((n) => path.find((p) => p.name === n) ?? { name: n, value: '' })
}
