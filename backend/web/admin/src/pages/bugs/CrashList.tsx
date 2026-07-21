import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { listCrashes } from '@/api/bugs'
import { useBrandStore } from '@/store/brand'
import StatusBadge from '@/components/common/StatusBadge'
import Pagination from '@/components/common/Pagination'
import { SkeletonTable } from '@/components/common/LoadingSpinner'
import EmptyState from '@/components/common/EmptyState'
import BrandBadge from '@/components/common/BrandBadge'
import { formatDate, truncate } from '@/lib/utils'
import { Download } from 'lucide-react'
import { exportCSV } from '@/lib/export'

export default function CrashList() {
  const [page, setPage] = useState(1)
  const [severity, setSeverity] = useState('')
  const [os, setOs] = useState('')
  const [appVersion, setAppVersion] = useState('')
  const brand = useBrandStore((s) => s.brand)
  const navigate = useNavigate()

  const { data, isLoading } = useQuery({
    queryKey: ['crashes', page, severity, os, appVersion, brand],
    queryFn: () => listCrashes({
      page,
      per_page: 20,
      severity: severity || undefined,
      os: os || undefined,
      app_version: appVersion || undefined,
      brand: brand || undefined,
    }),
  })

  const resetFilters = () => {
    setSeverity('')
    setOs('')
    setAppVersion('')
    setPage(1)
  }

  const hasFilters = severity || os || appVersion

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-xl font-bold">
          Crash Reports<BrandBadge />
          {data?.total != null && <span className="text-sm font-normal text-gray-400 ml-2">({data.total})</span>}
        </h2>
        {data?.items?.length ? (
          <button
            onClick={() => exportCSV(data.items.map(c => ({
              id: c.id,
              severity: c.severity || 'medium',
              error_message: c.error_message,
              os: `${c.os} ${c.os_version}`,
              app_version: c.app_version,
              created_at: c.created_at,
            })), 'crash_reports')}
            className="flex items-center gap-1.5 px-3 py-1.5 text-sm text-gray-600 border border-gray-300 rounded-md hover:bg-gray-50"
          >
            <Download size={14} /> Export CSV
          </button>
        ) : null}
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

        <select
          value={os}
          onChange={(e) => { setOs(e.target.value); setPage(1) }}
          className="px-3 py-2 border border-gray-300 rounded-md text-sm bg-white"
        >
          <option value="">All OS</option>
          <option value="macos">macOS</option>
          <option value="windows">Windows</option>
          <option value="linux">Linux</option>
        </select>

        <input
          type="text"
          placeholder="App version..."
          value={appVersion}
          onChange={(e) => { setAppVersion(e.target.value); setPage(1) }}
          className="px-3 py-2 border border-gray-300 rounded-md text-sm w-36"
        />

        {hasFilters && (
          <button onClick={resetFilters} className="px-3 py-2 text-sm text-gray-500 hover:text-gray-700">
            Clear filters
          </button>
        )}
      </div>

      {isLoading ? (
        <SkeletonTable rows={6} />
      ) : !data?.items?.length ? (
        <EmptyState message="No crash reports" description="Crashes are recorded automatically when the app encounters fatal errors" />
      ) : (
        <>
          <div className="bg-white rounded-lg border border-gray-200 overflow-hidden">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-gray-50 border-b">
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Severity</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Message</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">OS</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Version</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Date</th>
                </tr>
              </thead>
              <tbody>
                {data.items.map((crash) => (
                  <tr
                    key={crash.id}
                    className="border-b last:border-0 hover:bg-gray-50 cursor-pointer"
                    onClick={() => navigate(`/crashes/${crash.id}`)}
                  >
                    <td className="px-4 py-3"><StatusBadge status={crash.severity || 'medium'} /></td>
                    <td className="px-4 py-3 text-indigo-600 hover:underline">{truncate(crash.error_message, 60)}</td>
                    <td className="px-4 py-3 text-gray-600">{crash.os} {crash.os_version}</td>
                    <td className="px-4 py-3 text-gray-600">{crash.app_version}</td>
                    <td className="px-4 py-3 text-gray-500">{formatDate(crash.created_at)}</td>
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
