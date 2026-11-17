<script lang="ts" module>
  export interface Token {
    text: string
    kind: '' | 'var' | 'dyn'
  }

  /** Splits text into plain parts and {{variables}}; `\{{` is an escape, not a variable. */
  export function tokenize(s: string): Token[] {
    const out: Token[] = []
    const re = /(\\?)\{\{\s*([^{}]*?)\s*\}\}/g
    let last = 0
    for (let m; (m = re.exec(s)); ) {
      if (m[1]) continue
      if (m.index > last) out.push({ text: s.slice(last, m.index), kind: '' })
      out.push({ text: m[0], kind: m[2].startsWith('$') ? 'dyn' : 'var' })
      last = m.index + m[0].length
    }
    if (last < s.length) out.push({ text: s.slice(last), kind: '' })
    return out
  }
</script>

<script lang="ts">
  interface Props {
    value: string
    placeholder?: string
    oninput?: (value: string) => void
    onkeydown?: (e: KeyboardEvent) => void
    onpaste?: (e: ClipboardEvent) => void
    el?: HTMLInputElement
    list?: string
    compact?: boolean
  }
  let {
    value = $bindable(''),
    placeholder = '',
    oninput,
    onkeydown,
    onpaste,
    el = $bindable(),
    list,
    compact = false,
  }: Props = $props()

  let mirror: HTMLDivElement
  const tokens = $derived(tokenize(value))

  function sync() {
    if (mirror && el) mirror.scrollLeft = el.scrollLeft
  }

  function handleInput() {
    value = el!.value
    oninput?.(value)
    sync()
  }
</script>

<div class="var-input" class:compact>
  <div class="mirror" bind:this={mirror} aria-hidden="true">
    {#each tokens as tok, i (i)}<span class={tok.kind}>{tok.text}</span>{/each}
  </div>
  <input
    bind:this={el}
    {value}
    {placeholder}
    {list}
    spellcheck="false"
    autocomplete="off"
    autocapitalize="off"
    oninput={handleInput}
    onscroll={sync}
    onkeyup={sync}
    onclick={sync}
    {onkeydown}
    {onpaste}
  />
</div>

<style>
  .var-input {
    position: relative;
    flex: 1;
    min-width: 0;
    height: 28px;
    border: 1px solid var(--border);
    border-radius: 4px;
    background: var(--bg);
  }
  .var-input.compact {
    height: 24px;
    border-color: transparent;
    background: transparent;
  }
  .var-input.compact .mirror,
  .var-input.compact input {
    padding: 0 6px;
    line-height: 22px;
  }
  .var-input:focus-within {
    border-color: var(--accent);
  }
  .mirror,
  input {
    position: absolute;
    inset: 0;
    padding: 0 8px;
    font-family: var(--font-code);
    font-size: var(--font-size-code);
    line-height: 26px;
    white-space: pre;
    letter-spacing: normal;
  }
  .mirror {
    overflow: hidden;
    color: var(--text);
    pointer-events: none;
  }
  input {
    width: 100%;
    border: 0;
    outline: none;
    background: transparent;
    color: transparent;
    caret-color: var(--text);
  }
  input::placeholder {
    color: var(--text-muted);
  }
  input::selection {
    background: var(--selection, rgba(100, 150, 255, 0.35));
    color: transparent;
  }
  .var {
    color: var(--var-known);
  }
  .dyn {
    color: var(--var-dynamic);
  }
</style>
