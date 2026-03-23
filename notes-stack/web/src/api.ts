import type { Note, NoteDraft } from './types'

const apiBaseUrl = import.meta.env.VITE_API_BASE_URL ?? '/api'

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${apiBaseUrl}${path}`, {
    headers: {
      'Content-Type': 'application/json',
      ...(init?.headers ?? {}),
    },
    ...init,
  })

  if (!response.ok) {
    const payload = (await response.json().catch(() => null)) as
      | { errors?: Record<string, string[]>; title?: string }
      | null

    const validationMessage = payload?.errors
      ? Object.values(payload.errors).flat().join(' ')
      : null

    throw new Error(validationMessage ?? payload?.title ?? 'Request failed.')
  }

  if (response.status === 204) {
    return undefined as T
  }

  return (await response.json()) as T
}

export const notesApi = {
  list: () => request<Note[]>('/notes'),
  create: (draft: NoteDraft) =>
    request<Note>('/notes', {
      method: 'POST',
      body: JSON.stringify(draft),
    }),
  update: (id: number, draft: NoteDraft) =>
    request<Note>(`/notes/${id}`, {
      method: 'PUT',
      body: JSON.stringify(draft),
    }),
  remove: (id: number) =>
    request<void>(`/notes/${id}`, {
      method: 'DELETE',
    }),
}
