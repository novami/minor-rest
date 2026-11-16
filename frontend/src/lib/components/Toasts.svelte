<script lang="ts">
  import { toasts, dismissToast } from '../stores/toast.svelte'
</script>

<div class="toasts" aria-live="polite">
  {#each toasts as toast (toast.id)}
    <button class="toast {toast.kind}" onclick={() => dismissToast(toast.id)}>{toast.text}</button>
  {/each}
</div>

<style>
  .toasts {
    position: fixed;
    right: 16px;
    bottom: 16px;
    display: flex;
    flex-direction: column;
    gap: 8px;
    z-index: 200;
  }
  .toast {
    max-width: 360px;
    padding: 8px 12px;
    text-align: left;
    border: 1px solid var(--border);
    border-left: 4px solid var(--accent);
    border-radius: var(--radius);
    background: var(--bg-elevated);
    box-shadow: var(--shadow);
  }
  .success {
    border-left-color: var(--status-2xx);
  }
  .error {
    border-left-color: var(--danger);
  }
</style>
