<script lang="ts" module>
  export interface MenuItem {
    label?: string
    action?: () => void
    danger?: boolean
    separator?: boolean
  }
</script>

<script lang="ts">
  interface Props {
    x: number
    y: number
    items: MenuItem[]
    onclose: () => void
  }
  let { x, y, items, onclose }: Props = $props()

  let el: HTMLElement | undefined = $state()
  let pos = $state({ left: 0, top: 0 })

  // keep the menu inside the window
  $effect(() => {
    if (!el) return
    const r = el.getBoundingClientRect()
    pos = {
      left: Math.max(4, Math.min(x, window.innerWidth - r.width - 4)),
      top: Math.max(4, Math.min(y, window.innerHeight - r.height - 4)),
    }
  })

  function run(item: MenuItem) {
    onclose()
    item.action?.()
  }

  function onpointerdown(e: PointerEvent) {
    if (el && !el.contains(e.target as Node)) onclose()
  }

  function onkeydown(e: KeyboardEvent) {
    if (e.key === 'Escape') {
      e.preventDefault()
      onclose()
    }
  }
</script>

<svelte:window {onpointerdown} {onkeydown} onblur={onclose} onresize={onclose} />

<div class="menu" role="menu" bind:this={el} style:left="{pos.left}px" style:top="{pos.top}px">
  {#each items as item, i (i)}
    {#if item.separator}
      <div class="sep"></div>
    {:else}
      <button role="menuitem" class="item" class:danger={item.danger} onclick={() => run(item)}>{item.label}</button>
    {/if}
  {/each}
</div>

<style>
  .menu {
    position: fixed;
    z-index: 90;
    min-width: 200px;
    padding: 4px;
    border: 1px solid var(--border);
    border-radius: var(--radius);
    background: var(--bg-elevated);
    box-shadow: var(--shadow);
  }
  .item {
    display: block;
    width: 100%;
    padding: 4px 10px;
    border: none;
    border-radius: 4px;
    background: none;
    text-align: left;
    white-space: nowrap;
    cursor: default;
  }
  .item:hover {
    background: var(--accent);
    color: var(--accent-text);
  }
  .danger {
    color: var(--danger);
  }
  .sep {
    height: 1px;
    margin: 4px 0;
    background: var(--border);
  }
</style>
