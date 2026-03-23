import './App.css'
import { useNotes } from './notes-context'

function App() {
  const {
    notes,
    isLoading,
    isSaving,
    error,
    draft,
    selectedId,
    setDraft,
    selectNote,
    createNote,
    updateNote,
    removeNote,
    resetDraft,
  } = useNotes()

  const selectedNote = notes.find((note) => note.id === selectedId) ?? null
  const isEditing = selectedNote !== null

  return (
    <main className="shell">
      <section className="intro">
        <div>
          <p className="eyebrow">Full stack notes</p>
          <h1>Minimal API + React + Postgres, clean enough to ship.</h1>
        </div>
        <p className="lede">
          Compose first, Kubernetes later. This screen stays intentionally small:
          only id, title, and description.
        </p>
      </section>

      <section className="workspace">
        <aside className="list-card">
          <div className="panel-header">
            <div>
              <p className="panel-kicker">Notebook</p>
              <h2>Saved notes</h2>
            </div>
            <button className="ghost-button" onClick={resetDraft} type="button">
              New note
            </button>
          </div>

          {isLoading ? <p className="status">Loading notes...</p> : null}
          {error ? <p className="status error">{error}</p> : null}

          <ul className="note-list">
            {notes.map((note) => (
              <li key={note.id}>
                <button
                  className={`note-item ${selectedId === note.id ? 'active' : ''}`}
                  onClick={() => selectNote(note.id)}
                  type="button"
                >
                  <strong>{note.title}</strong>
                  <span>{note.description}</span>
                </button>
              </li>
            ))}
          </ul>
        </aside>

        <section className="editor-card">
          <div className="panel-header">
            <div>
              <p className="panel-kicker">{isEditing ? `Editing #${selectedId}` : 'Create'}</p>
              <h2>{isEditing ? 'Update note' : 'Write a new note'}</h2>
            </div>
          </div>

          <form
            className="note-form"
            onSubmit={(event) => {
              event.preventDefault()
              if (isEditing) {
                void updateNote()
              } else {
                void createNote()
              }
            }}
          >
            <label>
              <span>Title</span>
              <input
                maxLength={160}
                onChange={(event) => setDraft({ title: event.target.value })}
                placeholder="Keep it sharp"
                value={draft.title}
              />
            </label>

            <label>
              <span>Description</span>
              <textarea
                maxLength={2000}
                onChange={(event) => setDraft({ description: event.target.value })}
                placeholder="Context, decisions, follow-up, or just a quick thought."
                rows={10}
                value={draft.description}
              />
            </label>

            <div className="actions">
              <button className="primary-button" disabled={isSaving} type="submit">
                {isSaving ? 'Saving...' : isEditing ? 'Update note' : 'Create note'}
              </button>
              {isEditing ? (
                <button
                  className="danger-button"
                  disabled={isSaving}
                  onClick={() => void removeNote()}
                  type="button"
                >
                  Delete note
                </button>
              ) : null}
            </div>
          </form>

          {selectedNote ? (
            <div className="preview-card">
              <p className="panel-kicker">Preview</p>
              <h3>{selectedNote.title}</h3>
              <p>{selectedNote.description}</p>
            </div>
          ) : (
            <div className="preview-card muted">
              <p className="panel-kicker">Preview</p>
              <h3>No note selected</h3>
              <p>Create a note or select one from the list to edit it here.</p>
            </div>
          )}
        </section>
      </section>
    </main>
  )
}

export default App
