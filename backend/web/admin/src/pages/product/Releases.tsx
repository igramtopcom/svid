import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { listReleases, createRelease, updateRelease } from '@/api/product'
import StatusBadge from '@/components/common/StatusBadge'
import Pagination from '@/components/common/Pagination'
import { SkeletonTable } from '@/components/common/LoadingSpinner'
import EmptyState from '@/components/common/EmptyState'
import Modal from '@/components/common/Modal'
import { formatDate } from '@/lib/utils'
import type { AppRelease } from '@/types'

export default function Releases() {
  const [page, setPage] = useState(1)
  const [showCreate, setShowCreate] = useState(false)
  const [editing, setEditing] = useState<AppRelease | null>(null)
  const queryClient = useQueryClient()

  const { data, isLoading } = useQuery({
    queryKey: ['releases', page],
    queryFn: () => listReleases({ page, per_page: 20 }),
  })

  const createMut = useMutation({
    mutationFn: createRelease,
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['releases'] }); setShowCreate(false); toast.success('Release created') },
  })

  const updateMut = useMutation({
    mutationFn: ({ id, ...d }: Partial<AppRelease> & { id: string }) => updateRelease(id, d),
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['releases'] }); setEditing(null); toast.success('Release updated') },
  })

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-xl font-bold">App Releases</h2>
        <button onClick={() => setShowCreate(true)} className="px-4 py-2 bg-brand-600 text-white rounded-md text-sm hover:bg-brand-700">
          Create Release
        </button>
      </div>

      {isLoading ? <SkeletonTable rows={4} /> : !data?.items?.length ? <EmptyState message="No releases" description="Create a release to publish new app versions for auto-update" /> : (
        <>
          <div className="bg-white rounded-lg border border-gray-200 overflow-hidden">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-gray-50 border-b">
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Version</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Platform</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Channel</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Status</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Published</th>
                  <th className="text-right px-4 py-3 font-medium text-gray-600">Actions</th>
                </tr>
              </thead>
              <tbody>
                {data.items.map((rel) => (
                  <tr key={rel.id} className="border-b last:border-0 hover:bg-gray-50">
                    <td className="px-4 py-3 font-mono font-medium">{rel.version}</td>
                    <td className="px-4 py-3">{rel.platform}</td>
                    <td className="px-4 py-3"><StatusBadge status={rel.channel} /></td>
                    <td className="px-4 py-3">
                      <StatusBadge status={rel.is_active ? 'active' : 'inactive'} />
                      {rel.is_mandatory && <span className="ml-1 text-xs text-red-500 font-medium">mandatory</span>}
                    </td>
                    <td className="px-4 py-3 text-gray-500">{rel.published_at ? formatDate(rel.published_at) : 'Draft'}</td>
                    <td className="px-4 py-3 text-right">
                      <button onClick={() => setEditing(rel)} className="text-brand-600 hover:underline text-sm">Edit</button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Pagination page={page} totalPages={data.total_pages} total={data.total} onPageChange={setPage} />
        </>
      )}

      <Modal open={showCreate} onClose={() => setShowCreate(false)} title="Create Release">
        <ReleaseForm onSubmit={(d) => createMut.mutate(d)} loading={createMut.isPending} />
      </Modal>

      <Modal open={!!editing} onClose={() => setEditing(null)} title="Edit Release">
        {editing && <ReleaseForm initial={editing} onSubmit={(d) => updateMut.mutate({ id: editing.id, ...d })} loading={updateMut.isPending} />}
      </Modal>
    </div>
  )
}

function ReleaseForm({ initial, onSubmit, loading }: {
  initial?: Partial<AppRelease>; onSubmit: (d: Partial<AppRelease>) => void; loading: boolean
}) {
  const [version, setVersion] = useState(initial?.version || '')
  const [platform, setPlatform] = useState(initial?.platform || 'windows')
  const [channel, setChannel] = useState(initial?.channel || 'stable')
  const [notes, setNotes] = useState(initial?.release_notes || '')
  const [url, setUrl] = useState(initial?.download_url || '')
  const [checksum, setChecksum] = useState(initial?.checksum || '')
  const [mandatory, setMandatory] = useState(initial?.is_mandatory ?? false)
  const [active, setActive] = useState(initial?.is_active ?? true)

  return (
    <form onSubmit={(e) => { e.preventDefault(); onSubmit({ version, platform, channel, release_notes: notes, download_url: url, checksum, is_mandatory: mandatory, is_active: active } as Partial<AppRelease>) }} className="space-y-3">
      <div className="grid grid-cols-2 gap-3">
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Version</label>
          <input value={version} onChange={(e) => setVersion(e.target.value)} required className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm focus:outline-none focus:ring-2 focus:ring-brand-500" placeholder="1.2.0" />
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Platform</label>
          <select value={platform} onChange={(e) => setPlatform(e.target.value)} className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm">
            <option value="windows">Windows</option>
            <option value="macos">macOS</option>
            <option value="linux">Linux</option>
          </select>
        </div>
      </div>
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">Channel</label>
        <select value={channel} onChange={(e) => setChannel(e.target.value)} className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm">
          <option value="stable">Stable</option>
          <option value="beta">Beta</option>
          <option value="alpha">Alpha</option>
        </select>
      </div>
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">Download URL</label>
        <input value={url} onChange={(e) => setUrl(e.target.value)} className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm focus:outline-none focus:ring-2 focus:ring-brand-500" />
      </div>
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">Release Notes</label>
        <textarea value={notes} onChange={(e) => setNotes(e.target.value)} rows={3} className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm focus:outline-none focus:ring-2 focus:ring-brand-500" />
      </div>
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">Checksum (SHA-256)</label>
        <input value={checksum} onChange={(e) => setChecksum(e.target.value)} className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm font-mono focus:outline-none focus:ring-2 focus:ring-brand-500" />
      </div>
      <div className="flex gap-4">
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" checked={mandatory} onChange={(e) => setMandatory(e.target.checked)} /> Mandatory
        </label>
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" checked={active} onChange={(e) => setActive(e.target.checked)} /> Active
        </label>
      </div>
      <button type="submit" disabled={loading} className="w-full py-2 bg-brand-600 text-white rounded-md text-sm hover:bg-brand-700 disabled:opacity-50">
        {loading ? 'Saving...' : 'Save'}
      </button>
    </form>
  )
}
