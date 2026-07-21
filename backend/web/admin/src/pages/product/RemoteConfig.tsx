import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { listConfigs, createConfig, updateConfig, deleteConfig } from '@/api/product'
import Pagination from '@/components/common/Pagination'
import { SkeletonTable } from '@/components/common/LoadingSpinner'
import EmptyState from '@/components/common/EmptyState'
import Modal from '@/components/common/Modal'
import type { RemoteConfig as RCType } from '@/types'

export default function RemoteConfigPage() {
  const [page, setPage] = useState(1)
  const [showCreate, setShowCreate] = useState(false)
  const [editing, setEditing] = useState<RCType | null>(null)
  const queryClient = useQueryClient()

  const { data, isLoading } = useQuery({
    queryKey: ['configs', page],
    queryFn: () => listConfigs({ page, per_page: 20 }),
  })

  const createMut = useMutation({
    mutationFn: createConfig,
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['configs'] }); setShowCreate(false); toast.success('Config created') },
  })

  const updateMut = useMutation({
    mutationFn: ({ id, ...d }: Partial<RCType> & { id: string }) => updateConfig(id, d),
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['configs'] }); setEditing(null); toast.success('Config updated') },
  })

  const deleteMut = useMutation({
    mutationFn: deleteConfig,
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['configs'] }); toast.success('Config deleted') },
  })

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-xl font-bold">Remote Config</h2>
        <button onClick={() => setShowCreate(true)} className="px-4 py-2 bg-brand-600 text-white rounded-md text-sm hover:bg-brand-700">
          Create Config
        </button>
      </div>

      {isLoading ? <SkeletonTable rows={4} /> : !data?.items?.length ? <EmptyState message="No config entries" description="Remote config lets you change app behavior without releasing a new version" /> : (
        <>
          <div className="bg-white rounded-lg border border-gray-200 overflow-hidden">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-gray-50 border-b">
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Key</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Value</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Type</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Description</th>
                  <th className="text-right px-4 py-3 font-medium text-gray-600">Actions</th>
                </tr>
              </thead>
              <tbody>
                {data.items.map((cfg) => (
                  <tr key={cfg.id} className="border-b last:border-0 hover:bg-gray-50">
                    <td className="px-4 py-3 font-mono text-sm">{cfg.key}</td>
                    <td className="px-4 py-3 text-gray-600 font-mono text-xs max-w-xs truncate">{cfg.value}</td>
                    <td className="px-4 py-3">
                      <span className="text-xs bg-gray-100 text-gray-600 px-2 py-0.5 rounded">{cfg.value_type}</span>
                    </td>
                    <td className="px-4 py-3 text-gray-500">{cfg.description || '-'}</td>
                    <td className="px-4 py-3 text-right">
                      <button onClick={() => setEditing(cfg)} className="text-brand-600 hover:underline text-sm mr-3">Edit</button>
                      <button onClick={() => { if (confirm('Delete?')) deleteMut.mutate(cfg.id) }} className="text-red-500 hover:underline text-sm">Delete</button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Pagination page={page} totalPages={data.total_pages} total={data.total} onPageChange={setPage} />
        </>
      )}

      <Modal open={showCreate} onClose={() => setShowCreate(false)} title="Create Config">
        <ConfigForm onSubmit={(d) => createMut.mutate(d)} loading={createMut.isPending} />
      </Modal>

      <Modal open={!!editing} onClose={() => setEditing(null)} title="Edit Config">
        {editing && <ConfigForm initial={editing} onSubmit={(d) => updateMut.mutate({ id: editing.id, ...d })} loading={updateMut.isPending} />}
      </Modal>
    </div>
  )
}

function ConfigForm({ initial, onSubmit, loading }: {
  initial?: Partial<RCType>; onSubmit: (d: Partial<RCType>) => void; loading: boolean
}) {
  const [key, setKey] = useState(initial?.key || '')
  const [value, setValue] = useState(initial?.value || '')
  const [valueType, setValueType] = useState(initial?.value_type || 'string')
  const [desc, setDesc] = useState(initial?.description || '')

  return (
    <form onSubmit={(e) => { e.preventDefault(); onSubmit({ key, value, value_type: valueType, description: desc }) }} className="space-y-3">
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">Key</label>
        <input value={key} onChange={(e) => setKey(e.target.value)} required className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm focus:outline-none focus:ring-2 focus:ring-brand-500" placeholder="max_concurrent_downloads" />
      </div>
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">Value</label>
        <textarea value={value} onChange={(e) => setValue(e.target.value)} required rows={3} className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm font-mono focus:outline-none focus:ring-2 focus:ring-brand-500" />
      </div>
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">Type</label>
        <select value={valueType} onChange={(e) => setValueType(e.target.value)} className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm">
          <option value="string">String</option>
          <option value="number">Number</option>
          <option value="boolean">Boolean</option>
          <option value="json">JSON</option>
        </select>
      </div>
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">Description</label>
        <input value={desc} onChange={(e) => setDesc(e.target.value)} className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm focus:outline-none focus:ring-2 focus:ring-brand-500" />
      </div>
      <button type="submit" disabled={loading} className="w-full py-2 bg-brand-600 text-white rounded-md text-sm hover:bg-brand-700 disabled:opacity-50">
        {loading ? 'Saving...' : 'Save'}
      </button>
    </form>
  )
}
