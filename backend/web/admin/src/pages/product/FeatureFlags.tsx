import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { listFlags, createFlag, updateFlag, deleteFlag } from '@/api/product'
import StatusBadge from '@/components/common/StatusBadge'
import Pagination from '@/components/common/Pagination'
import { SkeletonTable } from '@/components/common/LoadingSpinner'
import EmptyState from '@/components/common/EmptyState'
import Modal from '@/components/common/Modal'
import type { FeatureFlag } from '@/types'

export default function FeatureFlags() {
  const [page, setPage] = useState(1)
  const [showCreate, setShowCreate] = useState(false)
  const [editing, setEditing] = useState<FeatureFlag | null>(null)
  const queryClient = useQueryClient()

  const { data, isLoading } = useQuery({
    queryKey: ['flags', page],
    queryFn: () => listFlags({ page, per_page: 20 }),
  })

  const createMut = useMutation({
    mutationFn: createFlag,
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['flags'] }); setShowCreate(false); toast.success('Flag created') },
  })

  const updateMut = useMutation({
    mutationFn: ({ id, ...data }: Partial<FeatureFlag> & { id: string }) => updateFlag(id, data),
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['flags'] }); setEditing(null); toast.success('Flag updated') },
  })

  const deleteMut = useMutation({
    mutationFn: deleteFlag,
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['flags'] }); toast.success('Flag deleted') },
  })

  const toggleFlag = (flag: FeatureFlag) => {
    updateMut.mutate({ id: flag.id, enabled: !flag.enabled })
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-xl font-bold">Feature Flags</h2>
        <button
          onClick={() => setShowCreate(true)}
          className="px-4 py-2 bg-brand-600 text-white rounded-md text-sm hover:bg-brand-700"
        >
          Create Flag
        </button>
      </div>

      {isLoading ? (
        <SkeletonTable rows={4} />
      ) : !data?.items?.length ? (
        <EmptyState message="No feature flags" description="Feature flags let you toggle app features remotely without a new release" />
      ) : (
        <>
          <div className="bg-white rounded-lg border border-gray-200 overflow-hidden">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-gray-50 border-b">
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Key</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Description</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Status</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Tiers</th>
                  <th className="text-right px-4 py-3 font-medium text-gray-600">Actions</th>
                </tr>
              </thead>
              <tbody>
                {data.items.map((flag) => (
                  <tr key={flag.id} className="border-b last:border-0 hover:bg-gray-50">
                    <td className="px-4 py-3 font-mono text-sm">{flag.key}</td>
                    <td className="px-4 py-3 text-gray-600">{flag.description || '-'}</td>
                    <td className="px-4 py-3">
                      <button onClick={() => toggleFlag(flag)}>
                        <StatusBadge status={flag.enabled ? 'enabled' : 'disabled'} />
                      </button>
                    </td>
                    <td className="px-4 py-3 text-gray-500 text-xs">{flag.tiers || 'all'}</td>
                    <td className="px-4 py-3 text-right">
                      <button onClick={() => setEditing(flag)} className="text-brand-600 hover:underline text-sm mr-3">
                        Edit
                      </button>
                      <button
                        onClick={() => { if (confirm('Delete this flag?')) deleteMut.mutate(flag.id) }}
                        className="text-red-500 hover:underline text-sm"
                      >
                        Delete
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Pagination page={page} totalPages={data.total_pages} total={data.total} onPageChange={setPage} />
        </>
      )}

      {/* Create Modal */}
      <Modal open={showCreate} onClose={() => setShowCreate(false)} title="Create Feature Flag">
        <FlagForm
          onSubmit={(data) => createMut.mutate(data)}
          loading={createMut.isPending}
        />
      </Modal>

      {/* Edit Modal */}
      <Modal open={!!editing} onClose={() => setEditing(null)} title="Edit Feature Flag">
        {editing && (
          <FlagForm
            initial={editing}
            onSubmit={(data) => updateMut.mutate({ id: editing.id, ...data })}
            loading={updateMut.isPending}
          />
        )}
      </Modal>
    </div>
  )
}

function FlagForm({
  initial,
  onSubmit,
  loading,
}: {
  initial?: Partial<FeatureFlag>
  onSubmit: (data: Partial<FeatureFlag>) => void
  loading: boolean
}) {
  const [key, setKey] = useState(initial?.key || '')
  const [name, setName] = useState(initial?.name || '')
  const [description, setDescription] = useState(initial?.description || '')
  const [enabled, setEnabled] = useState(initial?.enabled ?? false)
  const [tiers, setTiers] = useState(initial?.tiers || '')
  const [platforms, setPlatforms] = useState(initial?.platforms || '')
  const [minVersion, setMinVersion] = useState(initial?.min_app_version || '')

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    onSubmit({ key, name, description, enabled, tiers, platforms, min_app_version: minVersion })
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-3">
      <Input label="Key" value={key} onChange={setKey} required placeholder="feature_dark_mode" />
      <Input label="Name" value={name} onChange={setName} required placeholder="Dark Mode" />
      <Input label="Description" value={description} onChange={setDescription} />
      <Input label="Tiers (JSON array)" value={tiers} onChange={setTiers} placeholder='["free","pro"]' />
      <Input label="Platforms (JSON array)" value={platforms} onChange={setPlatforms} placeholder='["windows","macos"]' />
      <Input label="Min App Version" value={minVersion} onChange={setMinVersion} placeholder="1.2.0" />
      <label className="flex items-center gap-2 text-sm">
        <input type="checkbox" checked={enabled} onChange={(e) => setEnabled(e.target.checked)} />
        Enabled
      </label>
      <button type="submit" disabled={loading} className="w-full py-2 bg-brand-600 text-white rounded-md text-sm hover:bg-brand-700 disabled:opacity-50">
        {loading ? 'Saving...' : 'Save'}
      </button>
    </form>
  )
}

function Input({ label, value, onChange, required, placeholder }: {
  label: string; value: string; onChange: (v: string) => void; required?: boolean; placeholder?: string
}) {
  return (
    <div>
      <label className="block text-sm font-medium text-gray-700 mb-1">{label}</label>
      <input
        value={value}
        onChange={(e) => onChange(e.target.value)}
        required={required}
        placeholder={placeholder}
        className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
      />
    </div>
  )
}
