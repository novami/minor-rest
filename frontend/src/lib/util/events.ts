import { EventsOnMultiple } from '../../../wailsjs/runtime/runtime'

/** Subscribe to a Wails event; returns an unsubscribe function. No-op outside Wails (plain Vite dev). */
export function onEvent(name: string, cb: (...data: any[]) => void): () => void {
  if (!(window as any).runtime) return () => {}
  // EventsOn in the generated runtime drops the unsubscribe function; EventsOnMultiple returns it.
  return EventsOnMultiple(name, cb, -1)
}

/** Subscribe to a native menu action (`menu:<action>`). */
export function onMenu(action: string, cb: () => void): () => void {
  return onEvent(`menu:${action}`, cb)
}
