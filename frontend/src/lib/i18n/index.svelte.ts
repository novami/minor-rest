import cs from './cs.json'
import en from './en.json'

export type Lang = 'cs' | 'en'
export type LangSetting = Lang | 'auto'

const dictionaries: Record<Lang, Record<string, string>> = { cs, en }

function detect(): Lang {
  return navigator.language.toLowerCase().startsWith('cs') ? 'cs' : 'en'
}

const state = $state({ lang: detect() as Lang })

export function setLang(setting: LangSetting) {
  state.lang = setting === 'auto' ? detect() : setting
  document.documentElement.lang = state.lang
}

export function lang(): Lang {
  return state.lang
}

/** Translate a key; `{name}` placeholders are replaced from params. Missing keys fall back to English, then the key. */
export function t(key: string, params?: Record<string, string | number>): string {
  let s = dictionaries[state.lang][key] ?? dictionaries.en[key] ?? key
  if (params) {
    for (const [k, v] of Object.entries(params)) s = s.replaceAll(`{${k}}`, String(v))
  }
  return s
}
