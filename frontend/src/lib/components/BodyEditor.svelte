<script lang="ts">
  import { t } from '../i18n/index.svelte'
  import * as Backend from '../../../wailsjs/go/main/App'
  import type { model } from '../../../wailsjs/go/models'
  import CodeEditor, { type Lang } from './CodeEditor.svelte'
  import KvEditor from './KvEditor.svelte'
  import Button from './Button.svelte'
  import { showToast } from '../stores/toast.svelte'
  import { errorText } from '../util/errors'

  interface Props {
    body: model.Body
    projectID: string
  }
  let { body = $bindable(), projectID }: Props = $props()

  const types = ['none', 'json', 'xml', 'text', 'html', 'form-urlencoded', 'multipart', 'binary']
  const langs: Record<string, Lang> = { json: 'json', xml: 'xml', html: 'html', text: 'text' }
  const lang = $derived(langs[body.type])

  // Validation only warns. {{vars}} are masked by a same-length number so `{"id": {{id}}}` passes;
  // formatting itself is done by the backend (FormatJSON), never JSON.parse/stringify.
  const jsonWarning = $derived.by(() => {
    if (body.type !== 'json' || !body.raw?.trim()) return ''
    try {
      JSON.parse(body.raw.replace(/\\?\{\{[^{}]*\}\}/g, (m) => '1'.padEnd(m.length)))
      return ''
    } catch (e) {
      return e instanceof Error ? e.message : String(e)
    }
  })

  async function format() {
    try {
      body.raw = await Backend.FormatJSON(body.raw ?? '')
    } catch (e) {
      showToast(errorText(e), 'error')
    }
  }

  async function pick(): Promise<string> {
    try {
      return await Backend.PickFile(projectID)
    } catch (e) {
      showToast(errorText(e), 'error')
      return ''
    }
  }

  async function pickBinary() {
    const f = await pick()
    if (f) body.binaryPath = f
  }
</script>

<div class="body-editor">
  <div class="types">
    {#each types as ty (ty)}
      <label class:active={body.type === ty}>
        <input type="radio" name="body-type" value={ty} bind:group={body.type} />
        {t(`body.type.${ty}`)}
      </label>
    {/each}
    {#if body.type === 'json'}
      <span class="spacer"></span>
      <Button variant="ghost" onclick={format}>{t('body.format')}</Button>
    {/if}
  </div>

  {#if lang}
    <div class="code">
      <CodeEditor bind:value={() => body.raw ?? '', (v) => (body.raw = v)} {lang} />
    </div>
    {#if jsonWarning}
      <div class="warning" title={jsonWarning}>⚠ {t('body.invalidJson')}: {jsonWarning}</div>
    {/if}
  {:else if body.type === 'form-urlencoded'}
    <KvEditor bind:rows={body.form} />
  {:else if body.type === 'multipart'}
    <KvEditor bind:rows={body.multipart} multipart onpick={pick} />
  {:else if body.type === 'binary'}
    <div class="binary">
      <Button onclick={pickBinary}>{t('kv.pickFile')}</Button>
      {#if body.binaryPath}
        <span class="path" title={body.binaryPath}>{body.binaryPath}</span>
        <button class="clear" title={t('kv.delete')} onclick={() => delete body.binaryPath}>×</button>
      {/if}
    </div>
  {:else}
    <div class="none">{t('body.none')}</div>
  {/if}
</div>

<style>
  .body-editor {
    display: flex;
    flex-direction: column;
    gap: 6px;
    height: 100%;
    min-height: 0;
  }
  .types {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 2px 10px;
    font-size: 12px;
  }
  .types label {
    display: inline-flex;
    align-items: center;
    gap: 3px;
    color: var(--text-muted);
  }
  .types label.active {
    color: var(--text);
  }
  .spacer {
    flex: 1;
  }
  .code {
    flex: 1;
    min-height: 120px;
  }
  .warning {
    color: var(--status-4xx);
    font-size: 12px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .binary {
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .path {
    min-width: 0;
    overflow: hidden;
    font-family: var(--font-code);
    font-size: var(--font-size-code);
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .clear {
    border: 0;
    background: none;
    color: var(--text-muted);
    font-size: 15px;
  }
  .none {
    padding: 16px 0;
    color: var(--text-muted);
  }
</style>
