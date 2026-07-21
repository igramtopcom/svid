import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { getOverview, getTopEvents, listEvents, getDownloadStats } from '@/api/analytics'
import { useBrandStore } from '@/store/brand'
import StatsCard from '@/components/common/StatsCard'
import Pagination from '@/components/common/Pagination'
import { SkeletonTable } from '@/components/common/LoadingSpinner'
import EmptyState from '@/components/common/EmptyState'
import BrandBadge from '@/components/common/BrandBadge'
import { formatDate } from '@/lib/utils'
import { BarChart3, Activity, Monitor, Download, CheckCircle, XCircle, X } from 'lucide-react'
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, PieChart, Pie, Cell, LineChart, Line, CartesianGrid, Legend } from 'recharts'

const COLORS = ['#c8294f', '#3b82f6', '#f59e0b', '#ef4444', '#8b5cf6', '#ec4899', '#06b6d4', '#84cc16']

export default function Analytics() {
  const [page, setPage] = useState(1)
  const [eventType, setEventType] = useState('')
  const brand = useBrandStore((s) => s.brand)
  const [os, setOs] = useState('')
  const [appVersion, setAppVersion] = useState('')

  const { data: overview, isLoading: loadingOverview } = useQuery({
    queryKey: ['analytics-overview', brand],
    queryFn: () => getOverview(brand || undefined),
  })

  const { data: topEvents } = useQuery({
    queryKey: ['top-events', brand],
    queryFn: () => getTopEvents(10, brand || undefined),
  })

  const { data: downloadStats } = useQuery({
    queryKey: ['download-stats', brand],
    queryFn: () => getDownloadStats(30, brand || undefined),
  })

  const { data: events, isLoading: loadingEvents } = useQuery({
    queryKey: ['analytics-events', page, eventType, os, appVersion, brand],
    queryFn: () => listEvents({
      page, per_page: 20,
      event_type: eventType || undefined,
      os: os || undefined,
      app_version: appVersion || undefined,
      brand: brand || undefined,
    }),
  })

  const osPieData = overview?.by_os
    ? Object.entries(overview.by_os).map(([name, value]) => ({ name, value }))
    : []

  const topEventsData = topEvents?.map((e) => ({ name: e.event_type, count: e.count })) || []

  const hasFilters = eventType || os || appVersion

  return (
    <div>
      <h2 className="text-xl font-bold mb-6">Analytics<BrandBadge /></h2>

      {/* Overview Stats */}
      {!loadingOverview && overview && (
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
          <StatsCard title="Total Events" value={overview.total_events} icon={<BarChart3 size={24} />} />
          <StatsCard title="Events Today" value={overview.events_today} icon={<Activity size={24} />} />
          <StatsCard title="Active Devices Today" value={overview.active_devices_today} icon={<Monitor size={24} />} />
        </div>
      )}

      {/* Download Stats */}
      {downloadStats && (
        <>
          <h3 className="text-lg font-semibold mb-3">Download Analytics</h3>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
            <StatsCard title="Total Downloads" value={downloadStats.total_downloads} icon={<Download size={24} />} />
            <StatsCard title="Successful" value={downloadStats.success_count} icon={<CheckCircle size={24} />} />
            <StatsCard title="Errors" value={downloadStats.error_count} icon={<XCircle size={24} />} />
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
            {/* Daily Trend */}
            {downloadStats.daily_trend?.length > 0 && (
              <div className="bg-white rounded-lg border border-gray-200 p-5">
                <h4 className="text-sm font-semibold text-gray-700 mb-4">
                  Download Trend (30d) — {downloadStats.success_rate.toFixed(1)}% success rate
                </h4>
                <ResponsiveContainer width="100%" height={250}>
                  <LineChart data={downloadStats.daily_trend}>
                    <CartesianGrid strokeDasharray="3 3" />
                    <XAxis dataKey="date" fontSize={10} tickFormatter={(d) => d.slice(5)} />
                    <YAxis fontSize={12} />
                    <Tooltip />
                    <Legend />
                    <Line type="monotone" dataKey="success" stroke="#22c55e" strokeWidth={2} dot={false} />
                    <Line type="monotone" dataKey="errors" stroke="#ef4444" strokeWidth={2} dot={false} />
                  </LineChart>
                </ResponsiveContainer>
              </div>
            )}

            {/* By Platform */}
            {downloadStats.by_platform?.length > 0 && (
              <div className="bg-white rounded-lg border border-gray-200 p-5">
                <h4 className="text-sm font-semibold text-gray-700 mb-4">Downloads by Platform</h4>
                <ResponsiveContainer width="100%" height={250}>
                  <BarChart data={downloadStats.by_platform} layout="vertical">
                    <XAxis type="number" fontSize={12} />
                    <YAxis type="category" dataKey="platform" fontSize={11} width={100} />
                    <Tooltip />
                    <Bar dataKey="success" stackId="a" fill="#22c55e" />
                    <Bar dataKey="errors" stackId="a" fill="#ef4444" />
                  </BarChart>
                </ResponsiveContainer>
              </div>
            )}
          </div>
        </>
      )}

      {/* Charts */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
        {topEventsData.length > 0 && (
          <div className="bg-white rounded-lg border border-gray-200 p-5">
            <h3 className="text-sm font-semibold text-gray-700 mb-4">Top Event Types</h3>
            <ResponsiveContainer width="100%" height={300}>
              <BarChart data={topEventsData} layout="vertical">
                <XAxis type="number" fontSize={12} />
                <YAxis type="category" dataKey="name" fontSize={11} width={120} />
                <Tooltip />
                <Bar dataKey="count" fill="#c8294f" radius={[0, 4, 4, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </div>
        )}

        {osPieData.length > 0 && (
          <div className="bg-white rounded-lg border border-gray-200 p-5">
            <h3 className="text-sm font-semibold text-gray-700 mb-4">Events by OS</h3>
            <ResponsiveContainer width="100%" height={300}>
              <PieChart>
                <Pie
                  data={osPieData}
                  cx="50%"
                  cy="50%"
                  innerRadius={60}
                  outerRadius={110}
                  dataKey="value"
                  label={({ name, value }) => `${name}: ${value}`}
                >
                  {osPieData.map((_, i) => (
                    <Cell key={i} fill={COLORS[i % COLORS.length]} />
                  ))}
                </Pie>
                <Tooltip />
              </PieChart>
            </ResponsiveContainer>
          </div>
        )}
      </div>

      {/* Event Log */}
      <div className="mb-4">
        <h3 className="text-lg font-semibold mb-3">
          Event Log
          {events?.total != null && <span className="text-sm font-normal text-gray-400 ml-2">({events.total})</span>}
        </h3>
        <div className="flex flex-wrap gap-3 mb-3">
          <input
            type="text"
            value={eventType}
            onChange={(e) => { setEventType(e.target.value); setPage(1) }}
            placeholder="Filter by event type..."
            className="px-3 py-2 border border-gray-300 rounded-md text-sm w-64 focus:outline-none focus:ring-2 focus:ring-brand-500"
          />
          <select value={os} onChange={(e) => { setOs(e.target.value); setPage(1) }} className="px-3 py-2 border border-gray-300 rounded-md text-sm">
            <option value="">All OS</option>
            <option value="macos">macOS</option>
            <option value="windows">Windows</option>
            <option value="linux">Linux</option>
          </select>
          <input
            type="text"
            value={appVersion}
            onChange={(e) => { setAppVersion(e.target.value); setPage(1) }}
            placeholder="App version..."
            className="px-3 py-2 border border-gray-300 rounded-md text-sm w-32 focus:outline-none focus:ring-2 focus:ring-brand-500"
          />
          {hasFilters && (
            <button
              onClick={() => { setEventType(''); setOs(''); setAppVersion(''); setPage(1) }}
              className="flex items-center gap-1 px-3 py-2 text-sm text-gray-500 hover:text-gray-700"
            >
              <X size={14} /> Clear
            </button>
          )}
        </div>

        {loadingEvents ? <SkeletonTable rows={6} /> : !events?.items?.length ? <EmptyState message="No events" description="Analytics events are recorded when users interact with the app" /> : (
          <>
            <div className="bg-white rounded-lg border border-gray-200 overflow-hidden">
              <table className="w-full text-sm">
                <thead>
                  <tr className="bg-gray-50 border-b">
                    <th className="text-left px-4 py-3 font-medium text-gray-600">Event Type</th>
                    <th className="text-left px-4 py-3 font-medium text-gray-600">Data</th>
                    <th className="text-left px-4 py-3 font-medium text-gray-600">OS</th>
                    <th className="text-left px-4 py-3 font-medium text-gray-600">Version</th>
                    <th className="text-left px-4 py-3 font-medium text-gray-600">Date</th>
                  </tr>
                </thead>
                <tbody>
                  {events.items.map((evt) => (
                    <tr key={evt.id} className="border-b last:border-0 hover:bg-gray-50">
                      <td className="px-4 py-3 font-mono text-sm">{evt.event_type}</td>
                      <td className="px-4 py-3 text-gray-600 text-xs font-mono max-w-xs truncate">{evt.event_data || '-'}</td>
                      <td className="px-4 py-3 text-gray-600">{evt.os}</td>
                      <td className="px-4 py-3 text-gray-600">{evt.app_version}</td>
                      <td className="px-4 py-3 text-gray-500">{formatDate(evt.created_at)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <Pagination page={page} totalPages={events.total_pages} total={events.total} onPageChange={setPage} />
          </>
        )}
      </div>
    </div>
  )
}
