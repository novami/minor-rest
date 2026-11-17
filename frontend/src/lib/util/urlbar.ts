import type { model } from '../../../wailsjs/go/models'

/** Text of the URL bar: URL + enabled query params (raw, encoding happens on send). */
export function composeUrl(url: string, query: model.KV[] | undefined): string {
  const q = (query ?? [])
    .filter((p) => p.enabled && (p.name || p.value))
    .map((p) => (p.bare && !p.value ? p.name : `${p.name}=${p.value}`))
  return q.length ? `${url}?${q.join('&')}` : url
}

/**
 * Splits URL bar text into URL and query. Parsed params replace the enabled rows in order
 * (descriptions are kept), disabled rows stay where they were.
 */
export function parseUrl(text: string, query: model.KV[] | undefined): { url: string; query: model.KV[] } {
  const i = text.indexOf('?')
  const url = i < 0 ? text : text.slice(0, i)
  const parsed = i < 0 ? [] : text.slice(i + 1).split('&').filter(Boolean)
  const out: model.KV[] = []
  let k = 0
  for (const row of query ?? []) {
    if (!row.enabled) {
      out.push(row)
    } else if (k < parsed.length) {
      out.push({ ...row, ...pair(parsed[k++]) })
    }
  }
  for (; k < parsed.length; k++) out.push({ enabled: true, ...pair(parsed[k]) } as model.KV)
  return { url, query: out }
}

function pair(s: string): { name: string; value: string; bare: boolean } {
  const j = s.indexOf('=')
  return j < 0 ? { name: s, value: '', bare: true } : { name: s.slice(0, j), value: s.slice(j + 1), bare: false }
}
