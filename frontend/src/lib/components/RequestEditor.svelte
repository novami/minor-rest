<script lang="ts" module>
  type Section = 'params' | 'body' | 'headers' | 'settings' | 'docs'
  const lastSection = new Map<string, Section>()
</script>

<script lang="ts">
  import { t } from '../i18n/index.svelte'
  import Button from './Button.svelte'
  import MethodSelect from './MethodSelect.svelte'
  import VarInput from './VarInput.svelte'
  import KvEditor from './KvEditor.svelte'
  import BodyEditor from './BodyEditor.svelte'
  import SettingsEditor from './SettingsEditor.svelte'
  import CodeEditor from './CodeEditor.svelte'
  import * as App from '../../../wailsjs/go/main/App'
  import type { model } from '../../../wailsjs/go/models'
  import { syncPath } from '../util/kv'
  import { headerNames, valuesFor } from '../util/headers'
  import { reloadFromDisk, keepMine, type Tab } from '../stores/tabs.svelte'
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

  // svelte-ignore state_referenced_locally
  let section = $state<Section>(lastSection.get(tab.id) ?? 'params')
  $effect(() => {
    lastSection.set(tab.id, section)
  })
  const count = (rows: { enabled?: boolean; name: string }[] | undefined) =>
    (rows ?? []).filter((r) => r.enabled !== false && r.name).length
  const sections = $derived<{ id: Section; n: number }[]>([
    { id: 'params', n: count(tab.draft.params.query) + (tab.draft.params.path?.length ?? 0) },
    { id: 'body', n: 0 },
    { id: 'headers', n: count(tab.draft.headers) },
    { id: 'settings', n: Object.keys(tab.draft.settings ?? {}).length },
    { id: 'docs', n: 0 },
  ])

  // Inherited values are fetched whenever the Settings section is shown (project settings may change).
  let inherited = $state<model.HTTPSettings | null>(null)
  $effect(() => {
    if (section !== 'settings') return
    App.GetInheritedSettings(tab.projectID).then((s) => (inherited = s), () => (inherited = null))
  })

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
      {t(`request.section.${s.id}`)}{#if (s.id === 'body' && tab.draft.body.type !== 'none') || (s.id === 'docs' && tab.draft.docs)}<span class="dot"></span>{/if}{#if s.n}<span class="n">{s.n}</span>{/if}
    </button>
  {/each}
</nav>

{#if tab.diskChanged}
  <div class="banner" role="alert">
    <span>{t('request.changedOnDisk')}</span>
    <Button onclick={() => reloadFromDisk(tab)}>{t('request.loadFromDisk')}</Button>
    <Button onclick={() => keepMine(tab)}>{t('request.keepMine')}</Button>
  </div>
{/if}

<div class="panel" class:fill={section === 'body' || section === 'docs'}>
  {#if section === 'params'}
    <h4>{t('request.query')}</h4>
    <KvEditor bind:rows={tab.draft.params.query} allowBare />
    {#if tab.draft.params.path?.length}
      <h4>{t('request.path')}</h4>
      <KvEditor bind:rows={tab.draft.params.path} fixed />
    {/if}
  {:else if section === 'body'}
    <BodyEditor bind:body={tab.draft.body} projectID={tab.projectID} />
  {:else if section === 'headers'}
    <KvEditor bind:rows={tab.draft.headers} names={headerNames} {valuesFor} />
  {:else if section === 'settings'}
    <SettingsEditor bind:settings={tab.draft.settings} {inherited} />
  {:else}
    <CodeEditor lang="markdown" bind:value={() => tab.draft.docs ?? '', (v) => (tab.draft.docs = v || undefined)} />
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
  .dot {
    display: inline-block;
    width: 5px;
    height: 5px;
    margin-left: 5px;
    border-radius: 50%;
    background: var(--accent);
    vertical-align: middle;
  }
  .n {
    margin-left: 5px;
    color: var(--text-muted);
    font-size: 11px;
  }
  .panel {
    padding: 8px;
  }
  .banner {
    display: flex;
    align-items: center;
    gap: 8px;
    margin: 8px 8px 0;
    padding: 6px 8px;
    border: 1px solid var(--accent);
    border-radius: var(--radius);
  }
  .banner span {
    flex: 1;
  }
  .panel.fill {
    flex: 1;
    min-height: 0;
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
