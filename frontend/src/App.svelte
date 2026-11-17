<script lang="ts">
  import { onMount } from 'svelte'
  import { t } from './lib/i18n/index.svelte'
  import { onEvent, onMenu } from './lib/util/events'
  import { showToast } from './lib/stores/toast.svelte'
  import Splitter from './lib/components/Splitter.svelte'
  import Toasts from './lib/components/Toasts.svelte'
  import ProjectSwitcher from './lib/components/ProjectSwitcher.svelte'
  import Tree from './lib/components/Tree.svelte'
  import { ws, initWorkspace, saveWorkspace, reloadTree } from './lib/stores/workspace.svelte'
  import { createNode, duplicateNode } from './lib/stores/tree.svelte'

  let ready = false
  $effect(() => {
    // persist panel layout whenever it changes (after the workspace is loaded)
    void [ws.sidebarHidden, ws.sidebarWidth, ws.responseHeight]
    if (ready) saveWorkspace()
  })

  const pendingActions = [
    'save',
    'close-tab',
    'settings',
    'focus-url',
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
      ...pendingActions.map((a) => onMenu(a, () => showToast(t('toast.notImplemented', { action: a })))),
    ]
    return () => offs.forEach((off) => off())
  })
</script>

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
        <div class="empty">
          <div>{t('request.empty')}</div>
          <div class="hint">{t('request.emptyHint')}</div>
        </div>
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
