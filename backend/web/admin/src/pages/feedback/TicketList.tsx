import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { listTickets } from '@/api/feedback'
import { useBrandStore } from '@/store/brand'
import StatusBadge from '@/components/common/StatusBadge'
import Pagination from '@/components/common/Pagination'
import { SkeletonTable } from '@/components/common/LoadingSpinner'
import EmptyState from '@/components/common/EmptyState'
import BrandBadge from '@/components/common/BrandBadge'
import { useDebounce } from '@/hooks/useDebounce'
import { formatDate, truncate } from '@/lib/utils'
import { Download, Search, X } from 'lucide-react'
import { exportCSV } from '@/lib/export'

export default function TicketList() {
  const navigate = useNavigate()
  const [page, setPage] = useState(1)
  const [status, setStatus] = useState('')
  const [category, setCategory] = useState('')
  const brand = useBrandStore((s) => s.brand)
  const [searchInput, setSearchInput] = useState('')
  const search = useDebounce(searchInput)

  const { data, isLoading } = useQuery({
    queryKey: ['tickets', page, status, category, search, brand],
    queryFn: () => listTickets({
      page, per_page: 20,
      status: status || undefined,
      category: category || undefined,
      search: search || undefined,
      brand: brand || undefined,
    }),
  })

  const hasFilters = status || category || searchInput
  const clearAll = () => { setStatus(''); setCategory(''); setSearchInput(''); setPage(1) }

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-xl font-bold">
          Support Tickets<BrandBadge />
          {data?.total != null && <span className="text-sm font-normal text-gray-400 ml-2">({data.total})</span>}
        </h2>
        {data?.items?.length ? (
          <button
            onClick={() => exportCSV(data.items.map(t => ({
              id: t.id, subject: t.subject, category: t.category, status: t.status, created_at: t.created_at,
            })), 'tickets')}
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
            placeholder="Search by subject..."
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
          <option value="in_progress">In Progress</option>
          <option value="waiting_for_customer">Waiting for Customer</option>
          <option value="resolved">Resolved</option>
          <option value="closed">Closed</option>
        </select>
        <select value={category} onChange={(e) => { setCategory(e.target.value); setPage(1) }} className="px-3 py-2 border border-gray-300 rounded-md text-sm">
          <option value="">All Categories</option>
          <option value="general">General</option>
          <option value="bug">Bug</option>
          <option value="feature">Feature</option>
          <option value="billing">Billing</option>
          <option value="other">Other</option>
        </select>
        {hasFilters && (
          <button onClick={clearAll} className="px-3 py-2 text-sm text-gray-500 hover:text-gray-700">
            Clear filters
          </button>
        )}
      </div>

      {isLoading ? <SkeletonTable rows={6} /> : !data?.items?.length ? (
        <EmptyState message="No support tickets" description={hasFilters ? "Try adjusting your filters" : "Tickets appear when users submit support requests from the app"} />
      ) : (
        <>
          <div className="bg-white rounded-lg border border-gray-200 overflow-hidden">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-gray-50 border-b">
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Subject</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Category</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Status</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Date</th>
                </tr>
              </thead>
              <tbody>
                {data.items.map((ticket) => (
                  <tr key={ticket.id} className="border-b last:border-0 hover:bg-gray-50 cursor-pointer" onClick={() => navigate(`/tickets/${ticket.id}`)}>
                    <td className="px-4 py-3">
                      <span className="text-brand-600 font-medium">
                        {truncate(ticket.subject, 60)}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-gray-600 capitalize">{ticket.category}</td>
                    <td className="px-4 py-3"><StatusBadge status={ticket.status} /></td>
                    <td className="px-4 py-3 text-gray-500">{formatDate(ticket.created_at)}</td>
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
