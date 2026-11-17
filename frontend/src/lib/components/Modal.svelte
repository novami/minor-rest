<script lang="ts">
  import type { Snippet } from 'svelte'
  import { t } from '../i18n/index.svelte'

  interface Props {
    open: boolean
    title: string
    width?: string
    onclose: () => void
    children: Snippet
    footer?: Snippet
  }
  let { open, title, width = '520px', onclose, children, footer }: Props = $props()

  function onkeydown(e: KeyboardEvent) {
    if (open && e.key === 'Escape') {
      e.preventDefault()
      onclose()
    }
  }
</script>

<svelte:window {onkeydown} />

{#if open}
  <!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
  <div class="backdrop" onclick={(e) => e.target === e.currentTarget && onclose()}>
    <div class="modal" style:width role="dialog" aria-modal="true" aria-label={title}>
      <header>
        <h2>{title}</h2>
        <button class="close" title={t('common.close')} onclick={onclose}>×</button>
      </header>
      <div class="body">{@render children()}</div>
      {#if footer}
        <footer>{@render footer()}</footer>
      {/if}
    </div>
  </div>
{/if}

<style>
  .backdrop {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.3);
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 20px;
    z-index: 100;
  }
  .modal {
    max-width: calc(100vw - 40px);
    max-height: 80vh;
    display: flex;
    flex-direction: column;
    background: var(--bg-elevated);
    border: 1px solid var(--border);
    border-radius: 10px;
    box-shadow: var(--shadow);
  }
  header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 10px 14px;
    border-bottom: 1px solid var(--border);
  }
  h2 {
    margin: 0;
    font-size: 1em;
    font-weight: 600;
  }
  .close {
    border: none;
    background: none;
    font-size: 18px;
    color: var(--text-muted);
  }
  .body {
    padding: 14px;
    overflow: auto;
  }
  footer {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
    padding: 10px 14px;
    border-top: 1px solid var(--border);
  }
</style>
