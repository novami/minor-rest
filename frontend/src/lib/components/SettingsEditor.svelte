<script lang="ts">
  import { t } from '../i18n/index.svelte'
  import type { model } from '../../../wailsjs/go/models'

  interface Props {
    settings: model.HTTPSettings
    inherited: model.HTTPSettings | null
  }
  let { settings = $bindable(), inherited }: Props = $props()

  type Key = 'httpVersion' | 'followRedirects' | 'maxRedirects' | 'timeoutMs' | 'verifyTls'
  const INHERIT = '__inherit'

  const rows: { key: Key; kind: 'version' | 'bool' | 'number'; min: number }[] = [
    { key: 'httpVersion', kind: 'version', min: 0 },
    { key: 'followRedirects', kind: 'bool', min: 0 },
    { key: 'maxRedirects', kind: 'number', min: 0 },
    { key: 'timeoutMs', kind: 'number', min: 1 },
    { key: 'verifyTls', kind: 'bool', min: 0 },
  ]
  const versions = ['auto', 'http1', 'http2']

  function show(key: Key, v: unknown): string {
    if (v === undefined || v === null) return '—'
    if (typeof v === 'boolean') return t(v ? 'settings.on' : 'settings.off')
    if (key === 'httpVersion') return t(`settings.version.${v}`)
    return String(v)
  }

  // Inherit = the key is removed, so it is omitted on disk (YAML omitempty). Keys are rebuilt in the
  // Go field order, otherwise JSON comparison would mark an unchanged tab as dirty.
  const order = ['httpVersion', 'followRedirects', 'maxRedirects', 'timeoutMs', 'verifyTls', 'cookieJar'] as const
  function set(key: Key, v: unknown) {
    const cur = { ...settings, [key]: v } as Record<string, unknown>
    const next: Record<string, unknown> = {}
    for (const k of order) if (cur[k] !== undefined && cur[k] !== null) next[k] = cur[k]
    settings = next as model.HTTPSettings
  }

  function onselect(key: Key, kind: string, value: string) {
    if (value === INHERIT) return set(key, undefined)
    if (kind === 'bool') return set(key, value === 'true')
    if (kind === 'number') return set(key, inherited?.[key] ?? 0)
    set(key, value)
  }

  function onnumber(key: Key, min: number, e: Event) {
    const n = (e.currentTarget as HTMLInputElement).valueAsNumber
    if (Number.isInteger(n) && n >= min) set(key, n)
  }
</script>

<div class="grid">
  {#each rows as r (r.key)}
    {@const own = settings[r.key]}
    {@const isOwn = own !== undefined && own !== null}
    <label for="s-{r.key}">{t(`settings.${r.key}`)}</label>
    <div class="value">
      <select
        id="s-{r.key}"
        value={!isOwn ? INHERIT : r.kind === 'number' ? 'own' : String(own)}
        onchange={(e) => onselect(r.key, r.kind, e.currentTarget.value)}
      >
        <option value={INHERIT}>{t('settings.inherit', { value: show(r.key, inherited?.[r.key]) })}</option>
        {#if r.kind === 'version'}
          {#each versions as v (v)}<option value={v}>{t(`settings.version.${v}`)}</option>{/each}
        {:else if r.kind === 'bool'}
          <option value="true">{t('settings.on')}</option>
          <option value="false">{t('settings.off')}</option>
        {:else}
          <option value="own">{t('settings.custom')}</option>
        {/if}
      </select>
      {#if r.kind === 'number' && isOwn}
        <input type="number" min={r.min} step="1" value={own} oninput={(e) => onnumber(r.key, r.min, e)} />
        {#if r.key === 'timeoutMs'}<span class="unit">ms</span>{/if}
      {/if}
    </div>
  {/each}
</div>

<style>
  .grid {
    display: grid;
    grid-template-columns: max-content 1fr;
    gap: 8px 16px;
    align-items: center;
    max-width: 640px;
  }
  label {
    color: var(--text-muted);
  }
  .value {
    display: flex;
    align-items: center;
    gap: 6px;
  }
  select,
  input {
    height: 26px;
    padding: 0 6px;
    border: 1px solid var(--border);
    border-radius: 4px;
    background: var(--bg);
    color: var(--text);
    font: inherit;
  }
  input {
    width: 110px;
  }
  .unit {
    color: var(--text-muted);
  }
</style>
