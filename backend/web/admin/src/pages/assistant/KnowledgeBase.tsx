import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { listKnowledge, createKnowledge, updateKnowledge, deleteKnowledge } from '@/api/assistant'
import StatusBadge from '@/components/common/StatusBadge'
import Pagination from '@/components/common/Pagination'
import { SkeletonTable } from '@/components/common/LoadingSpinner'
import EmptyState from '@/components/common/EmptyState'
import Modal from '@/components/common/Modal'
import { truncate } from '@/lib/utils'
import type { KnowledgeBase as KBType } from '@/types'

export default function KnowledgeBasePage() {
  const [page, setPage] = useState(1)
  const [category, setCategory] = useState('')
  const [showCreate, setShowCreate] = useState(false)
  const [editing, setEditing] = useState<KBType | null>(null)
  const queryClient = useQueryClient()

  const { data, isLoading } = useQuery({
    queryKey: ['knowledge', page, category],
    queryFn: () => listKnowledge({ page, per_page: 20, category: category || undefined }),
  })

  const createMut = useMutation({
    mutationFn: createKnowledge,
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['knowledge'] }); setShowCreate(false); toast.success('Entry created') },
  })

  const updateMut = useMutation({
    mutationFn: ({ id, ...d }: Partial<KBType> & { id: string }) => updateKnowledge(id, d),
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['knowledge'] }); setEditing(null); toast.success('Entry updated') },
  })

  const deleteMut = useMutation({
    mutationFn: deleteKnowledge,
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['knowledge'] }); toast.success('Entry deleted') },
  })

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-xl font-bold">
          Knowledge Base
          {data?.total != null && <span className="text-sm font-normal text-gray-400 ml-2">({data.total})</span>}
        </h2>
        <button onClick={() => setShowCreate(true)} className="px-4 py-2 bg-brand-600 text-white rounded-md text-sm hover:bg-brand-700">
          Add Entry
        </button>
      </div>

      <div className="flex gap-3 mb-4">
        <select value={category} onChange={(e) => { setCategory(e.target.value); setPage(1) }} className="px-3 py-2 border border-gray-300 rounded-md text-sm">
          <option value="">All Categories</option>
          <option value="faq">FAQ</option>
          <option value="tutorial">Tutorial</option>
          <option value="troubleshooting">Troubleshooting</option>
        </select>
      </div>

      {isLoading ? <SkeletonTable rows={4} /> : !data?.items?.length ? <EmptyState message="No knowledge entries" description="Add FAQ, tutorials, or troubleshooting guides for the AI assistant to reference" /> : (
        <>
          <div className="space-y-3">
            {data.items.map((kb) => (
              <div key={kb.id} className="bg-white rounded-lg border border-gray-200 p-4">
                <div className="flex items-start justify-between">
                  <div className="flex-1">
                    <div className="flex items-center gap-2 mb-1">
                      <h3 className="font-medium">{kb.title}</h3>
                      <StatusBadge status={kb.category} />
                      <StatusBadge status={kb.is_active ? 'active' : 'inactive'} />
                    </div>
                    <p className="text-sm text-gray-600">{truncate(kb.content, 150)}</p>
                    {kb.tags && <p className="text-xs text-gray-400 mt-1">Tags: {kb.tags}</p>}
                  </div>
                  <div className="flex gap-2 ml-4">
                    <button onClick={() => setEditing(kb)} className="text-brand-600 hover:underline text-sm">Edit</button>
                    <button onClick={() => { if (confirm('Delete?')) deleteMut.mutate(kb.id) }} className="text-red-500 hover:underline text-sm">Delete</button>
                  </div>
                </div>
              </div>
            ))}
          </div>
          <Pagination page={page} totalPages={data.total_pages} total={data.total} onPageChange={setPage} />
        </>
      )}

      <Modal open={showCreate} onClose={() => setShowCreate(false)} title="Add Knowledge Entry">
        <KBForm onSubmit={(d) => createMut.mutate(d)} loading={createMut.isPending} />
      </Modal>

      <Modal open={!!editing} onClose={() => setEditing(null)} title="Edit Knowledge Entry">
        {editing && <KBForm initial={editing} onSubmit={(d) => updateMut.mutate({ id: editing.id, ...d })} loading={updateMut.isPending} />}
      </Modal>
    </div>
  )
}

function KBForm({ initial, onSubmit, loading }: {
  initial?: Partial<KBType>; onSubmit: (d: Partial<KBType>) => void; loading: boolean
}) {
  const [title, setTitle] = useState(initial?.title || '')
  const [content, setContent] = useState(initial?.content || '')
  const [category, setCategory] = useState(initial?.category || 'faq')
  const [tags, setTags] = useState(initial?.tags || '')
  const [active, setActive] = useState(initial?.is_active ?? true)

  return (
    <form onSubmit={(e) => { e.preventDefault(); onSubmit({ title, content, category, tags, is_active: active }) }} className="space-y-3">
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">Title</label>
        <input value={title} onChange={(e) => setTitle(e.target.value)} required className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm focus:outline-none focus:ring-2 focus:ring-brand-500" />
      </div>
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">Content</label>
        <textarea value={content} onChange={(e) => setContent(e.target.value)} required rows={6} className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm focus:outline-none focus:ring-2 focus:ring-brand-500" />
      </div>
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">Category</label>
        <select value={category} onChange={(e) => setCategory(e.target.value)} className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm">
          <option value="faq">FAQ</option>
          <option value="tutorial">Tutorial</option>
          <option value="troubleshooting">Troubleshooting</option>
        </select>
      </div>
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">Tags</label>
        <input value={tags} onChange={(e) => setTags(e.target.value)} placeholder="download, error, setup" className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm focus:outline-none focus:ring-2 focus:ring-brand-500" />
      </div>
      <label className="flex items-center gap-2 text-sm">
        <input type="checkbox" checked={active} onChange={(e) => setActive(e.target.checked)} /> Active
      </label>
      <button type="submit" disabled={loading} className="w-full py-2 bg-brand-600 text-white rounded-md text-sm hover:bg-brand-700 disabled:opacity-50">
        {loading ? 'Saving...' : 'Save'}
      </button>
    </form>
  )
}
