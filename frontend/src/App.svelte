<script lang="ts">
  import { onMount } from 'svelte'
  import { t } from './lib/i18n/index.svelte'
  import { onMenu } from './lib/util/events'
  import { showToast } from './lib/stores/toast.svelte'
  import Splitter from './lib/components/Splitter.svelte'
  import Toasts from './lib/components/Toasts.svelte'

  let sidebarVisible = $state(true)
  let sidebarWidth = $state(260)
  let responseHeight = $state(320)

  const pendingActions = [
    'new-request',
    'new-folder',
    'save',
    'close-tab',
    'settings',
    'focus-url',
    'save-response',
    'copy-curl',
    'duplicate',
    'palette',
    'environment',
  ]

  onMount(() => {
    const offs = [
      onMenu('toggle-sidebar', () => (sidebarVisible = !sidebarVisible)),
      ...pendingActions.map((a) => onMenu(a, () => showToast(t('toast.notImplemented', { action: a })))),
    ]
    return () => offs.forEach((off) => off())
  })
</script>

<div class="app">
  <header class="titlebar">
    <span class="title">{t('app.name')}</span>
  </header>

  <div class="workspace">
    {#if sidebarVisible}
      <aside class="sidebar" style:width="{sidebarWidth}px">
        <div class="section-title">{t('sidebar.title')}</div>
        <div class="empty">{t('sidebar.empty')}</div>
      </aside>
      <Splitter bind:size={sidebarWidth} direction="horizontal" min={180} max={600} />
    {/if}

    <main class="main">
      <section class="request">
        <div class="empty">
          <div>{t('request.empty')}</div>
          <div class="hint">{t('request.emptyHint')}</div>
        </div>
      </section>
      <Splitter bind:size={responseHeight} direction="vertical" min={120} max={1200} invert />
      <section class="response" style:height="{responseHeight}px">
        <div class="empty">
          <div>{t('response.empty')}</div>
          <div class="hint">{t('response.emptyHint')}</div>
        </div>
      </section>
    </main>
  </div>
</div>

<Toasts />

<style>
  .app {
    height: 100%;
    display: flex;
    flex-direction: column;
  }
  .titlebar {
    --wails-draggable: drag;
    flex: none;
    height: var(--titlebar-h);
    display: flex;
    align-items: center;
    padding-left: 80px; /* space for the window traffic lights */
    border-bottom: 1px solid var(--border);
    background: var(--bg-sidebar);
  }
  .title {
    font-weight: 600;
    color: var(--text-muted);
  }
  .workspace {
    flex: 1;
    min-height: 0;
    display: flex;
  }
  .sidebar {
    flex: none;
    overflow: auto;
    background: var(--bg-sidebar);
  }
  .section-title {
    padding: 10px 12px 4px;
    font-size: 11px;
    font-weight: 600;
    text-transform: uppercase;
    color: var(--text-muted);
  }
  .main {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
  }
  .request {
    flex: 1;
    min-height: 120px;
    overflow: auto;
  }
  .response {
    flex: none;
    overflow: auto;
  }
  .empty {
    height: 100%;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 4px;
    color: var(--text-muted);
    padding: 12px;
    text-align: center;
  }
  .sidebar .empty {
    height: auto;
    padding-top: 24px;
  }
  .hint {
    font-size: 0.9em;
    opacity: 0.8;
  }
</style>
