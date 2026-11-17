import { t } from '../i18n/index.svelte'

/** Backend errors are `CODE: detail`; returns localized text for `errors.CODE` plus the detail. */
export function errorText(err: unknown): string {
  const s = String(err instanceof Error ? err.message : err)
  const i = s.indexOf(':')
  const code = i > 0 ? s.slice(0, i) : s
  const key = `errors.${code}`
  const msg = t(key)
  if (msg === key) return s
  const detail = i > 0 ? s.slice(i + 1).trim() : ''
  return detail ? `${msg} (${detail})` : msg
}
