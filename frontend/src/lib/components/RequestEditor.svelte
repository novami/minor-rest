<script lang="ts" module>
  const lastSection = new Map<string, 'params' | 'headers'>()
</script>

<script lang="ts">
  import { t } from '../i18n/index.svelte'
  import Button from './Button.svelte'
  import MethodSelect from './MethodSelect.svelte'
  import VarInput from './VarInput.svelte'
  import KvEditor from './KvEditor.svelte'
  import { syncPath } from '../util/kv'
  import { headerNames, valuesFor } from '../util/headers'
  import type { Tab } from '../stores/tabs.svelte'
  import { composeUrl, parseUrl } from '../util/urlbar'

  interface Props {
    tab: Tab
    onsend: () => void
    urlEl?: HTMLInputElement
  }
  let { tab, onsend, urlEl = $bindable() }: Props = $props()

  // The URL bar keeps its own text while typing (e.g. a trailing `?`); it is rebuilt only when
  // URL or query change from elsewhere (another tab, the Params table).
  let text = $state('')
  let shownFor = ''
  $effect(() => {
    const composed = composeUrl(tab.draft.url, tab.draft.params.query)
    const typed = parseUrl(text, tab.draft.params.query)
    if (shownFor !== tab.id || composed !== composeUrl(typed.url, typed.query)) {
      text = composed
      shownFor = tab.id
    }
  })

  // Path params follow `:name` segments of the URL.
  $effect(() => {
    const p = syncPath(tab.draft.url, tab.draft.params.path ?? [])
    if (p) tab.draft.params.path = p
  })

  type Section = 'params' | 'headers'
  // svelte-ignore state_referenced_locally
  let section = $state<Section>(lastSection.get(tab.id) ?? 'params')
  $effect(() => {
    lastSection.set(tab.id, section)
  })
  const count = (rows: { enabled?: boolean; name: string }[] | undefined) =>
    (rows ?? []).filter((r) => r.enabled !== false && r.name).length
  const sections = $derived<{ id: Section; n: number }[]>([
    { id: 'params', n: count(tab.draft.params.query) + (tab.draft.params.path?.length ?? 0) },
    { id: 'headers', n: count(tab.draft.headers) },
  ])

  function oninput(v: string) {
    const p = parseUrl(v, tab.draft.params.query)
    tab.draft.url = p.url
    tab.draft.params.query = p.query
  }

  function onkeydown(e: KeyboardEvent) {
    if (e.key === 'Enter') {
      e.preventDefault()
      onsend()
    }
  }
</script>

<div class="urlbar">
  <MethodSelect bind:value={tab.draft.method} />
  <VarInput bind:value={text} bind:el={urlEl} placeholder={t('request.urlPlaceholder')} {oninput} {onkeydown} />
  <Button variant="primary" onclick={onsend} title="Cmd+Enter">{t('request.send')}</Button>
</div>

<nav class="sections">
  {#each sections as s (s.id)}
    <button class:active={section === s.id} onclick={() => (section = s.id)}>
      {t(`request.section.${s.id}`)}{#if s.n}<span class="n">{s.n}</span>{/if}
    </button>
  {/each}
</nav>

<div class="panel">
  {#if section === 'params'}
    <h4>{t('request.query')}</h4>
    <KvEditor bind:rows={tab.draft.params.query} allowBare />
    {#if tab.draft.params.path?.length}
      <h4>{t('request.path')}</h4>
      <KvEditor bind:rows={tab.draft.params.path} fixed />
    {/if}
  {:else}
    <KvEditor bind:rows={tab.draft.headers} names={headerNames} {valuesFor} />
  {/if}
</div>

<style>
  .urlbar {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 8px;
  }
  .sections {
    display: flex;
    gap: 2px;
    padding: 0 8px;
    border-bottom: 1px solid var(--border);
  }
  .sections button {
    padding: 6px 10px;
    border: 0;
    border-bottom: 2px solid transparent;
    background: none;
    color: var(--text-muted);
    font: inherit;
  }
  .sections button.active {
    color: var(--text);
    border-bottom-color: var(--accent);
  }
  .n {
    margin-left: 5px;
    color: var(--text-muted);
    font-size: 11px;
  }
  .panel {
    padding: 8px;
  }
  h4 {
    margin: 4px 0 4px;
    font-size: 11px;
    font-weight: 600;
    color: var(--text-muted);
    text-transform: uppercase;
  }
  h4 + :global(.kv) {
    margin-bottom: 12px;
  }
</style>
