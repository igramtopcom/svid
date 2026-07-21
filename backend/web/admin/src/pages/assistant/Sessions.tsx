import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { listSessions, getSession } from '@/api/assistant'
import { useBrandStore } from '@/store/brand'
import StatusBadge from '@/components/common/StatusBadge'
import Pagination from '@/components/common/Pagination'
import LoadingSpinner, { SkeletonTable } from '@/components/common/LoadingSpinner'
import EmptyState from '@/components/common/EmptyState'
import BrandBadge from '@/components/common/BrandBadge'
import Modal from '@/components/common/Modal'
import { formatDate, truncate } from '@/lib/utils'
export default function Sessions() {
  const brand = useBrandStore((s) => s.brand)
  const [page, setPage] = useState(1)
  const [status, setStatus] = useState('')
  const [selected, setSelected] = useState<string | null>(null)

  const { data, isLoading } = useQuery({
    queryKey: ['assistant-sessions', page, status, brand],
    queryFn: () => listSessions({ page, per_page: 20, status: status || undefined, brand: brand || undefined }),
  })

  const { data: sessionDetail, isLoading: loadingDetail } = useQuery({
    queryKey: ['assistant-session', selected],
    queryFn: () => getSession(selected!),
    enabled: !!selected,
  })

  return (
    <div>
      <h2 className="text-xl font-bold mb-4">
        AI Chat Sessions<BrandBadge />
        {data?.total != null && <span className="text-sm font-normal text-gray-400 ml-2">({data.total})</span>}
      </h2>

      <div className="flex gap-3 mb-4">
        <select value={status} onChange={(e) => { setStatus(e.target.value); setPage(1) }} className="px-3 py-2 border border-gray-300 rounded-md text-sm">
          <option value="">All Status</option>
          <option value="active">Active</option>
          <option value="closed">Closed</option>
          <option value="escalated">Escalated</option>
        </select>
        {status && (
          <button onClick={() => { setStatus(''); setPage(1) }} className="px-3 py-2 text-sm text-gray-500 hover:text-gray-700">
            Clear filter
          </button>
        )}
      </div>

      {isLoading ? <SkeletonTable rows={6} /> : !data?.items?.length ? <EmptyState message="No chat sessions" description="Chat sessions appear when users interact with the AI assistant in the app" /> : (
        <>
          <div className="bg-white rounded-lg border border-gray-200 overflow-hidden">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-gray-50 border-b">
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Title</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Status</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Device</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Date</th>
                </tr>
              </thead>
              <tbody>
                {data.items.map((session) => (
                  <tr
                    key={session.id}
                    className="border-b last:border-0 hover:bg-gray-50 cursor-pointer"
                    onClick={() => setSelected(session.id)}
                  >
                    <td className="px-4 py-3 font-medium text-brand-600">{truncate(session.title, 50)}</td>
                    <td className="px-4 py-3"><StatusBadge status={session.status} /></td>
                    <td className="px-4 py-3 text-gray-500 text-xs font-mono">{session.device_id.slice(0, 8)}...</td>
                    <td className="px-4 py-3 text-gray-500">{formatDate(session.created_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Pagination page={page} totalPages={data.total_pages} total={data.total} onPageChange={setPage} />
        </>
      )}

      {/* Session Detail Modal */}
      <Modal open={!!selected} onClose={() => setSelected(null)} title="Chat Session">
        {loadingDetail ? <LoadingSpinner /> : sessionDetail && (
          <div>
            <div className="flex items-center justify-between mb-4">
              <h4 className="font-medium">{sessionDetail.title}</h4>
              <StatusBadge status={sessionDetail.status} />
            </div>
            <div className="space-y-3 max-h-96 overflow-y-auto">
              {sessionDetail.messages?.map((msg) => (
                <div
                  key={msg.id}
                  className={`p-3 rounded-lg text-sm ${
                    msg.role === 'user'
                      ? 'bg-gray-50 border border-gray-200 mr-6'
                      : msg.role === 'assistant'
                      ? 'bg-brand-50 border border-brand-200 ml-6'
                      : 'bg-yellow-50 border border-yellow-200 text-center italic'
                  }`}
                >
                  <span className="text-xs font-medium text-gray-400 uppercase">{msg.role}</span>
                  <p className="mt-1 whitespace-pre-wrap">{msg.content}</p>
                  <span className="text-xs text-gray-400 mt-1 block">{formatDate(msg.created_at)}</span>
                </div>
              ))}
            </div>
          </div>
        )}
      </Modal>
    </div>
  )
}
