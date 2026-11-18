import * as App from '../../../wailsjs/go/main/App'
import type { run } from '../../../wailsjs/go/models'
import { errorText } from '../util/errors'
import type { Tab } from './tabs.svelte'

export interface Run {
  runID: string
  running: boolean
  result?: run.Result
  body?: run.BodyView
  error?: string // localized text (send failure, body load failure)
}

/** Last run per tab (tab ID = request ID); in memory only. */
export const runs = $state<Record<string, Run>>({})

export async function send(tab: Tab) {
  if (runs[tab.id]?.running) return
  const runID = crypto.randomUUID()
  runs[tab.id] = { runID, running: true }
  const current = () => (runs[tab.id]?.runID === runID ? runs[tab.id] : undefined)
  try {
    const result = await App.Send({
      runID,
      projectID: tab.projectID,
      rel: tab.rel,
      request: $state.snapshot(tab.draft),
    } as run.Input)
    const r = current()
    if (!r) return
    r.result = result
    if (!result.error) r.body = await App.GetRunBody(runID, true)
  } catch (err) {
    const r = current()
    if (r) r.error = errorText(err)
  } finally {
    const r = current()
    if (r) r.running = false
  }
}

export function cancel(tab: Tab) {
  const r = runs[tab.id]
  if (r?.running) App.Cancel(r.runID)
}
