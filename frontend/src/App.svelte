<script lang="ts">
  import { onMount } from 'svelte'
  import { t } from './lib/i18n/index.svelte'
  import { onEvent, onMenu } from './lib/util/events'
  import { showToast } from './lib/stores/toast.svelte'
  import Splitter from './lib/components/Splitter.svelte'
  import Toasts from './lib/components/Toasts.svelte'
  import ProjectSwitcher from './lib/components/ProjectSwitcher.svelte'
  import Tree from './lib/components/Tree.svelte'
  import TabBar from './lib/components/TabBar.svelte'
  import RequestEditor from './lib/components/RequestEditor.svelte'
  import * as Backend from '../wailsjs/go/main/App'
  import { ws, initWorkspace, saveWorkspace, reloadTree } from './lib/stores/workspace.svelte'
  import { createNode, duplicateNode } from './lib/stores/tree.svelte'
  import { activeTab, anyDirty, closeTab, saveTab } from './lib/stores/tabs.svelte'

  let ready = false
  $effect(() => {
    // persist panel layout whenever it changes (after the workspace is loaded)
    void [ws.sidebarHidden, ws.sidebarWidth, ws.responseHeight]
    if (ready) saveWorkspace()
  })

  const tab = $derived(activeTab())
  let urlEl = $state<HTMLInputElement>()

  // native quit confirmation needs to know about unsaved tabs
  let lastDirty = false
  $effect(() => {
    const d = anyDirty()
    if (d !== lastDirty && (window as any).go) Backend.SetDirty(d)
    lastDirty = d
  })

  function send() {
    showToast(t('toast.notImplemented', { action: 'send' }))
  }

  function onkeydown(e: KeyboardEvent) {
    if (e.metaKey && e.key === 'Enter' && tab) {
      e.preventDefault()
      send()
    }
  }

  const pendingActions = [
    'settings',
    'save-response',
    'copy-curl',
    'palette',
    'environment',
  ]

  onMount(() => {
    initWorkspace().finally(() => (ready = true))
    const offs = [
      onEvent('tree:changed', (e: { projectID: string }) => e?.projectID === ws.activeProject && reloadTree()),
      onMenu('toggle-sidebar', () => (ws.sidebarHidden = !ws.sidebarHidden)),
      onMenu('new-request', () => createNode('request')),
      onMenu('new-folder', () => createNode('folder')),
      onMenu('duplicate', () => duplicateNode()),
      onMenu('save', () => saveTab()),
      onMenu('close-tab', () => closeTab()),
      onMenu('focus-url', () => urlEl?.select()),
      ...pendingActions.map((a) => onMenu(a, () => showToast(t('toast.notImplemented', { action: a })))),
    ]
    return () => offs.forEach((off) => off())
  })
</script>

<svelte:window {onkeydown} />

<div class="app">
  <header class="titlebar">
    <ProjectSwitcher />
  </header>

  <div class="workspace">
    {#if !ws.sidebarHidden}
      <aside class="sidebar" style:width="{ws.sidebarWidth}px">
        {#if !ws.activeProject}
          <div class="empty">{t('sidebar.noProject')}</div>
        {:else if ws.tree}
          <Tree root={ws.tree} />
        {/if}
      </aside>
      <Splitter bind:size={ws.sidebarWidth} direction="horizontal" min={180} max={600} />
    {/if}

    <main class="main">
      <section class="request">
        {#if ws.activeProject}
          <TabBar />
        {/if}
        {#if tab}
          {#key tab.id}
            <RequestEditor {tab} onsend={send} bind:urlEl />
          {/key}
        {:else}
          <div class="empty">
            <div>{t('request.empty')}</div>
            <div class="hint">{t('request.emptyHint')}</div>
          </div>
        {/if}
      </section>
      <Splitter bind:size={ws.responseHeight} direction="vertical" min={120} max={1200} invert />
      <section class="response" style:height="{ws.responseHeight}px">
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
    display: flex;
    flex-direction: column;
  }
  .request .empty {
    height: auto;
    flex: 1;
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
