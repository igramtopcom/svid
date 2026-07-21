import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { listAnnouncements, createAnnouncement, updateAnnouncement, deleteAnnouncement } from '@/api/product'
import StatusBadge from '@/components/common/StatusBadge'
import Pagination from '@/components/common/Pagination'
import { SkeletonTable } from '@/components/common/LoadingSpinner'
import EmptyState from '@/components/common/EmptyState'
import Modal from '@/components/common/Modal'
import { formatDate, truncate } from '@/lib/utils'
import type { Announcement } from '@/types'

export default function Announcements() {
  const [page, setPage] = useState(1)
  const [showCreate, setShowCreate] = useState(false)
  const [editing, setEditing] = useState<Announcement | null>(null)
  const queryClient = useQueryClient()

  const { data, isLoading } = useQuery({
    queryKey: ['announcements', page],
    queryFn: () => listAnnouncements({ page, per_page: 20 }),
  })

  const createMut = useMutation({
    mutationFn: createAnnouncement,
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['announcements'] }); setShowCreate(false); toast.success('Announcement created') },
  })

  const updateMut = useMutation({
    mutationFn: ({ id, ...d }: Partial<Announcement> & { id: string }) => updateAnnouncement(id, d),
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['announcements'] }); setEditing(null); toast.success('Announcement updated') },
  })

  const deleteMut = useMutation({
    mutationFn: deleteAnnouncement,
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['announcements'] }); toast.success('Announcement deleted') },
  })

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-xl font-bold">Announcements</h2>
        <button onClick={() => setShowCreate(true)} className="px-4 py-2 bg-brand-600 text-white rounded-md text-sm hover:bg-brand-700">
          Create Announcement
        </button>
      </div>

      {isLoading ? <SkeletonTable rows={4} /> : !data?.items?.length ? <EmptyState message="No announcements" description="Create announcements to notify app users about updates or maintenance" /> : (
        <>
          <div className="bg-white rounded-lg border border-gray-200 overflow-hidden">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-gray-50 border-b">
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Title</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Type</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Status</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Period</th>
                  <th className="text-right px-4 py-3 font-medium text-gray-600">Actions</th>
                </tr>
              </thead>
              <tbody>
                {data.items.map((ann) => (
                  <tr key={ann.id} className="border-b last:border-0 hover:bg-gray-50">
                    <td className="px-4 py-3 font-medium">{truncate(ann.title, 40)}</td>
                    <td className="px-4 py-3"><StatusBadge status={ann.type} /></td>
                    <td className="px-4 py-3"><StatusBadge status={ann.is_active ? 'active' : 'inactive'} /></td>
                    <td className="px-4 py-3 text-gray-500 text-xs">{formatDate(ann.starts_at)} - {formatDate(ann.expires_at)}</td>
                    <td className="px-4 py-3 text-right">
                      <button onClick={() => setEditing(ann)} className="text-brand-600 hover:underline text-sm mr-3">Edit</button>
                      <button onClick={() => { if (confirm('Delete?')) deleteMut.mutate(ann.id) }} className="text-red-500 hover:underline text-sm">Delete</button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Pagination page={page} totalPages={data.total_pages} total={data.total} onPageChange={setPage} />
        </>
      )}

      <Modal open={showCreate} onClose={() => setShowCreate(false)} title="Create Announcement">
        <AnnForm onSubmit={(d) => createMut.mutate(d)} loading={createMut.isPending} />
      </Modal>

      <Modal open={!!editing} onClose={() => setEditing(null)} title="Edit Announcement">
        {editing && <AnnForm initial={editing} onSubmit={(d) => updateMut.mutate({ id: editing.id, ...d })} loading={updateMut.isPending} />}
      </Modal>
    </div>
  )
}

function AnnForm({ initial, onSubmit, loading }: {
  initial?: Partial<Announcement>; onSubmit: (d: Partial<Announcement>) => void; loading: boolean
}) {
  const [title, setTitle] = useState(initial?.title || '')
  const [content, setContent] = useState(initial?.content || '')
  const [type, setType] = useState(initial?.type || 'info')
  const [tiers, setTiers] = useState(initial?.target_tiers || '')
  const [platforms, setPlatforms] = useState(initial?.target_platforms || '')
  const [active, setActive] = useState(initial?.is_active ?? true)
  const [starts, setStarts] = useState(initial?.starts_at?.slice(0, 16) || '')
  const [expires, setExpires] = useState(initial?.expires_at?.slice(0, 16) || '')

  return (
    <form onSubmit={(e) => { e.preventDefault(); onSubmit({ title, content, type, target_tiers: tiers, target_platforms: platforms, is_active: active, starts_at: starts ? new Date(starts).toISOString() : '', expires_at: expires ? new Date(expires).toISOString() : '' }) }} className="space-y-3">
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">Title</label>
        <input value={title} onChange={(e) => setTitle(e.target.value)} required className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm focus:outline-none focus:ring-2 focus:ring-brand-500" />
      </div>
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">Content</label>
        <textarea value={content} onChange={(e) => setContent(e.target.value)} required rows={3} className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm focus:outline-none focus:ring-2 focus:ring-brand-500" />
      </div>
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">Type</label>
        <select value={type} onChange={(e) => setType(e.target.value)} className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm">
          <option value="info">Info</option>
          <option value="warning">Warning</option>
          <option value="critical">Critical</option>
          <option value="maintenance">Maintenance</option>
        </select>
      </div>
      <div className="grid grid-cols-2 gap-3">
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Starts At</label>
          <input type="datetime-local" value={starts} onChange={(e) => setStarts(e.target.value)} className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm" />
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Expires At</label>
          <input type="datetime-local" value={expires} onChange={(e) => setExpires(e.target.value)} className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm" />
        </div>
      </div>
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">Target Tiers (JSON)</label>
        <input value={tiers} onChange={(e) => setTiers(e.target.value)} placeholder='["free","pro"]' className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm focus:outline-none focus:ring-2 focus:ring-brand-500" />
      </div>
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">Target Platforms (JSON)</label>
        <input value={platforms} onChange={(e) => setPlatforms(e.target.value)} placeholder='["windows","macos"]' className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm focus:outline-none focus:ring-2 focus:ring-brand-500" />
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
