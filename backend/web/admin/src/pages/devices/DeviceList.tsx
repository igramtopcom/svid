import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { listDevices } from '@/api/devices'
import { useBrandStore } from '@/store/brand'
import StatusBadge from '@/components/common/StatusBadge'
import Pagination from '@/components/common/Pagination'
import { SkeletonTable } from '@/components/common/LoadingSpinner'
import EmptyState from '@/components/common/EmptyState'
import BrandBadge from '@/components/common/BrandBadge'
import { timeAgo } from '@/lib/utils'
import { Search, Download } from 'lucide-react'
import { exportCSV } from '@/lib/export'

export default function DeviceList() {
  const navigate = useNavigate()
  const [page, setPage] = useState(1)
  const [os, setOs] = useState('')
  const [tier, setTier] = useState('')
  const [search, setSearch] = useState('')
  const brand = useBrandStore((s) => s.brand)

  const { data, isLoading } = useQuery({
    queryKey: ['devices', page, os, tier, search, brand],
    queryFn: () => listDevices({ page, per_page: 20, os: os || undefined, tier: tier || undefined, search: search || undefined, brand: brand || undefined }),
  })

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-xl font-bold">
          Devices<BrandBadge />
          {data?.total != null && <span className="text-sm font-normal text-gray-400 ml-2">({data.total})</span>}
        </h2>
        {data?.items?.length ? (
          <button
            onClick={() => exportCSV(data.items.map(d => ({
              device_name: d.device_name || '',
              hardware_id: d.hardware_id,
              os: d.os,
              os_version: d.os_version,
              app_version: d.app_version,
              tier: d.tier,
              status: d.is_active ? 'active' : 'inactive',
              last_seen_at: d.last_seen_at,
              created_at: d.created_at,
            })), 'devices')}
            className="flex items-center gap-1.5 px-3 py-1.5 text-sm text-gray-600 border border-gray-300 rounded-md hover:bg-gray-50"
          >
            <Download size={14} /> Export CSV
          </button>
        ) : null}
      </div>

      {/* Filters */}
      <div className="flex flex-wrap gap-3 mb-4">
        <div className="relative">
          <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400" />
          <input
            type="text"
            placeholder="Search hardware ID or name..."
            value={search}
            onChange={(e) => { setSearch(e.target.value); setPage(1) }}
            className="pl-9 pr-3 py-2 border border-gray-300 rounded-md text-sm w-64 focus:outline-none focus:ring-2 focus:ring-brand-500"
          />
        </div>
        <select
          value={os}
          onChange={(e) => { setOs(e.target.value); setPage(1) }}
          className="px-3 py-2 border border-gray-300 rounded-md text-sm"
        >
          <option value="">All OS</option>
          <option value="windows">Windows</option>
          <option value="macos">macOS</option>
          <option value="linux">Linux</option>
        </select>
        <select
          value={tier}
          onChange={(e) => { setTier(e.target.value); setPage(1) }}
          className="px-3 py-2 border border-gray-300 rounded-md text-sm"
        >
          <option value="">All Tiers</option>
          <option value="free">Free</option>
          <option value="pro">Pro</option>
          <option value="enterprise">Enterprise</option>
        </select>
        {(search || os || tier) && (
          <button onClick={() => { setSearch(''); setOs(''); setTier(''); setPage(1) }} className="px-3 py-2 text-sm text-gray-500 hover:text-gray-700">
            Clear filters
          </button>
        )}
      </div>

      {isLoading ? (
        <SkeletonTable rows={8} />
      ) : !data?.items?.length ? (
        <EmptyState message="No devices found" description="Devices appear when users install and register the SSvid app" />
      ) : (
        <>
          <div className="bg-white rounded-lg border border-gray-200 overflow-hidden">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-gray-50 border-b">
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Device</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">OS</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Version</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Tier</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Status</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Last Seen</th>
                </tr>
              </thead>
              <tbody>
                {data.items.map((device) => (
                  <tr key={device.id} className="border-b last:border-0 hover:bg-gray-50 cursor-pointer" onClick={() => navigate(`/devices/${device.id}`)}>
                    <td className="px-4 py-3">
                      <span className="text-brand-600 font-medium">
                        {device.device_name || device.hardware_id}
                      </span>
                      <p className="text-xs text-gray-400 mt-0.5">{device.hardware_id}</p>
                    </td>
                    <td className="px-4 py-3 text-gray-600">
                      {device.os} {device.os_version}
                    </td>
                    <td className="px-4 py-3 text-gray-600">{device.app_version}</td>
                    <td className="px-4 py-3">
                      <StatusBadge status={device.tier} />
                    </td>
                    <td className="px-4 py-3">
                      <StatusBadge status={device.is_active ? 'active' : 'inactive'} />
                    </td>
                    <td className="px-4 py-3 text-gray-500">{timeAgo(device.last_seen_at)}</td>
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
