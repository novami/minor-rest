import * as App from '../../../wailsjs/go/main/App'
import type { model } from '../../../wailsjs/go/models'
import { showToast } from './toast.svelte'
import { errorText } from '../util/errors'
import { ws, reloadTree, saveWorkspace, treeLoaded, closeProject } from './workspace.svelte'
import { findNode } from './tree.svelte'

export interface Tab {
  id: string // request ID – survives rename and move
  projectID: string
  rel: string
  draft: model.Request
  saved: string // JSON of the last loaded/saved state
  diskChanged?: model.Request // newer version on disk while the tab has local changes
}

export const tabs = $state({
  list: [] as Tab[],
  confirmClose: '', // ID of a dirty tab waiting for Save / Discard / Cancel
  confirmProject: '', // ID of a project with dirty tabs waiting for Save / Discard / Cancel
})

const restored = new Set<string>()

function fail(err: unknown) {
  showToast(errorText(err), 'error', 5000)
}

export const isDirty = (t: Tab) => JSON.stringify(t.draft) !== t.saved

export function projectTabs(): Tab[] {
  return tabs.list.filter((t) => t.projectID === ws.activeProject)
}

export function activeTab(): Tab | undefined {
  const id = ws.activeTab[ws.activeProject]
  return tabs.list.find((t) => t.id === id && t.projectID === ws.activeProject)
}

function findById(id: string, n: model.TreeNode | null = ws.tree): model.TreeNode | undefined {
  if (!n) return undefined
  if (n.kind === 'request' && n.id === id) return n
  for (const c of n.children ?? []) {
    const f = findById(id, c)
    if (f) return f
  }
  return undefined
}

/** Display name: current name from the tree (renames), else the loaded one. */
export function tabName(t: Tab): string {
  return (t.projectID === ws.activeProject && findById(t.id)?.name) || t.draft.name
}

function persist() {
  const pid = ws.activeProject
  if (!pid) return
  ws.tabs[pid] = projectTabs().map((t) => t.id)
  saveWorkspace()
}

export function activate(id: string) {
  ws.activeTab[ws.activeProject] = id
  persist()
}

async function load(pid: string, id: string, rel: string): Promise<Tab | undefined> {
  try {
    const r = await App.GetRequest(pid, rel)
    return { id, projectID: pid, rel, draft: r, saved: JSON.stringify(r) }
  } catch (err) {
    fail(err)
  }
}

export async function openTab(rel: string) {
  const pid = ws.activeProject
  const node = findNode(rel)
  if (!pid || node?.kind !== 'request' || !node.id) return
  if (!tabs.list.some((t) => t.id === node.id && t.projectID === pid)) {
    const tab = await load(pid, node.id, rel)
    if (!tab) return
    tabs.list.push(tab)
  }
  activate(node.id)
}

function remove(id: string) {
  const list = projectTabs()
  const i = list.findIndex((t) => t.id === id)
  if (i < 0) return
  tabs.list = tabs.list.filter((t) => t !== list[i])
  if (ws.activeTab[ws.activeProject] === id) {
    const next = list[i + 1] ?? list[i - 1]
    ws.activeTab[ws.activeProject] = next && next.id !== id ? next.id : ''
  }
  persist()
}

/** Close a tab; a dirty one first asks (see tabs.confirmClose). */
export function closeTab(id = ws.activeTab[ws.activeProject]) {
  const t = projectTabs().find((t) => t.id === id)
  if (!t) return
  if (isDirty(t)) tabs.confirmClose = id
  else remove(id)
}

export async function resolveClose(choice: 'save' | 'discard' | 'cancel') {
  const id = tabs.confirmClose
  tabs.confirmClose = ''
  if (choice === 'cancel') return
  if (choice === 'save' && !(await saveTab(id))) return
  remove(id)
}

export function saveTab(id = ws.activeTab[ws.activeProject]): Promise<boolean> {
  const t = projectTabs().find((t) => t.id === id)
  return t ? save(t) : Promise.resolve(false)
}

async function save(t: Tab, reload = true): Promise<boolean> {
  try {
    const r = $state.snapshot(t.draft) as model.Request
    await App.SaveRequest(t.projectID, t.rel, r)
    t.saved = JSON.stringify(r)
    t.diskChanged = undefined
    if (reload) await reloadTree() // method and URL are shown/searched in the tree
    return true
  } catch (err) {
    fail(err)
    return false
  }
}

/** Save all dirty tabs (of one project, or all); false when any save failed. */
export async function saveAll(projectID?: string): Promise<boolean> {
  let ok = true
  for (const t of tabs.list.filter((t) => isDirty(t) && (!projectID || t.projectID === projectID))) {
    ok = (await save(t, false)) && ok
  }
  await reloadTree()
  return ok
}

/** Close a project; with dirty tabs it first asks (see tabs.confirmProject). */
export function closeProjectSafe(id: string) {
  if (tabs.list.some((t) => t.projectID === id && isDirty(t))) tabs.confirmProject = id
  else closeProject(id)
}

export async function resolveCloseProject(choice: 'save' | 'discard' | 'cancel') {
  const id = tabs.confirmProject
  tabs.confirmProject = ''
  if (choice === 'cancel') return
  if (choice === 'save' && !(await saveAll(id))) return
  tabs.list = tabs.list.filter((t) => t.projectID !== id)
  await closeProject(id)
}

/** Window close → Save chosen in the native dialog: save everything, then quit. */
export async function saveAllAndQuit() {
  if (await saveAll()) App.Quit()
}

/** The request file changed on disk (not by us): reload a clean tab, offer a choice for a dirty one. */
export async function changedOnDisk(projectID: string, rel: string) {
  const t = tabs.list.find((t) => t.projectID === projectID && t.rel === rel)
  if (!t) return
  let r: model.Request
  try {
    r = await App.GetRequest(projectID, rel)
  } catch {
    return // deleted or moved – the tree sync handles it
  }
  const disk = JSON.stringify(r)
  if (disk === t.saved) {
    t.diskChanged = undefined
  } else if (isDirty(t)) {
    t.diskChanged = r
  } else {
    t.draft = r
    t.saved = disk
  }
}

export function reloadFromDisk(t: Tab) {
  if (!t.diskChanged) return
  t.draft = t.diskChanged
  t.saved = JSON.stringify(t.diskChanged)
  t.diskChanged = undefined
}

/** Keep local edits; the disk version becomes the baseline, so the tab stays dirty against it. */
export function keepMine(t: Tab) {
  if (!t.diskChanged) return
  t.saved = JSON.stringify(t.diskChanged)
  t.diskChanged = undefined
}

/** After a tree load: restore tabs of the project once, follow renames/moves, drop deleted clean tabs. */
async function syncWithTree() {
  const open = new Set(ws.projects.map((p) => p.id))
  tabs.list = tabs.list.filter((t) => open.has(t.projectID))
  const pid = ws.activeProject
  if (!pid || !ws.tree) return
  for (const t of projectTabs()) {
    const n = findById(t.id)
    if (n) t.rel = n.rel
    else if (!isDirty(t)) tabs.list = tabs.list.filter((x) => x !== t)
  }
  if (!restored.has(pid)) {
    restored.add(pid)
    for (const id of ws.tabs[pid] ?? []) {
      const n = findById(id)
      if (!n || tabs.list.some((t) => t.id === id && t.projectID === pid)) continue
      const tab = await load(pid, id, n.rel)
      if (tab) tabs.list.push(tab)
    }
  }
  const ids = projectTabs().map((t) => t.id)
  if (!ids.includes(ws.activeTab[pid])) ws.activeTab[pid] = ids[0] ?? ''
  persist()
}

treeLoaded.push(syncWithTree)

export const anyDirty = () => tabs.list.some(isDirty)
