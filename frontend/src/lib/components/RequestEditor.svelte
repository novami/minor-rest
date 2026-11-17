<script lang="ts">
  import { t } from '../i18n/index.svelte'
  import Button from './Button.svelte'
  import MethodSelect from './MethodSelect.svelte'
  import VarInput from './VarInput.svelte'
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

<style>
  .urlbar {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 8px;
  }
</style>
