import * as App from '../../../wailsjs/go/main/App'
import type { model } from '../../../wailsjs/go/models'
import { t } from '../i18n/index.svelte'
import { showToast } from './toast.svelte'
import { errorText } from '../util/errors'
import { ws, reloadTree, saveWorkspace } from './workspace.svelte'
import { openTab } from './tabs.svelte'

export const tree = $state({
  selected: '', // Rel of the selected node
  editing: '', // Rel of the node being renamed inline
})

function fail(err: unknown) {
  showToast(errorText(err), 'error', 5000)
}

const pid = () => ws.activeProject

export function parentOf(rel: string): string {
  const i = rel.lastIndexOf('/')
  return i < 0 ? '' : rel.slice(0, i)
}

export function findNode(rel: string, n: model.TreeNode | null = ws.tree): model.TreeNode | undefined {
  if (!n) return undefined
  if (n.rel === rel) return n
  for (const c of n.children ?? []) {
    const f = findNode(rel, c)
    if (f) return f
  }
  return undefined
}

export function isExpanded(rel: string): boolean {
  return ws.expanded[pid()]?.includes(rel) ?? false
}

export function setExpanded(rel: string, open: boolean) {
  const list = ws.expanded[pid()] ?? []
  const has = list.includes(rel)
  if (open === has) return
  ws.expanded[pid()] = open ? [...list, rel] : list.filter((r) => r !== rel)
  saveWorkspace()
}

/** Expand all ancestors so that the node is visible. */
function reveal(rel: string) {
  for (let p = parentOf(rel); p; p = parentOf(p)) setExpanded(p, true)
}

/** Folder for new items: the selected folder, the selected request's folder, or the root. */
export function targetFolder(): string {
  const n = findNode(tree.selected)
  if (!n || !tree.selected) return ''
  return n.kind === 'folder' ? n.rel : parentOf(n.rel)
}

/** Replace a renamed/moved rel prefix in expansion state and selection. */
function remap(from: string, to: string) {
  const map = (r: string) => (r === from ? to : r.startsWith(from + '/') ? to + r.slice(from.length) : r)
  const list = ws.expanded[pid()]
  if (list) ws.expanded[pid()] = list.map(map)
  tree.selected = map(tree.selected)
  saveWorkspace()
}

export async function createNode(kind: 'folder' | 'request', parent = targetFolder()) {
  if (!pid()) return
  try {
    const name = t(kind === 'folder' ? 'tree.newFolderName' : 'tree.newRequestName')
    const n = kind === 'folder' ? await App.CreateFolder(pid(), parent, name) : await App.CreateRequest(pid(), parent, name)
    if (parent) setExpanded(parent, true)
    await reloadTree()
    tree.selected = n.rel
    if (kind === 'request') await openTab(n.rel)
    tree.editing = n.rel
  } catch (err) {
    fail(err)
  }
}

export async function renameNode(rel: string, name: string) {
  tree.editing = ''
  const n = findNode(rel)
  if (!n || !name.trim() || name.trim() === n.name) return
  try {
    const res = await App.RenameNode(pid(), rel, name.trim())
    remap(rel, res.rel)
    await reloadTree()
  } catch (err) {
    fail(err)
  }
}

export async function duplicateNode(rel = tree.selected) {
  if (!rel) return
  try {
    const n = await App.DuplicateNode(pid(), rel, t('tree.copySuffix'))
    await reloadTree()
    tree.selected = n.rel
  } catch (err) {
    fail(err)
  }
}

export async function deleteNode(rel: string) {
  try {
    await App.DeleteNode(pid(), rel)
    const inside = (r: string) => r === rel || r.startsWith(rel + '/')
    const list = ws.expanded[pid()]
    if (list) ws.expanded[pid()] = list.filter((r) => !inside(r))
    if (inside(tree.selected)) tree.selected = parentOf(rel)
    saveWorkspace()
    await reloadTree()
  } catch (err) {
    fail(err)
  }
}

export async function moveNode(rel: string, targetParent: string, index: number) {
  try {
    const n = await App.MoveNode(pid(), rel, targetParent, index)
    remap(rel, n.rel)
    if (targetParent) setExpanded(targetParent, true)
    await reloadTree()
    reveal(n.rel)
  } catch (err) {
    fail(err)
  }
}

export async function revealInFinder(rel: string) {
  try {
    await App.RevealInFinder(pid(), rel)
  } catch (err) {
    fail(err)
  }
}
