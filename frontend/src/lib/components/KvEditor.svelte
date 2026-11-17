<script lang="ts">
  import { t } from '../i18n/index.svelte'
  import VarInput from './VarInput.svelte'
  import { fromBulk, toBulk, type Row } from '../util/kv'

  interface Props {
    rows?: Row[]
    /** Fixed names (path params): no checkbox, delete, new rows, reordering or bulk edit. */
    fixed?: boolean
    allowBare?: boolean
    names?: string[]
    valuesFor?: (name: string) => string[]
    /** Multipart parts: text/file switch, file picker, Content-Type instead of description; no bulk edit. */
    multipart?: boolean
    onpick?: () => Promise<string>
  }
  let {
    rows = $bindable(),
    fixed = false,
    allowBare = false,
    names,
    valuesFor,
    multipart = false,
    onpick,
  }: Props = $props()

  const uid = $props.id()
  const ghost: Row = $derived(
    multipart ? { name: '', value: '', kind: 'text', enabled: true } : { name: '', value: '', enabled: true },
  )
  const third = $derived(multipart ? 'contentType' : 'description')
  // The ghost row shares the index key with the row it becomes, so focus survives the first keystroke.
  const list = $derived(rows ?? [])
  const shown = $derived(fixed ? list : [...list, ghost])

  let bulk = $state(false)
  let bulkText = $state('')

  function set(i: number, field: 'name' | 'value' | 'description' | 'contentType' | 'path', v: string) {
    if (!rows || i === rows.length) {
      // Reassigned (not pushed) so it reaches the parent even when it had no array yet.
      rows = [...list, { ...ghost, [field]: v }]
      return
    }
    // Empty optional fields are dropped so the draft matches the backend (omitempty) and stays clean.
    if (field !== 'name' && field !== 'value' && !v) delete rows[i][field]
    else rows[i][field] = v
    if (field === 'value' && v) delete rows[i].bare
  }

  function setKind(i: number, kind: string) {
    if (i === list.length) rows = [...list, { ...ghost, kind }]
    else rows![i].kind = kind
  }

  async function pick(i: number) {
    const f = await onpick?.()
    if (f) set(i, 'path', f)
  }

  function toggleBulk() {
    if (!bulk) bulkText = toBulk(list)
    bulk = !bulk
  }

  // Drag & drop by the handle; drop before/after the hovered row.
  let from = $state(-1)
  let over = $state<{ i: number; after: boolean } | null>(null)

  function dragStart(e: DragEvent, i: number) {
    from = i
    e.dataTransfer!.effectAllowed = 'move'
    e.dataTransfer!.setData('text/plain', String(i))
    const row = (e.target as HTMLElement).closest('.row')
    if (row) e.dataTransfer!.setDragImage(row, 8, 12)
  }

  function dragOver(e: DragEvent, i: number) {
    if (from < 0 || i >= list.length) return
    e.preventDefault()
    const r = (e.currentTarget as HTMLElement).getBoundingClientRect()
    over = { i, after: e.clientY > r.top + r.height / 2 }
  }

  function drop(e: DragEvent) {
    e.preventDefault()
    if (rows && from >= 0 && over) {
      let to = over.i + (over.after ? 1 : 0)
      if (to > from) to--
      if (to !== from) {
        const [r] = rows.splice(from, 1)
        rows.splice(to, 0, r)
      }
    }
    dragEnd()
  }

  function dragEnd() {
    from = -1
    over = null
  }
</script>

<div class="kv">
  {#if bulk}
    <textarea
      class="bulk"
      spellcheck="false"
      placeholder={t('kv.bulkHint')}
      bind:value={bulkText}
      oninput={() => (rows = fromBulk(bulkText, list, allowBare))}
    ></textarea>
  {:else}
    <div class="row head" class:fixed>
      <span></span><span></span>
      <span>{t('kv.name')}</span><span>{t('kv.value')}</span>
      <span>{t(multipart ? 'kv.contentType' : 'kv.description')}</span><span></span>
    </div>
    {#each shown as row, i (i)}
      {@const isGhost = !fixed && i === list.length}
      <div
        class="row"
        class:fixed
        class:off={!isGhost && row.enabled === false}
        class:dragging={from === i}
        class:drop-before={over?.i === i && !over.after}
        class:drop-after={over?.i === i && over.after}
        role="listitem"
        ondragover={(e) => dragOver(e, i)}
        ondrop={drop}
      >
        {#if fixed || isGhost}
          <span></span><span></span>
        {:else}
          <span
            class="handle"
            draggable="true"
            role="button"
            tabindex="-1"
            title={t('kv.drag')}
            ondragstart={(e) => dragStart(e, i)}
            ondragend={dragEnd}>⋮⋮</span
          >
          <input type="checkbox" bind:checked={row.enabled} />
        {/if}
        {#if fixed}
          <span class="fixed-name">{row.name}</span>
        {:else}
          <VarInput
            compact
            value={row.name}
            list={names ? `${uid}-names` : undefined}
            placeholder={isGhost ? t('kv.name') : ''}
            oninput={(v) => set(i, 'name', v)}
          />
        {/if}
        <div class="value">
          {#if multipart}
            <select class="kind" value={row.kind ?? 'text'} onchange={(e) => setKind(i, e.currentTarget.value)}>
              <option value="text">{t('kv.kindText')}</option>
              <option value="file">{t('kv.kindFile')}</option>
            </select>
          {/if}
          {#if multipart && row.kind === 'file'}
            <button class="file" title={row.path} onclick={() => pick(i)}>
              {row.path || t('kv.pickFile')}
            </button>
          {:else}
            <VarInput
              compact
              value={row.value ?? ''}
              list={valuesFor && valuesFor(row.name).length ? `${uid}-v${i}` : undefined}
              placeholder={isGhost ? t('kv.value') : ''}
              oninput={(v) => set(i, 'value', v)}
            />
          {/if}
        </div>
        <input
          class="desc"
          value={row[third] ?? ''}
          placeholder={isGhost ? t(multipart ? 'kv.contentType' : 'kv.description') : ''}
          oninput={(e) => set(i, third, e.currentTarget.value)}
        />
        {#if fixed || isGhost}
          <span></span>
        {:else}
          <button class="del" title={t('kv.delete')} onclick={() => rows?.splice(i, 1)}>×</button>
        {/if}
        {#if valuesFor && valuesFor(row.name).length}
          <datalist id="{uid}-v{i}">
            {#each valuesFor(row.name) as v (v)}<option value={v}></option>{/each}
          </datalist>
        {/if}
      </div>
    {/each}
    {#if names}
      <datalist id="{uid}-names">
        {#each names as n (n)}<option value={n}></option>{/each}
      </datalist>
    {/if}
  {/if}
  {#if !fixed && !multipart}
    <div class="tools">
      <button class="link" onclick={toggleBulk}>{bulk ? t('kv.table') : t('kv.bulk')}</button>
    </div>
  {/if}
</div>

<style>
  .kv {
    display: flex;
    flex-direction: column;
  }
  .row {
    display: grid;
    grid-template-columns: 16px 20px minmax(80px, 1fr) minmax(120px, 2fr) minmax(80px, 1fr) 22px;
    align-items: center;
    gap: 2px;
    border-bottom: 1px solid var(--border);
    position: relative;
  }
  .row.head {
    color: var(--text-muted);
    font-size: 11px;
    padding: 2px 0;
  }
  .row.head span {
    padding-left: 6px;
  }
  .row.off :global(.mirror),
  .row.off .desc {
    opacity: 0.45;
  }
  .row.dragging {
    opacity: 0.4;
  }
  .row.drop-before::before,
  .row.drop-after::after {
    content: '';
    position: absolute;
    left: 0;
    right: 0;
    height: 2px;
    background: var(--accent);
  }
  .row.drop-before::before {
    top: -1px;
  }
  .row.drop-after::after {
    bottom: -1px;
  }
  .row :global(.var-input.compact:focus-within),
  .desc:focus {
    border-color: var(--accent);
  }
  .value {
    display: flex;
    align-items: center;
    min-width: 0;
  }
  .kind {
    flex: none;
    height: 22px;
    border: 0;
    background: none;
    color: var(--text-muted);
    font: inherit;
    font-size: 11px;
  }
  .file {
    flex: 1;
    min-width: 0;
    height: 22px;
    padding: 0 6px;
    overflow: hidden;
    border: 1px dashed var(--border);
    border-radius: 4px;
    background: none;
    color: var(--text);
    font-family: var(--font-code);
    font-size: var(--font-size-code);
    text-align: left;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .handle {
    color: var(--text-muted);
    font-size: 10px;
    letter-spacing: -2px;
    text-align: center;
    cursor: grab;
    visibility: hidden;
  }
  .row:hover .handle {
    visibility: visible;
  }
  .fixed-name {
    padding: 0 6px;
    font-family: var(--font-code);
    font-size: var(--font-size-code);
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .desc {
    height: 24px;
    min-width: 0;
    padding: 0 6px;
    border: 1px solid transparent;
    border-radius: 4px;
    outline: none;
    background: transparent;
    color: var(--text-muted);
    font: inherit;
  }
  .del {
    border: 0;
    background: none;
    color: var(--text-muted);
    font-size: 15px;
    visibility: hidden;
  }
  .row:hover .del {
    visibility: visible;
  }
  .del:hover {
    color: var(--danger);
  }
  .bulk {
    min-height: 160px;
    resize: vertical;
    padding: 6px 8px;
    border: 1px solid var(--border);
    border-radius: 4px;
    background: var(--bg);
    color: var(--text);
    font-family: var(--font-code);
    font-size: var(--font-size-code);
    outline: none;
  }
  .bulk:focus {
    border-color: var(--accent);
  }
  .tools {
    display: flex;
    justify-content: flex-end;
    padding-top: 4px;
  }
  .link {
    border: 0;
    background: none;
    color: var(--accent);
    font: inherit;
    font-size: 12px;
  }
</style>
