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
    moveNode,
  } from '../stores/tree.svelte'
  import { fold } from '../util/text'

  interface Props {
    root: model.TreeNode
  }
  let { root }: Props = $props()

  interface Row {
    node: model.TreeNode
    depth: number
  }

  let query = $state('')
  const q = $derived(fold(query.trim()))

  function matches(n: model.TreeNode): boolean {
    if (fold(n.name).includes(q)) return true
    return n.kind === 'request' && (fold(n.url ?? '').includes(q) || fold(n.method ?? '').includes(q))
  }

  // visible nodes in display order; with a filter: matches, their ancestors, and whole subtrees of matching folders
  const rows = $derived.by(() => {
    const walk = (nodes: model.TreeNode[] | undefined, depth: number, all: boolean): Row[] => {
      const out: Row[] = []
      for (const node of nodes ?? []) {
        const self = !q || all || matches(node)
        if (node.kind !== 'folder') {
          if (self) out.push({ node, depth })
          continue
        }
        const sub = q || isExpanded(node.rel) ? walk(node.children, depth + 1, q ? self : false) : []
        if (self || sub.length) out.push({ node, depth }, ...sub)
      }
      return out
    }
    return walk(root.children, 0, false)
  })

  let listEl: HTMLElement

  // drag & drop
  type DropPos = 'before' | 'after' | 'into'
  let drag = $state<model.TreeNode | null>(null)
  let drop = $state<{ rel: string; pos: DropPos } | null>(null)
  let expandTimer: ReturnType<typeof setTimeout> | undefined
  let expandRel = ''

  function dropTarget(e: DragEvent, n: model.TreeNode): { rel: string; pos: DropPos } | null {
    if (!drag) return null
    const r = (e.currentTarget as HTMLElement).getBoundingClientRect()
    const y = (e.clientY - r.top) / r.height
    let t: { rel: string; pos: DropPos }
    if (n.kind === 'folder') {
      if (drag.kind === 'request') t = { rel: n.rel, pos: 'into' }
      else t = { rel: n.rel, pos: y < 0.25 ? 'before' : y > 0.75 && !isExpanded(n.rel) ? 'after' : 'into' }
    } else if (drag.kind === 'request') {
      t = { rel: n.rel, pos: y < 0.5 ? 'before' : 'after' }
    } else {
      t = { rel: parentOf(n.rel), pos: 'into' } // folder over a request: into that request's folder
    }
    if (t.rel === drag.rel && t.pos !== 'into') return null
    const dest = t.pos === 'into' ? t.rel : parentOf(t.rel)
    if (drag.kind === 'folder' && (dest === drag.rel || dest.startsWith(drag.rel + '/'))) return null
    return t
  }

  function setDrop(t: { rel: string; pos: DropPos } | null) {
    drop = t
    const rel = t?.pos === 'into' && t.rel && !isExpanded(t.rel) ? t.rel : ''
    if (rel === expandRel) return
    clearTimeout(expandTimer)
    expandRel = rel
    if (rel) expandTimer = setTimeout(() => setExpanded(rel, true), 700)
  }

  function ondragstart(e: DragEvent, n: model.TreeNode) {
    if (!e.dataTransfer) return
    e.dataTransfer.setData('text/plain', n.rel) // WebKit starts a drag only with data set
    e.dataTransfer.effectAllowed = 'move'
    drag = n
    select(n.rel)
  }

  function ondragover(e: DragEvent, n?: model.TreeNode) {
    if (!drag) return
    const t = n ? dropTarget(e, n) : { rel: '', pos: 'into' as DropPos }
    e.stopPropagation()
    setDrop(t)
    if (!t) return
    e.preventDefault()
    if (e.dataTransfer) e.dataTransfer.dropEffect = 'move'
  }

  function ondragleave(e: DragEvent) {
    if (!listEl.contains(e.relatedTarget as Node)) setDrop(null)
  }

  function ondrop(e: DragEvent) {
    e.preventDefault()
    e.stopPropagation()
    const d = drag
    const t = drop
    ondragend()
    if (!d || !t) return
    const parent = t.pos === 'into' ? t.rel : parentOf(t.rel)
    const sibs = (findNode(parent)?.children ?? []).filter((c) => c.kind === d.kind && c.rel !== d.rel)
    let index = sibs.length
    if (t.pos !== 'into') index = sibs.findIndex((c) => c.rel === t.rel) + (t.pos === 'after' ? 1 : 0)
    if (parent === parentOf(d.rel)) {
      const cur = (findNode(parent)?.children ?? []).filter((c) => c.kind === d.kind).findIndex((c) => c.rel === d.rel)
      if (cur === index) return
    }
    moveNode(d.rel, parent, index)
  }

  function ondragend() {
    drag = null
    setDrop(null)
  }

  function onSearchKey(e: KeyboardEvent) {
    if (e.key === 'Escape') {
      e.preventDefault()
      if (query) query = ''
      else listEl.focus()
    } else if (e.key === 'ArrowDown' || e.key === 'Enter') {
      e.preventDefault()
      if (rows.length && !rows.some((r) => r.node.rel === tree.selected)) select(rows[0].node.rel)
      listEl.focus()
    }
  }
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

<div class="search">
  <input
    type="search"
    bind:value={query}
    placeholder={t('tree.search')}
    spellcheck="false"
    onkeydown={onSearchKey}
  />
</div>
<!-- svelte-ignore a11y_no_noninteractive_tabindex -->
<div
  class="tree"
  class:drop-root={drop?.rel === '' && drop.pos === 'into'}
  role="tree"
  tabindex="0"
  bind:this={listEl}
  {onkeydown}
  oncontextmenu={(e) => oncontextmenu(e)}
  ondragover={(e) => ondragover(e)}
  {ondragleave}
  {ondrop}
>
  {#each rows as { node: n, depth } (n.rel)}
    <!-- keyboard is handled by the focusable tree container -->
    <!-- svelte-ignore a11y_click_events_have_key_events, a11y_interactive_supports_focus -->
    <div
      class="row"
      class:selected={n.rel === tree.selected}
      class:broken={!!n.error}
      class:dragging={drag?.rel === n.rel}
      class:drop-before={drop?.rel === n.rel && drop.pos === 'before'}
      class:drop-after={drop?.rel === n.rel && drop.pos === 'after'}
      class:drop-into={drop?.rel === n.rel && drop.pos === 'into'}
      draggable={!q && tree.editing !== n.rel}
      ondragstart={(e) => ondragstart(e, n)}
      ondragover={(e) => ondragover(e, n)}
      {ondragend}
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
    <div class="empty">{t(q ? 'tree.noMatches' : 'sidebar.empty')}</div>
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
  .search {
    position: sticky;
    top: 0;
    z-index: 1;
    padding: 6px 8px 0;
    background: var(--bg-sidebar);
  }
  .search input {
    width: 100%;
    height: 24px;
    padding: 0 6px;
    border: 1px solid var(--border);
    border-radius: 4px;
    background: var(--bg);
    color: var(--text);
  }
  .search input:focus {
    outline: none;
    border-color: var(--accent);
  }
  .tree {
    min-height: calc(100% - 30px);
    padding: 6px 0;
  }
  .tree.drop-root {
    outline: 1px solid var(--accent);
    outline-offset: -1px;
  }
  .row.dragging {
    opacity: 0.5;
  }
  .row.drop-before {
    box-shadow: inset 0 2px 0 var(--accent);
  }
  .row.drop-after {
    box-shadow: inset 0 -2px 0 var(--accent);
  }
  .row.drop-into {
    outline: 1px solid var(--accent);
    outline-offset: -1px;
    background: var(--bg-hover);
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
