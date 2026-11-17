<script lang="ts">
  import { t } from '../i18n/index.svelte'
  import Modal from './Modal.svelte'
  import Button from './Button.svelte'
  import {
    ws,
    activeProject,
    selectProject,
    createProject,
    openProjectDialog,
    closeProject,
  } from '../stores/workspace.svelte'

  let open = $state(false)
  let creating = $state(false)
  let newName = $state('')
  let root: HTMLElement

  const current = $derived(activeProject())

  function run(fn: () => void) {
    open = false
    fn()
  }

  function startCreate() {
    newName = ''
    creating = true
  }

  async function submitCreate(e: SubmitEvent) {
    e.preventDefault()
    if (!newName.trim()) return
    if (await createProject(newName)) creating = false
  }

  function onwindowclick(e: MouseEvent) {
    if (open && !root.contains(e.target as Node)) open = false
  }

  function onkeydown(e: KeyboardEvent) {
    if (open && e.key === 'Escape') open = false
  }
</script>

<svelte:window onclick={onwindowclick} {onkeydown} />

<div class="switcher" bind:this={root}>
  <button class="trigger" onclick={() => (open = !open)} aria-haspopup="menu" aria-expanded={open}>
    <span class="name">{current?.name ?? t('project.none')}</span>
    {#if current?.readOnly}<span class="ro">{t('project.readOnly')}</span>{/if}
    <span class="caret">▾</span>
  </button>

  {#if open}
    <div class="menu" role="menu">
      {#each ws.projects as p (p.id)}
        <button role="menuitem" class="item" title={p.path} onclick={() => run(() => selectProject(p.id))}>
          <span class="check">{p.id === ws.activeProject ? '✓' : ''}</span>{p.name}
        </button>
      {/each}
      {#if ws.projects.length}<div class="sep"></div>{/if}
      <button role="menuitem" class="item" onclick={() => run(startCreate)}>
        <span class="check"></span>{t('project.new')}
      </button>
      <button role="menuitem" class="item" onclick={() => run(openProjectDialog)}>
        <span class="check"></span>{t('project.open')}
      </button>
      {#if current}
        <div class="sep"></div>
        <button role="menuitem" class="item" onclick={() => run(() => closeProject(current.id))}>
          <span class="check"></span>{t('project.close')}
        </button>
      {/if}
    </div>
  {/if}
</div>

<Modal open={creating} title={t('project.newTitle')} width="400px" onclose={() => (creating = false)}>
  <form id="new-project" onsubmit={submitCreate}>
    <label class="field">
      <span>{t('project.name')}</span>
      <!-- svelte-ignore a11y_autofocus -->
      <input bind:value={newName} autofocus spellcheck="false" />
    </label>
    <p class="hint">{t('project.newHint')}</p>
  </form>
  {#snippet footer()}
    <Button onclick={() => (creating = false)}>{t('common.cancel')}</Button>
    <Button variant="primary" type="submit" disabled={!newName.trim()} form="new-project">{t('common.create')}</Button>
  {/snippet}
</Modal>

<style>
  .switcher {
    position: relative;
    --wails-draggable: no-drag;
  }
  .trigger {
    display: flex;
    align-items: center;
    gap: 6px;
    max-width: 320px;
    padding: 3px 8px;
    border: none;
    border-radius: var(--radius);
    background: none;
    cursor: default;
    font-weight: 600;
  }
  .trigger:hover,
  .trigger[aria-expanded='true'] {
    background: var(--bg-hover);
  }
  .name {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .ro {
    font-size: 11px;
    font-weight: 400;
    color: var(--text-muted);
  }
  .caret {
    color: var(--text-muted);
    font-size: 10px;
  }
  .menu {
    position: absolute;
    top: calc(100% + 4px);
    left: 0;
    z-index: 50;
    min-width: 220px;
    max-width: 360px;
    padding: 4px;
    border: 1px solid var(--border);
    border-radius: var(--radius);
    background: var(--bg-elevated);
    box-shadow: var(--shadow);
  }
  .item {
    display: flex;
    width: 100%;
    padding: 4px 8px;
    border: none;
    border-radius: 4px;
    background: none;
    text-align: left;
    cursor: default;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .item:hover {
    background: var(--accent);
    color: var(--accent-text);
  }
  .check {
    flex: none;
    width: 18px;
  }
  .sep {
    height: 1px;
    margin: 4px 0;
    background: var(--border);
  }
  .field {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }
  .field input {
    padding: 5px 8px;
    border: 1px solid var(--border);
    border-radius: var(--radius);
    background: var(--bg);
  }
  .hint {
    margin: 8px 0 0;
    font-size: 0.9em;
    color: var(--text-muted);
  }
</style>
