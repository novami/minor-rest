<script lang="ts">
  import type { model } from '../../../wailsjs/go/models'
  import { t } from '../i18n/index.svelte'
  import ContextMenu, { type MenuItem } from './ContextMenu.svelte'
  import Modal from './Modal.svelte'
  import Button from './Button.svelte'
  import {
    tree,
    isExpanded,
    setExpanded,
    parentOf,
    findNode,
    createNode,
    renameNode,
    duplicateNode,
    deleteNode,
    revealInFinder,
  } from '../stores/tree.svelte'

  interface Props {
    root: model.TreeNode
  }
  let { root }: Props = $props()

  interface Row {
    node: model.TreeNode
    depth: number
  }

  // visible nodes in display order
  const rows = $derived.by(() => {
    const out: Row[] = []
    const walk = (nodes: model.TreeNode[] | undefined, depth: number) => {
      for (const node of nodes ?? []) {
        out.push({ node, depth })
        if (node.kind === 'folder' && isExpanded(node.rel)) walk(node.children, depth + 1)
      }
    }
    walk(root.children, 0)
    return out
  })

  let listEl: HTMLElement
  let menu = $state<{ x: number; y: number; items: MenuItem[] } | null>(null)
  let confirmDelete = $state<model.TreeNode | null>(null)
  let editValue = $state('')


  function select(rel: string) {
    tree.selected = rel
  }

  function toggle(n: model.TreeNode) {
    if (n.kind === 'folder') setExpanded(n.rel, !isExpanded(n.rel))
  }

  function nodeMenu(n: model.TreeNode): MenuItem[] {
    const folder = n.kind === 'folder' ? n.rel : parentOf(n.rel)
    return [
      { label: t('tree.newRequest'), action: () => createNode('request', folder) },
      { label: t('tree.newFolder'), action: () => createNode('folder', folder) },
      { separator: true },
      { label: t('tree.rename'), action: () => (tree.editing = n.rel) },
      { label: t('tree.duplicate'), action: () => duplicateNode(n.rel) },
      { label: t('tree.reveal'), action: () => revealInFinder(n.rel) },
      { separator: true },
      { label: t('tree.delete'), danger: true, action: () => (confirmDelete = n) },
    ]
  }

  function oncontextmenu(e: MouseEvent, n?: model.TreeNode) {
    e.preventDefault()
    e.stopPropagation()
    listEl.focus()
    if (n) select(n.rel)
    const items: MenuItem[] = n
      ? nodeMenu(n)
      : [
          { label: t('tree.newRequest'), action: () => createNode('request', '') },
          { label: t('tree.newFolder'), action: () => createNode('folder', '') },
        ]
    menu = { x: e.clientX, y: e.clientY, items }
  }

  function onkeydown(e: KeyboardEvent) {
    if (tree.editing || menu) return
    const i = rows.findIndex((r) => r.node.rel === tree.selected)
    const cur = rows[i]?.node
    const move = (j: number) => {
      const r = rows[Math.max(0, Math.min(rows.length - 1, j))]
      if (r) select(r.node.rel)
    }
    switch (e.key) {
      case 'ArrowDown':
        move(i + 1)
        break
      case 'ArrowUp':
        move(i < 0 ? rows.length - 1 : i - 1)
        break
      case 'ArrowRight':
        if (cur?.kind === 'folder') {
          if (!isExpanded(cur.rel)) setExpanded(cur.rel, true)
          else move(i + 1)
        }
        break
      case 'ArrowLeft':
        if (cur?.kind === 'folder' && isExpanded(cur.rel)) setExpanded(cur.rel, false)
        else if (cur && parentOf(cur.rel)) select(parentOf(cur.rel))
        break
      case 'Enter':
        if (cur) toggle(cur)
        break
      case 'F2':
        if (cur) tree.editing = cur.rel
        break
      case 'Backspace':
      case 'Delete':
        if (cur && (e.metaKey || e.key === 'Delete')) confirmDelete = cur
        else return
        break
      default:
        return
    }
    e.preventDefault()
    queueMicrotask(() => listEl.querySelector('.selected')?.scrollIntoView({ block: 'nearest' }))
  }

  function onEditKey(e: KeyboardEvent, rel: string) {
    e.stopPropagation()
    if (e.key === 'Enter') {
      e.preventDefault()
      renameNode(rel, editValue)
      listEl.focus()
    } else if (e.key === 'Escape') {
      e.preventDefault()
      tree.editing = ''
      listEl.focus()
    }
  }

  /** Mounts the inline rename input: fill in the current name and select it. */
  function focusSelect(el: HTMLInputElement) {
    editValue = findNode(tree.editing)?.name ?? ''
    el.value = editValue
    el.focus()
    el.select()
  }

  async function doDelete() {
    const n = confirmDelete
    confirmDelete = null
    listEl.focus()
    if (n) await deleteNode(n.rel)
  }
</script>

<!-- svelte-ignore a11y_no_noninteractive_tabindex -->
<div
  class="tree"
  role="tree"
  tabindex="0"
  bind:this={listEl}
  {onkeydown}
  oncontextmenu={(e) => oncontextmenu(e)}
>
  {#each rows as { node: n, depth } (n.rel)}
    <!-- keyboard is handled by the focusable tree container -->
    <!-- svelte-ignore a11y_click_events_have_key_events, a11y_interactive_supports_focus -->
    <div
      class="row"
      class:selected={n.rel === tree.selected}
      class:broken={!!n.error}
      role="treeitem"
      aria-selected={n.rel === tree.selected}
      aria-expanded={n.kind === 'folder' ? isExpanded(n.rel) : undefined}
      style:padding-left="{6 + depth * 14}px"
      title={n.error ? t(`errors.${n.error}`) : undefined}
      onclick={() => select(n.rel)}
      ondblclick={() => toggle(n)}
      oncontextmenu={(e) => oncontextmenu(e, n)}
    >
      {#if n.kind === 'folder'}
        <!-- svelte-ignore a11y_no_static_element_interactions -->
        <span class="chevron" class:open={isExpanded(n.rel)} onclick={(e) => (e.stopPropagation(), toggle(n))}>▸</span>
        <span class="icon">📁</span>
      {:else}
        <span class="chevron"></span>
        <span class="method m-{(n.method ?? '').toLowerCase()}">{n.method}</span>
      {/if}
      {#if tree.editing === n.rel}
        <input
          class="edit"
          bind:value={editValue}
          use:focusSelect
          spellcheck="false"
          onkeydown={(e) => onEditKey(e, n.rel)}
          onblur={() => tree.editing === n.rel && renameNode(n.rel, editValue)}
          onclick={(e) => e.stopPropagation()}
        />
      {:else}
        <span class="label">{n.name}</span>
      {/if}
    </div>
  {/each}
  {#if !rows.length}
    <div class="empty">{t('sidebar.empty')}</div>
  {/if}
</div>

{#if menu}
  <ContextMenu x={menu.x} y={menu.y} items={menu.items} onclose={() => ((menu = null), listEl.focus())} />
{/if}

<Modal open={!!confirmDelete} title={t('tree.deleteTitle')} width="420px" onclose={() => (confirmDelete = null)}>
  <p class="confirm">
    {t(confirmDelete?.kind === 'folder' ? 'tree.deleteFolderMessage' : 'tree.deleteRequestMessage', {
      name: confirmDelete?.name ?? '',
    })}
  </p>
  {#snippet footer()}
    <Button onclick={() => (confirmDelete = null)}>{t('common.cancel')}</Button>
    <Button variant="danger" onclick={doDelete}>{t('tree.delete')}</Button>
  {/snippet}
</Modal>

<style>
  .tree {
    min-height: 100%;
    padding: 6px 0;
  }
  .tree:focus-visible {
    outline: none;
  }
  .row {
    display: flex;
    align-items: center;
    gap: 4px;
    height: 24px;
    padding-right: 8px;
    white-space: nowrap;
    cursor: default;
  }
  .row:hover {
    background: var(--bg-hover);
  }
  .row.selected {
    background: var(--bg-active);
  }
  .tree:focus-within .row.selected {
    background: var(--accent);
    color: var(--accent-text);
  }
  .tree:focus-within .row.selected .method {
    color: inherit;
  }
  .broken .label {
    color: var(--danger);
  }
  .chevron {
    flex: none;
    width: 12px;
    font-size: 10px;
    color: var(--text-muted);
    text-align: center;
    transition: transform 0.1s;
  }
  .chevron.open {
    transform: rotate(90deg);
  }
  .tree:focus-within .row.selected .chevron {
    color: inherit;
  }
  .icon {
    font-size: 12px;
  }
  .label {
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .edit {
    flex: 1;
    min-width: 0;
    padding: 0 4px;
    border: 1px solid var(--accent);
    border-radius: 3px;
    background: var(--bg);
    color: var(--text);
  }
  .method {
    flex: none;
    min-width: 34px;
    font-family: var(--font-code);
    font-size: 10px;
    font-weight: 700;
    text-align: right;
    margin-right: 2px;
  }
  .m-get { color: var(--method-get); }
  .m-post { color: var(--method-post); }
  .m-put { color: var(--method-put); }
  .m-patch { color: var(--method-patch); }
  .m-delete { color: var(--method-delete); }
  .m-head { color: var(--method-head); }
  .m-options { color: var(--method-options); }
  .empty {
    padding: 24px 12px;
    text-align: center;
    color: var(--text-muted);
  }
  .confirm {
    margin: 0;
  }
</style>
