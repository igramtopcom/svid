import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { listCrashGroups, getCrashGroupStats } from '@/api/bugs'
import { useBrandStore } from '@/store/brand'
import StatusBadge from '@/components/common/StatusBadge'
import Pagination from '@/components/common/Pagination'
import { SkeletonTable } from '@/components/common/LoadingSpinner'
import EmptyState from '@/components/common/EmptyState'
import BrandBadge from '@/components/common/BrandBadge'
import { formatDate, truncate } from '@/lib/utils'
import { Download } from 'lucide-react'
import { exportCSV } from '@/lib/export'

const STATUS_TABS = ['', 'new', 'investigating', 'fixing', 'resolved', 'wont_fix']
const STATUS_LABELS: Record<string, string> = {
  '': 'All',
  new: 'New',
  investigating: 'Investigating',
  fixing: 'Fixing',
  resolved: 'Resolved',
  wont_fix: "Won't Fix",
}

export default function CrashGroupList() {
  const [page, setPage] = useState(1)
  const [status, setStatus] = useState('')
  const [severity, setSeverity] = useState('')
  const [search, setSearch] = useState('')
  const brand = useBrandStore((s) => s.brand)
  const navigate = useNavigate()

  const { data: stats } = useQuery({
    queryKey: ['crash-group-stats', brand],
    queryFn: () => getCrashGroupStats(brand || undefined),
  })

  const { data, isLoading } = useQuery({
    queryKey: ['crash-groups', page, status, severity, search, brand],
    queryFn: () => listCrashGroups({
      page,
      per_page: 20,
      status: status || undefined,
      severity: severity || undefined,
      search: search || undefined,
      brand: brand || undefined,
    }),
  })

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-xl font-bold">
          Crash Groups<BrandBadge />
          {data?.total != null && <span className="text-sm font-normal text-gray-400 ml-2">({data.total})</span>}
        </h2>
        {data?.items?.length ? (
          <button
            onClick={() => exportCSV(data.items.map(g => ({
              id: g.id,
              title: g.title,
              severity: g.severity,
              status: g.status,
              crash_count: g.crash_count,
              device_count: g.device_count,
              platforms: g.platforms,
              last_seen_at: g.last_seen_at,
            })), 'crash_groups')}
            className="flex items-center gap-1.5 px-3 py-1.5 text-sm text-gray-600 border border-gray-300 rounded-md hover:bg-gray-50"
          >
            <Download size={14} /> Export CSV
          </button>
        ) : null}
      </div>

      {/* Stats Cards */}
      {stats && (
        <div className="grid grid-cols-4 gap-4 mb-6">
          <div className="bg-white p-4 rounded-lg border border-gray-200">
            <p className="text-sm text-gray-500">Total Groups</p>
            <p className="text-2xl font-bold">{stats.total_groups}</p>
          </div>
          <div className="bg-white p-4 rounded-lg border border-gray-200">
            <p className="text-sm text-gray-500">Active</p>
            <p className="text-2xl font-bold text-orange-600">{stats.active_groups}</p>
          </div>
          <div className="bg-white p-4 rounded-lg border border-gray-200">
            <p className="text-sm text-gray-500">Resolved</p>
            <p className="text-2xl font-bold text-green-600">{stats.by_status?.resolved || 0}</p>
          </div>
          <div className="bg-white p-4 rounded-lg border border-gray-200">
            <p className="text-sm text-gray-500">Critical</p>
            <p className="text-2xl font-bold text-red-600">{stats.by_severity?.critical || 0}</p>
          </div>
        </div>
      )}

      {/* Status Tabs */}
      <div className="flex gap-1 mb-4 border-b border-gray-200">
        {STATUS_TABS.map((s) => (
          <button
            key={s}
            onClick={() => { setStatus(s); setPage(1) }}
            className={`px-4 py-2 text-sm font-medium border-b-2 transition-colors ${
              status === s
                ? 'border-brand-600 text-brand-600'
                : 'border-transparent text-gray-500 hover:text-gray-700'
            }`}
          >
            {STATUS_LABELS[s]}
          </button>
        ))}
      </div>

      {/* Filters */}
      <div className="flex flex-wrap gap-3 mb-4">
        <select
          value={severity}
          onChange={(e) => { setSeverity(e.target.value); setPage(1) }}
          className="px-3 py-2 border border-gray-300 rounded-md text-sm bg-white"
        >
          <option value="">All Severities</option>
          <option value="critical">Critical</option>
          <option value="high">High</option>
          <option value="medium">Medium</option>
          <option value="low">Low</option>
        </select>

        <input
          type="text"
          placeholder="Search title..."
          value={search}
          onChange={(e) => { setSearch(e.target.value); setPage(1) }}
          className="px-3 py-2 border border-gray-300 rounded-md text-sm w-64"
        />
        {(severity || status || search) && (
          <button onClick={() => { setSeverity(''); setStatus(''); setSearch(''); setPage(1) }} className="px-3 py-2 text-sm text-gray-500 hover:text-gray-700">
            Clear filters
          </button>
        )}
      </div>

      {isLoading ? (
        <SkeletonTable rows={6} />
      ) : !data?.items?.length ? (
        <EmptyState message="No crash groups found" description="Crash groups are created automatically when devices report crashes" />
      ) : (
        <>
          <div className="bg-white rounded-lg border border-gray-200 overflow-hidden">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-gray-50 border-b">
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Severity</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Title</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Status</th>
                  <th className="text-right px-4 py-3 font-medium text-gray-600">Crashes</th>
                  <th className="text-right px-4 py-3 font-medium text-gray-600">Devices</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Platforms</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Last Seen</th>
                </tr>
              </thead>
              <tbody>
                {data.items.map((group) => (
                  <tr
                    key={group.id}
                    className="border-b last:border-0 hover:bg-gray-50 cursor-pointer"
                    onClick={() => navigate(`/crash-groups/${group.id}`)}
                  >
                    <td className="px-4 py-3"><StatusBadge status={group.severity} /></td>
                    <td className="px-4 py-3 text-indigo-600 hover:underline font-medium">
                      {truncate(group.title, 60)}
                    </td>
                    <td className="px-4 py-3"><StatusBadge status={group.status} /></td>
                    <td className="px-4 py-3 text-right font-mono">{group.crash_count}</td>
                    <td className="px-4 py-3 text-right font-mono">{group.device_count}</td>
                    <td className="px-4 py-3 text-gray-600 text-xs">{group.platforms}</td>
                    <td className="px-4 py-3 text-gray-500">{formatDate(group.last_seen_at)}</td>
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
