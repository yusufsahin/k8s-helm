import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useState,
  type PropsWithChildren,
} from 'react'
import { notesApi } from './api'
import type { Note, NoteDraft } from './types'

type NotesContextValue = {
  notes: Note[]
  draft: NoteDraft
  error: string | null
  isLoading: boolean
  isSaving: boolean
  selectedId: number | null
  setDraft: (draft: Partial<NoteDraft>) => void
  selectNote: (id: number) => void
  createNote: () => Promise<void>
  updateNote: () => Promise<void>
  removeNote: () => Promise<void>
  resetDraft: () => void
}

const initialDraft: NoteDraft = {
  title: '',
  description: '',
}

const NotesContext = createContext<NotesContextValue | null>(null)

export function NotesProvider({ children }: PropsWithChildren) {
  const [notes, setNotes] = useState<Note[]>([])
  const [draft, setDraftState] = useState<NoteDraft>(initialDraft)
  const [error, setError] = useState<string | null>(null)
  const [isLoading, setIsLoading] = useState(true)
  const [isSaving, setIsSaving] = useState(false)
  const [selectedId, setSelectedId] = useState<number | null>(null)

  useEffect(() => {
    let cancelled = false

    void (async () => {
      try {
        const data = await notesApi.list()
        if (cancelled) {
          return
        }

        setNotes(data)
        if (data.length > 0) {
          setSelectedId(data[0].id)
          setDraftState({
            title: data[0].title,
            description: data[0].description,
          })
        }
      } catch (err) {
        if (!cancelled) {
          setError(err instanceof Error ? err.message : 'Failed to load notes.')
        }
      } finally {
        if (!cancelled) {
          setIsLoading(false)
        }
      }
    })()

    return () => {
      cancelled = true
    }
  }, [])

  const value = useMemo<NotesContextValue>(
    () => ({
      notes,
      draft,
      error,
      isLoading,
      isSaving,
      selectedId,
      setDraft(partialDraft) {
        setDraftState((currentDraft) => ({ ...currentDraft, ...partialDraft }))
      },
      selectNote(id) {
        const note = notes.find((item) => item.id === id)
        if (!note) {
          return
        }

        setSelectedId(id)
        setDraftState({
          title: note.title,
          description: note.description,
        })
        setError(null)
      },
      async createNote() {
        setIsSaving(true)
        setError(null)

        try {
          const created = await notesApi.create(draft)
          setNotes((currentNotes) => [created, ...currentNotes])
          setSelectedId(created.id)
          setDraftState({
            title: created.title,
            description: created.description,
          })
        } catch (err) {
          setError(err instanceof Error ? err.message : 'Failed to create note.')
        } finally {
          setIsSaving(false)
        }
      },
      async updateNote() {
        if (selectedId === null) {
          return
        }

        setIsSaving(true)
        setError(null)

        try {
          const updated = await notesApi.update(selectedId, draft)
          setNotes((currentNotes) =>
            currentNotes.map((note) => (note.id === updated.id ? updated : note)),
          )
          setDraftState({
            title: updated.title,
            description: updated.description,
          })
        } catch (err) {
          setError(err instanceof Error ? err.message : 'Failed to update note.')
        } finally {
          setIsSaving(false)
        }
      },
      async removeNote() {
        if (selectedId === null) {
          return
        }

        setIsSaving(true)
        setError(null)

        try {
          await notesApi.remove(selectedId)

          setNotes((currentNotes) => {
            const remaining = currentNotes.filter((note) => note.id !== selectedId)
            const nextSelected = remaining[0] ?? null

            setSelectedId(nextSelected?.id ?? null)
            setDraftState(
              nextSelected
                ? {
                    title: nextSelected.title,
                    description: nextSelected.description,
                  }
                : initialDraft,
            )

            return remaining
          })
        } catch (err) {
          setError(err instanceof Error ? err.message : 'Failed to delete note.')
        } finally {
          setIsSaving(false)
        }
      },
      resetDraft() {
        setSelectedId(null)
        setDraftState(initialDraft)
        setError(null)
      },
    }),
    [draft, error, isLoading, isSaving, notes, selectedId],
  )

  return <NotesContext.Provider value={value}>{children}</NotesContext.Provider>
}

export function useNotes() {
  const context = useContext(NotesContext)
  if (!context) {
    throw new Error('useNotes must be used within NotesProvider.')
  }

  return context
}
