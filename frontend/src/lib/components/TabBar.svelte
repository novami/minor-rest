<script lang="ts">
  import { t } from '../i18n/index.svelte'
  import Modal from './Modal.svelte'
  import Button from './Button.svelte'
  import { ws } from '../stores/workspace.svelte'
  import { createNode } from '../stores/tree.svelte'
  import { tabs, projectTabs, isDirty, tabName, activate, closeTab, resolveClose, resolveCloseProject } from '../stores/tabs.svelte'

  const list = $derived(projectTabs())
  const pending = $derived(list.find((x) => x.id === tabs.confirmClose))
  const pendingProject = $derived(ws.projects.find((p) => p.id === tabs.confirmProject))

  function onauxclick(e: MouseEvent, id: string) {
    if (e.button === 1) closeTab(id)
  }
</script>

<div class="tabbar" role="tablist">
  {#each list as tab (tab.id)}
    {@const active = tab.id === ws.activeTab[ws.activeProject]}
    {@const dirty = isDirty(tab)}
    <div
      class="tab"
      class:active
      role="tab"
      tabindex="-1"
      aria-selected={active}
      title={tab.rel}
      onclick={() => activate(tab.id)}
      onkeydown={(e) => e.key === 'Enter' && activate(tab.id)}
      onauxclick={(e) => onauxclick(e, tab.id)}
    >
      <span class="method m-{tab.draft.method.toLowerCase()}">{tab.draft.method}</span>
      <span class="name">{tabName(tab)}</span>
      <button
        class="close"
        class:dirty
        title={t('tabs.close')}
        onclick={(e) => (e.stopPropagation(), closeTab(tab.id))}
      >
        <span class="dot">●</span><span class="x">×</span>
      </button>
    </div>
  {/each}
  <button class="add" title={t('tree.newRequest')} onclick={() => createNode('request')}>+</button>
</div>

<Modal open={!!pending} title={t('tabs.unsavedTitle')} width="440px" onclose={() => resolveClose('cancel')}>
  <p class="confirm">{t('tabs.unsavedMessage', { name: pending ? tabName(pending) : '' })}</p>
  {#snippet footer()}
    <Button onclick={() => resolveClose('cancel')}>{t('common.cancel')}</Button>
    <Button variant="danger" onclick={() => resolveClose('discard')}>{t('tabs.discard')}</Button>
    <Button variant="primary" onclick={() => resolveClose('save')}>{t('tabs.save')}</Button>
  {/snippet}
</Modal>

<Modal
  open={!!pendingProject}
  title={t('tabs.unsavedTitle')}
  width="440px"
  onclose={() => resolveCloseProject('cancel')}
>
  <p class="confirm">{t('tabs.unsavedProject', { name: pendingProject?.name ?? '' })}</p>
  {#snippet footer()}
    <Button onclick={() => resolveCloseProject('cancel')}>{t('common.cancel')}</Button>
    <Button variant="danger" onclick={() => resolveCloseProject('discard')}>{t('tabs.discard')}</Button>
    <Button variant="primary" onclick={() => resolveCloseProject('save')}>{t('tabs.saveAll')}</Button>
  {/snippet}
</Modal>

<style>
  .tabbar {
    flex: none;
    display: flex;
    align-items: stretch;
    height: 32px;
    overflow-x: auto;
    border-bottom: 1px solid var(--border);
    background: var(--bg-sidebar);
    scrollbar-width: none;
  }
  .tab {
    flex: none;
    display: flex;
    align-items: center;
    gap: 6px;
    max-width: 220px;
    padding: 0 4px 0 10px;
    border-right: 1px solid var(--border);
    cursor: default;
    white-space: nowrap;
  }
  .tab:hover {
    background: var(--bg-hover);
  }
  .tab.active {
    background: var(--bg);
    box-shadow: inset 0 -2px 0 var(--accent);
  }
  .name {
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .method {
    font-family: var(--font-code);
    font-size: 10px;
    font-weight: 700;
  }
  .close {
    width: 18px;
    height: 18px;
    padding: 0;
    border: 0;
    border-radius: 3px;
    background: none;
    color: var(--text-muted);
    line-height: 18px;
  }
  .close:hover {
    background: var(--bg-hover);
  }
  .close .dot,
  .close.dirty .x {
    display: none;
  }
  .close.dirty .dot {
    display: inline;
    font-size: 9px;
  }
  .tab:hover .close.dirty .dot,
  .close.dirty:hover .dot {
    display: none;
  }
  .tab:hover .close.dirty .x {
    display: inline;
  }
  .tab:not(.active):not(:hover) .close:not(.dirty) {
    visibility: hidden;
  }
  .add {
    flex: none;
    width: 32px;
    border: 0;
    background: none;
    color: var(--text-muted);
    font-size: 16px;
  }
  .add:hover {
    color: var(--text);
    background: var(--bg-hover);
  }
  .confirm {
    margin: 0;
  }
  .m-get { color: var(--method-get); }
  .m-post { color: var(--method-post); }
  .m-put { color: var(--method-put); }
  .m-patch { color: var(--method-patch); }
  .m-delete { color: var(--method-delete); }
  .m-head { color: var(--method-head); }
  .m-options { color: var(--method-options); }
</style>
