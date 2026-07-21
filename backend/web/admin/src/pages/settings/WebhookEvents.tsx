import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { listWebhookEvents } from '@/api/system'
import Pagination from '@/components/common/Pagination'
import { SkeletonTable } from '@/components/common/LoadingSpinner'
import EmptyState from '@/components/common/EmptyState'
import StatusBadge from '@/components/common/StatusBadge'
import { formatDate } from '@/lib/utils'
import { Download } from 'lucide-react'
import { exportCSV } from '@/lib/export'

export default function WebhookEvents() {
  const [page, setPage] = useState(1)
  const [eventType, setEventType] = useState('')
  const [status, setStatus] = useState('')

  const { data, isLoading } = useQuery({
    queryKey: ['webhook-events', page, eventType, status],
    queryFn: () => listWebhookEvents({
      page,
      per_page: 30,
      event_type: eventType || undefined,
      status: status || undefined,
    }),
  })

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <div>
          <h2 className="text-xl font-bold">
            Webhook Events
            {data?.total != null && <span className="text-sm font-normal text-gray-400 ml-2">({data.total})</span>}
          </h2>
          <p className="text-sm text-gray-500 mt-1">Stripe webhook events received and their processing status.</p>
        </div>
        {data?.items?.length ? (
          <button
            onClick={() => exportCSV(data.items.map(e => ({
              event_id: e.event_id,
              event_type: e.event_type,
              status: e.status,
              processed_at: e.processed_at || '',
              created_at: e.created_at,
            })), 'webhook_events')}
            className="flex items-center gap-1.5 px-3 py-1.5 text-sm text-gray-600 border border-gray-300 rounded-md hover:bg-gray-50"
          >
            <Download size={14} /> Export CSV
          </button>
        ) : null}
      </div>

      <div className="flex gap-3 mb-4">
        <input type="text" placeholder="Event type..." value={eventType}
          onChange={(e) => { setEventType(e.target.value); setPage(1) }}
          className="px-3 py-2 border border-gray-300 rounded-md text-sm w-48" />
        <select value={status} onChange={(e) => { setStatus(e.target.value); setPage(1) }}
          className="px-3 py-2 border border-gray-300 rounded-md text-sm bg-white">
          <option value="">All Status</option>
          <option value="processing">Processing</option>
          <option value="processed">Processed</option>
          <option value="failed">Failed</option>
        </select>
        {(eventType || status) && (
          <button onClick={() => { setEventType(''); setStatus(''); setPage(1) }} className="px-3 py-2 text-sm text-gray-500 hover:text-gray-700">
            Clear filters
          </button>
        )}
      </div>

      {isLoading ? <SkeletonTable rows={6} /> : !data?.items?.length ? <EmptyState message="No webhook events" description="Webhook events are recorded when Stripe sends payment notifications" /> : (
        <>
          <div className="bg-white rounded-lg border border-gray-200 overflow-hidden">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-gray-50 border-b">
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Event ID</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Type</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Status</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Processed At</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Created</th>
                </tr>
              </thead>
              <tbody>
                {data.items.map((evt) => (
                  <tr key={evt.id} className="border-b last:border-0 hover:bg-gray-50">
                    <td className="px-4 py-3 font-mono text-xs text-gray-700">{evt.event_id}</td>
                    <td className="px-4 py-3"><span className="font-mono text-xs text-gray-700">{evt.event_type}</span></td>
                    <td className="px-4 py-3"><StatusBadge status={evt.status} /></td>
                    <td className="px-4 py-3 text-gray-500">{evt.processed_at ? formatDate(evt.processed_at) : '-'}</td>
                    <td className="px-4 py-3 text-gray-500">{formatDate(evt.created_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Pagination page={page} totalPages={data.total_pages} total={data.total} onPageChange={setPage} />
        </>
      )}
    </div>
  )
}
