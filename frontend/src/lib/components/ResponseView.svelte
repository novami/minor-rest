<script lang="ts">
  // Temporary response view (F4): status line + raw body. Full view comes in F5.
  import { t } from '../i18n/index.svelte'
  import { errorText } from '../util/errors'
  import type { Run } from '../stores/runs.svelte'

  let { run }: { run: Run } = $props()

  const res = $derived(run.result)
  const err = $derived(res?.error ? errorText(res.error.detail ? `${res.error.code}: ${res.error.detail}` : res.error.code) : run.error)

  function size(n: number): string {
    if (n < 1024) return `${n} B`
    if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`
    return `${(n / 1024 / 1024).toFixed(1)} MB`
  }
  function statusClass(s: number): string {
    return s >= 500 ? 's5' : s >= 400 ? 's4' : s >= 300 ? 's3' : 's2'
  }
</script>

<div class="response-view">
  {#if run.running}
    <div class="line muted">{t('response.sending')}</div>
  {:else if err}
    <div class="line error">{err}</div>
  {:else if res}
    <div class="line">
      <span class="status {statusClass(res.status)}">{res.status} {res.statusText}</span>
      <span class="muted">{res.proto}</span>
      <span class="muted">{Math.round(res.timing.totalMs)} ms</span>
      <span class="muted">{size(res.sizes.bodyDecoded)}</span>
    </div>
  {/if}
  {#if res && res.unresolved.length}
    <div class="line warn">{t('response.unresolved', { names: res.unresolved.join(', ') })}</div>
  {/if}
  {#if !run.running && res && !res.error}
    {#if res.truncated}<div class="line warn">{t('response.truncated')}</div>{/if}
    {#if res.isBinary}
      <div class="line muted">{t('response.binary', { size: size(res.sizes.bodyDecoded) })}</div>
    {:else if run.body}
      {#if run.body.partial}<div class="line warn">{t('response.partial', { size: size(run.body.size) })}</div>{/if}
      <pre class="body">{run.body.text}</pre>
    {/if}
  {/if}
</div>

<style>
  .response-view {
    height: 100%;
    display: flex;
    flex-direction: column;
    min-height: 0;
  }
  .line {
    flex: none;
    display: flex;
    gap: 12px;
    padding: 6px 12px;
    border-bottom: 1px solid var(--border);
  }
  .muted {
    color: var(--text-muted);
  }
  .error {
    color: var(--danger);
  }
  .warn {
    color: var(--method-post);
  }
  .status {
    font-weight: 600;
  }
  .s2 {
    color: var(--method-get);
  }
  .s3 {
    color: var(--method-put);
  }
  .s4 {
    color: var(--method-post);
  }
  .s5 {
    color: var(--danger);
  }
  .body {
    flex: 1;
    min-height: 0;
    margin: 0;
    padding: 8px 12px;
    overflow: auto;
    font-family: var(--font-code);
    font-size: var(--font-size-code);
    white-space: pre-wrap;
    word-break: break-word;
    user-select: text;
  }
</style>
