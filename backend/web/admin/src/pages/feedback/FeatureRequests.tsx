import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { listFeatureRequests, updateFeatureRequest } from '@/api/feedback'
import { useBrandStore } from '@/store/brand'
import StatusBadge from '@/components/common/StatusBadge'
import Pagination from '@/components/common/Pagination'
import { SkeletonTable } from '@/components/common/LoadingSpinner'
import EmptyState from '@/components/common/EmptyState'
import BrandBadge from '@/components/common/BrandBadge'
import Modal from '@/components/common/Modal'
import { useDebounce } from '@/hooks/useDebounce'
import { formatDate, truncate } from '@/lib/utils'
import { ThumbsUp, Search, X, Download } from 'lucide-react'
import { exportCSV } from '@/lib/export'
import { toast } from 'sonner'
import type { FeatureRequest } from '@/types'

export default function FeatureRequests() {
  const [page, setPage] = useState(1)
  const [status, setStatus] = useState('')
  const [sort, setSort] = useState('newest')
  const [searchInput, setSearchInput] = useState('')
  const search = useDebounce(searchInput)
  const [editing, setEditing] = useState<FeatureRequest | null>(null)
  const brand = useBrandStore((s) => s.brand)
  const queryClient = useQueryClient()

  const { data, isLoading } = useQuery({
    queryKey: ['feature-requests', page, status, sort, search, brand],
    queryFn: () => listFeatureRequests({
      page, per_page: 20,
      status: status || undefined,
      sort: sort || undefined,
      search: search || undefined,
      brand: brand || undefined,
    }),
  })

  const updateMut = useMutation({
    mutationFn: ({ id, ...d }: { id: string; status?: string; admin_response?: string }) => updateFeatureRequest(id, d),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['feature-requests'] })
      setEditing(null)
      toast.success('Feature request updated')
    },
  })

  const hasFilters = status || searchInput
  const clearAll = () => { setStatus(''); setSearchInput(''); setPage(1) }

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-xl font-bold">
          Feature Requests<BrandBadge />
          {data?.total != null && <span className="text-sm font-normal text-gray-400 ml-2">({data.total})</span>}
        </h2>
        {data?.items?.length ? (
          <button
            onClick={() => exportCSV(data.items.map(fr => ({
              title: fr.title,
              description: fr.description,
              status: fr.status,
              upvotes: fr.upvotes,
              admin_response: fr.admin_response || '',
              created_at: fr.created_at,
            })), 'feature_requests')}
            className="flex items-center gap-1.5 px-3 py-1.5 text-sm text-gray-600 border border-gray-300 rounded-md hover:bg-gray-50"
          >
            <Download size={14} /> Export CSV
          </button>
        ) : null}
      </div>

      <div className="flex flex-wrap gap-3 mb-4">
        <div className="relative flex-1 min-w-[200px] max-w-sm">
          <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400" />
          <input
            type="text"
            value={searchInput}
            onChange={(e) => { setSearchInput(e.target.value); setPage(1) }}
            placeholder="Search title or description..."
            className="w-full pl-9 pr-8 py-2 border border-gray-300 rounded-md text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
          />
          {searchInput && (
            <button onClick={() => { setSearchInput(''); setPage(1) }} className="absolute right-2 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600">
              <X size={14} />
            </button>
          )}
        </div>
        <select value={status} onChange={(e) => { setStatus(e.target.value); setPage(1) }} className="px-3 py-2 border border-gray-300 rounded-md text-sm">
          <option value="">All Status</option>
          <option value="open">Open</option>
          <option value="under_review">Under Review</option>
          <option value="planned">Planned</option>
          <option value="implemented">Implemented</option>
          <option value="declined">Declined</option>
        </select>
        <select value={sort} onChange={(e) => { setSort(e.target.value); setPage(1) }} className="px-3 py-2 border border-gray-300 rounded-md text-sm">
          <option value="newest">Newest</option>
          <option value="upvotes">Most Upvoted</option>
        </select>
        {hasFilters && (
          <button onClick={clearAll} className="px-3 py-2 text-sm text-gray-500 hover:text-gray-700">
            Clear filters
          </button>
        )}
      </div>

      {isLoading ? <SkeletonTable rows={6} /> : !data?.items?.length ? (
        <EmptyState message="No feature requests" description={hasFilters ? "Try adjusting your filters" : "Feature requests appear when users suggest improvements from the app"} />
      ) : (
        <>
          <div className="space-y-3">
            {data.items.map((fr) => (
              <div key={fr.id} className="bg-white rounded-lg border border-gray-200 p-4 hover:border-gray-300 transition-colors">
                <div className="flex items-start gap-4">
                  <div className="flex flex-col items-center text-gray-500 min-w-[40px]">
                    <ThumbsUp size={16} />
                    <span className="text-sm font-bold">{fr.upvotes}</span>
                  </div>
                  <div className="flex-1">
                    <div className="flex items-center justify-between">
                      <h3 className="font-medium">{fr.title}</h3>
                      <StatusBadge status={fr.status} />
                    </div>
                    <p className="text-sm text-gray-600 mt-1">{truncate(fr.description, 200)}</p>
                    {fr.admin_response && (
                      <div className="mt-2 p-2 bg-brand-50 rounded text-sm text-brand-700">
                        <strong>Response:</strong> {fr.admin_response}
                      </div>
                    )}
                    <div className="flex items-center gap-4 mt-2 text-xs text-gray-400">
                      <span>{formatDate(fr.created_at)}</span>
                      <button onClick={() => setEditing(fr)} className="text-brand-600 hover:underline">
                        Respond
                      </button>
                    </div>
                  </div>
                </div>
              </div>
            ))}
          </div>
          <Pagination page={page} totalPages={data.total_pages} total={data.total} onPageChange={setPage} />
        </>
      )}

      <Modal open={!!editing} onClose={() => setEditing(null)} title="Update Feature Request">
        {editing && (
          <ResponseForm
            initial={editing}
            onSubmit={(d) => updateMut.mutate({ id: editing.id, ...d })}
            loading={updateMut.isPending}
          />
        )}
      </Modal>
    </div>
  )
}

function ResponseForm({ initial, onSubmit, loading }: {
  initial: FeatureRequest
  onSubmit: (d: { status?: string; admin_response?: string }) => void
  loading: boolean
}) {
  const [status, setStatus] = useState(initial.status)
  const [response, setResponse] = useState(initial.admin_response || '')

  return (
    <form onSubmit={(e) => { e.preventDefault(); onSubmit({ status, admin_response: response }) }} className="space-y-3">
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">Status</label>
        <select value={status} onChange={(e) => setStatus(e.target.value)} className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm">
          <option value="open">Open</option>
          <option value="under_review">Under Review</option>
          <option value="planned">Planned</option>
          <option value="implemented">Implemented</option>
          <option value="declined">Declined</option>
        </select>
      </div>
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">Admin Response</label>
        <textarea value={response} onChange={(e) => setResponse(e.target.value)} rows={4} className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm focus:outline-none focus:ring-2 focus:ring-brand-500" placeholder="Your response to this feature request..." />
      </div>
      <button type="submit" disabled={loading} className="w-full py-2 bg-brand-600 text-white rounded-md text-sm hover:bg-brand-700 disabled:opacity-50">
        {loading ? 'Saving...' : 'Update'}
      </button>
    </form>
  )
}
