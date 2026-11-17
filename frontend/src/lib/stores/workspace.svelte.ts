import * as App from '../../../wailsjs/go/main/App'
import type { model, settings } from '../../../wailsjs/go/models'
import { showToast } from './toast.svelte'
import { errorText } from '../util/errors'

const hasBackend = () => !!(window as any).go

export const ws = $state({
  projects: [] as model.ProjectInfo[],
  activeProject: '',
  expanded: {} as Record<string, string[]>,
  sidebarHidden: false,
  sidebarWidth: 260,
  responseHeight: 320,
  tree: null as model.TreeNode | null,
})

export function activeProject(): model.ProjectInfo | undefined {
  return ws.projects.find((p) => p.id === ws.activeProject)
}

function fail(err: unknown) {
  showToast(errorText(err), 'error', 5000)
}

export async function initWorkspace() {
  if (!hasBackend()) return
  const w = await App.GetWorkspace()
  ws.activeProject = w.activeProject
  ws.expanded = w.expanded ?? {}
  ws.sidebarHidden = w.sidebarHidden
  ws.sidebarWidth = w.sidebarWidth
  ws.responseHeight = w.responseHeight
  ws.projects = (await App.ListProjects()) ?? []
  await reloadTree()
}

let saveTimer: ReturnType<typeof setTimeout> | undefined

/** Persist UI state (debounced). The project list is managed by the backend. */
export function saveWorkspace() {
  if (!hasBackend()) return
  clearTimeout(saveTimer)
  saveTimer = setTimeout(() => {
    const w: settings.Workspace = {
      projects: [],
      activeProject: ws.activeProject,
      expanded: $state.snapshot(ws.expanded),
      sidebarHidden: ws.sidebarHidden,
      sidebarWidth: ws.sidebarWidth,
      responseHeight: ws.responseHeight,
    }
    App.SaveWorkspace(w).catch(fail)
  }, 400)
}

export async function reloadTree() {
  if (!ws.activeProject) {
    ws.tree = null
    return
  }
  try {
    ws.tree = await App.GetTree(ws.activeProject)
  } catch (err) {
    ws.tree = null
    fail(err)
  }
}

export async function selectProject(id: string) {
  if (id === ws.activeProject) return
  ws.activeProject = id
  saveWorkspace()
  await reloadTree()
}

async function adopt(info: model.ProjectInfo | null) {
  if (!info) return
  ws.projects = (await App.ListProjects()) ?? []
  ws.activeProject = info.id
  await reloadTree()
}

export async function createProject(name: string, parentDir: string): Promise<boolean> {
  try {
    await adopt(await App.CreateProject(name, parentDir))
    return true
  } catch (err) {
    fail(err)
    return false
  }
}

export async function openProjectDialog() {
  try {
    await adopt(await App.OpenProjectDialog())
  } catch (err) {
    fail(err)
  }
}

export async function closeProject(id: string) {
  try {
    await App.CloseProject(id)
    const w = await App.GetWorkspace()
    ws.projects = (await App.ListProjects()) ?? []
    ws.activeProject = w.activeProject
    delete ws.expanded[id]
    await reloadTree()
  } catch (err) {
    fail(err)
  }
}

export function defaultProjectsDir(): Promise<string> {
  return hasBackend() ? App.DefaultProjectsDir() : Promise.resolve('')
}

/** Native folder picker; returns '' when cancelled. */
export async function pickDirectory(defaultDir: string): Promise<string> {
  try {
    return await App.PickDirectory(defaultDir)
  } catch (err) {
    fail(err)
    return ''
  }
}
