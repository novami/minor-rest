export type ToastKind = 'info' | 'success' | 'error'
export interface Toast {
  id: number
  text: string
  kind: ToastKind
}

let nextId = 1
export const toasts = $state<Toast[]>([])

export function showToast(text: string, kind: ToastKind = 'info', ms = 3000) {
  const id = nextId++
  toasts.push({ id, text, kind })
  setTimeout(() => dismissToast(id), ms)
}

export function dismissToast(id: number) {
  const i = toasts.findIndex((t) => t.id === id)
  if (i >= 0) toasts.splice(i, 1)
}
