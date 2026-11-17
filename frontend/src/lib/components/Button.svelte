<script lang="ts">
  import type { Snippet } from 'svelte'

  interface Props {
    variant?: 'default' | 'primary' | 'danger' | 'ghost'
    disabled?: boolean
    title?: string
    type?: 'button' | 'submit'
    form?: string
    onclick?: (e: MouseEvent) => void
    children: Snippet
  }
  let { variant = 'default', disabled = false, title, type = 'button', form, onclick, children }: Props = $props()
</script>

<button class="btn {variant}" {type} {form} {disabled} {title} {onclick}>
  {@render children()}
</button>

<style>
  .btn {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    height: 26px;
    padding: 0 12px;
    border: 1px solid var(--border);
    border-radius: var(--radius);
    background: var(--bg-elevated);
    cursor: default;
    white-space: nowrap;
  }
  .btn:hover:not(:disabled) {
    background: var(--bg-hover);
  }
  .btn:disabled {
    opacity: 0.5;
  }
  .primary {
    background: var(--accent);
    border-color: var(--accent);
    color: var(--accent-text);
  }
  .primary:hover:not(:disabled) {
    background: var(--accent);
    filter: brightness(1.08);
  }
  .danger {
    color: var(--danger);
  }
  .ghost {
    border-color: transparent;
    background: transparent;
  }
</style>
