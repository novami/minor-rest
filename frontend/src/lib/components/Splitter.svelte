<script lang="ts">
  /** Drag handle that resizes an adjacent pane. `size` is bindable (px). */
  interface Props {
    size: number
    direction: 'horizontal' | 'vertical' // horizontal = resizes width, vertical = height
    min?: number
    max?: number
    invert?: boolean // true when the resized pane is after the handle
  }
  let { size = $bindable(), direction, min = 120, max = 2000, invert = false }: Props = $props()

  function onpointerdown(e: PointerEvent) {
    const el = e.currentTarget as HTMLElement
    el.setPointerCapture(e.pointerId)
    const start = direction === 'horizontal' ? e.clientX : e.clientY
    const startSize = size
    const move = (ev: PointerEvent) => {
      const pos = direction === 'horizontal' ? ev.clientX : ev.clientY
      const delta = (pos - start) * (invert ? -1 : 1)
      size = Math.min(max, Math.max(min, startSize + delta))
    }
    const up = () => {
      el.removeEventListener('pointermove', move)
      el.removeEventListener('pointerup', up)
    }
    el.addEventListener('pointermove', move)
    el.addEventListener('pointerup', up)
  }
</script>

<!-- svelte-ignore a11y_no_static_element_interactions -->
<div class="splitter {direction}" {onpointerdown}></div>

<style>
  .splitter {
    flex: none;
    background: var(--border);
    position: relative;
  }
  .splitter::after {
    content: '';
    position: absolute;
    inset: -3px;
  }
  .horizontal {
    width: 1px;
    cursor: col-resize;
  }
  .vertical {
    height: 1px;
    cursor: row-resize;
  }
</style>
