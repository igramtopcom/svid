import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { listBugs } from '@/api/bugs'
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

export default function BugList() {
  const navigate = useNavigate()
  const [page, setPage] = useState(1)
  const [status, setStatus] = useState('')
  const [priority, setPriority] = useState('')
  const brand = useBrandStore((s) => s.brand)
  const [os, setOs] = useState('')
  const [searchInput, setSearchInput] = useState('')
  const search = useDebounce(searchInput)

  const { data, isLoading } = useQuery({
    queryKey: ['bugs', page, status, priority, os, search, brand],
    queryFn: () => listBugs({
      page, per_page: 20,
      status: status || undefined,
      priority: priority || undefined,
      os: os || undefined,
      search: search || undefined,
      brand: brand || undefined,
    }),
  })

  const hasFilters = status || priority || os || searchInput
  const clearAll = () => { setStatus(''); setPriority(''); setOs(''); setSearchInput(''); setPage(1) }

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-xl font-bold">
          Bug Reports<BrandBadge />
          {data?.total != null && <span className="text-sm font-normal text-gray-400 ml-2">({data.total})</span>}
        </h2>
        {data?.items?.length ? (
          <button
            onClick={() => exportCSV(data.items.map(b => ({
              id: b.id, title: b.title, priority: b.priority, status: b.status,
              os: b.os, app_version: b.app_version, created_at: b.created_at,
            })), 'bug_reports')}
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
          <option value="new">New</option>
          <option value="triaging">Triaging</option>
          <option value="in_progress">In Progress</option>
          <option value="resolved">Resolved</option>
          <option value="closed">Closed</option>
        </select>
        <select value={priority} onChange={(e) => { setPriority(e.target.value); setPage(1) }} className="px-3 py-2 border border-gray-300 rounded-md text-sm">
          <option value="">All Priority</option>
          <option value="critical">Critical</option>
          <option value="high">High</option>
          <option value="medium">Medium</option>
          <option value="low">Low</option>
        </select>
        <select value={os} onChange={(e) => { setOs(e.target.value); setPage(1) }} className="px-3 py-2 border border-gray-300 rounded-md text-sm">
          <option value="">All OS</option>
          <option value="macos">macOS</option>
          <option value="windows">Windows</option>
          <option value="linux">Linux</option>
        </select>
        {hasFilters && (
          <button onClick={clearAll} className="px-3 py-2 text-sm text-gray-500 hover:text-gray-700">
            Clear filters
          </button>
        )}
      </div>

      {isLoading ? (
        <SkeletonTable rows={6} />
      ) : !data?.items?.length ? (
        <EmptyState message="No bug reports" description={hasFilters ? "Try adjusting your filters" : "Bug reports appear when users submit reports from the app"} />
      ) : (
        <>
          <div className="bg-white rounded-lg border border-gray-200 overflow-hidden">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-gray-50 border-b">
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Title</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Priority</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Status</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">OS</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Version</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Date</th>
                </tr>
              </thead>
              <tbody>
                {data.items.map((bug) => (
                  <tr key={bug.id} className="border-b last:border-0 hover:bg-gray-50 cursor-pointer" onClick={() => navigate(`/bugs/${bug.id}`)}>
                    <td className="px-4 py-3">
                      <span className="text-brand-600 font-medium">
                        {truncate(bug.title, 60)}
                      </span>
                    </td>
                    <td className="px-4 py-3"><StatusBadge status={bug.priority} /></td>
                    <td className="px-4 py-3"><StatusBadge status={bug.status} /></td>
                    <td className="px-4 py-3 text-gray-600">{bug.os}</td>
                    <td className="px-4 py-3 text-gray-600">{bug.app_version}</td>
                    <td className="px-4 py-3 text-gray-500">{formatDate(bug.created_at)}</td>
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
