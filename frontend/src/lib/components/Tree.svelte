<script lang="ts">
  import type { model } from '../../../wailsjs/go/models'
  import { t } from '../i18n/index.svelte'
  import Tree from './Tree.svelte'

  interface Props {
    nodes: model.TreeNode[]
    depth?: number
  }
  let { nodes, depth = 0 }: Props = $props()
</script>

<ul class="tree" role={depth === 0 ? 'tree' : 'group'}>
  {#each nodes as n (n.rel)}
    <li role="treeitem" aria-selected="false">
      <div class="row" class:broken={!!n.error} style:padding-left="{8 + depth * 14}px" title={n.error ? t(`errors.${n.error}`) : n.name}>
        {#if n.kind === 'folder'}
          <span class="icon">📁</span>
        {:else}
          <span class="method m-{(n.method ?? '').toLowerCase()}">{n.method}</span>
        {/if}
        <span class="label">{n.name}</span>
      </div>
      {#if n.children?.length}
        <Tree nodes={n.children} depth={depth + 1} />
      {/if}
    </li>
  {/each}
</ul>

<style>
  .tree {
    list-style: none;
    margin: 0;
    padding: 0;
  }
  .row {
    display: flex;
    align-items: center;
    gap: 6px;
    height: 24px;
    padding-right: 8px;
    white-space: nowrap;
  }
  .row:hover {
    background: var(--bg-hover);
  }
  .broken {
    color: var(--danger);
  }
  .icon {
    font-size: 12px;
  }
  .label {
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .method {
    flex: none;
    min-width: 34px;
    font-family: var(--font-code);
    font-size: 10px;
    font-weight: 700;
    text-align: right;
  }
  .m-get { color: var(--method-get); }
  .m-post { color: var(--method-post); }
  .m-put { color: var(--method-put); }
  .m-patch { color: var(--method-patch); }
  .m-delete { color: var(--method-delete); }
  .m-head { color: var(--method-head); }
  .m-options { color: var(--method-options); }
</style>
