<script lang="ts" module>
  export type Lang = 'json' | 'xml' | 'html' | 'markdown' | 'text'
</script>

<script lang="ts">
  import { onMount } from 'svelte'
  import { basicSetup } from 'codemirror'
  import { Compartment, EditorState, type Extension } from '@codemirror/state'
  import { Decoration, EditorView, MatchDecorator, ViewPlugin, type DecorationSet, type ViewUpdate } from '@codemirror/view'
  import { HighlightStyle, syntaxHighlighting } from '@codemirror/language'
  import { tags } from '@lezer/highlight'
  import { json } from '@codemirror/lang-json'
  import { xml } from '@codemirror/lang-xml'
  import { html } from '@codemirror/lang-html'
  import { markdown } from '@codemirror/lang-markdown'

  interface Props {
    value: string
    lang?: Lang
    readonly?: boolean
    oninput?: (value: string) => void
  }
  let { value = $bindable(''), lang = 'text', readonly = false, oninput }: Props = $props()

  let host: HTMLDivElement
  let view: EditorView | undefined
  const langC = new Compartment()
  const roC = new Compartment()

  const langExt = (l: Lang): Extension =>
    ({ json: json(), xml: xml(), html: html(), markdown: markdown(), text: [] })[l]

  // {{variables}} highlighted like in VarInput (`\{{` = escape).
  const varMatcher = new MatchDecorator({
    regexp: /(\\?)\{\{\s*([^{}]*?)\s*\}\}/g,
    decoration: (m) =>
      m[1] ? null : Decoration.mark({ class: m[2].startsWith('$') ? 'cm-var-dyn' : 'cm-var' }),
  })
  const vars = ViewPlugin.fromClass(
    class {
      decorations: DecorationSet
      constructor(v: EditorView) {
        this.decorations = varMatcher.createDeco(v)
      }
      update(u: ViewUpdate) {
        this.decorations = varMatcher.updateDeco(u, this.decorations)
      }
    },
    { decorations: (v) => v.decorations },
  )

  const highlight = HighlightStyle.define([
    { tag: [tags.string, tags.attributeValue], color: 'var(--code-string)' },
    { tag: [tags.number, tags.bool, tags.null, tags.atom], color: 'var(--code-number)' },
    { tag: [tags.propertyName, tags.attributeName], color: 'var(--code-property)' },
    { tag: [tags.tagName, tags.heading, tags.keyword], color: 'var(--code-keyword)' },
    { tag: [tags.comment, tags.meta], color: 'var(--text-muted)' },
    { tag: tags.strong, fontWeight: 'bold' },
    { tag: tags.emphasis, fontStyle: 'italic' },
  ])

  const theme = EditorView.theme({
    '&': { height: '100%', color: 'var(--text)', backgroundColor: 'var(--bg)', fontSize: 'var(--font-size-code)' },
    '&.cm-focused': { outline: 'none' },
    '.cm-scroller': { fontFamily: 'var(--font-code)', lineHeight: '1.5' },
    '.cm-content': { caretColor: 'var(--text)' },
    '.cm-cursor': { borderLeftColor: 'var(--text)' },
    '.cm-gutters': { backgroundColor: 'var(--bg)', color: 'var(--text-muted)', border: 'none' },
    '.cm-activeLine, .cm-activeLineGutter': { backgroundColor: 'var(--bg-hover)' },
    '&.cm-focused .cm-selectionBackground, .cm-selectionBackground, ::selection': {
      backgroundColor: 'var(--bg-active) !important',
    },
    '.cm-matchingBracket': { backgroundColor: 'var(--bg-active)', outline: 'none' },
    '.cm-panels': { backgroundColor: 'var(--bg-sidebar)', color: 'var(--text)' },
    '.cm-panels input, .cm-panels button': { font: 'inherit' },
    '.cm-tooltip': { backgroundColor: 'var(--bg-elevated)', border: '1px solid var(--border)' },
    '.cm-var': { color: 'var(--var-known)' },
    '.cm-var-dyn': { color: 'var(--var-dynamic)' },
  })

  onMount(() => {
    view = new EditorView({
      parent: host,
      state: EditorState.create({
        doc: value,
        extensions: [
          basicSetup,
          theme,
          syntaxHighlighting(highlight),
          vars,
          EditorView.lineWrapping,
          langC.of(langExt(lang)),
          roC.of([EditorState.readOnly.of(readonly), EditorView.editable.of(!readonly)]),
          EditorView.updateListener.of((u) => {
            if (!u.docChanged) return
            value = u.state.doc.toString()
            oninput?.(value)
          }),
        ],
      }),
    })
    return () => view?.destroy()
  })

  // External changes (format, another source) replace the document.
  $effect(() => {
    const v = value
    if (view && v !== view.state.doc.toString()) {
      view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: v } })
    }
  })
  $effect(() => {
    view?.dispatch({ effects: langC.reconfigure(langExt(lang)) })
  })
  $effect(() => {
    view?.dispatch({
      effects: roC.reconfigure([EditorState.readOnly.of(readonly), EditorView.editable.of(!readonly)]),
    })
  })
</script>

<div class="code-editor" bind:this={host}></div>

<style>
  .code-editor {
    height: 100%;
    min-height: 0;
    overflow: hidden;
    border: 1px solid var(--border);
    border-radius: 4px;
  }
  .code-editor:focus-within {
    border-color: var(--accent);
  }
</style>
