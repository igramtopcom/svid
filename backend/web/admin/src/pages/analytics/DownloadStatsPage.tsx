import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { getDownloadStats } from '@/api/analytics'
import { useBrandStore } from '@/store/brand'
import StatsCard from '@/components/common/StatsCard'
import { PageSkeleton } from '@/components/common/LoadingSpinner'
import { Download, CheckCircle, XCircle, Percent } from 'lucide-react'
import BrandBadge from '@/components/common/BrandBadge'
import PeriodSelector from '@/components/common/PeriodSelector'
import {
  BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer,
  AreaChart, Area, CartesianGrid, Legend,
} from 'recharts'

export default function DownloadStatsPage() {
  const [days, setDays] = useState(30)
  const brand = useBrandStore((s) => s.brand)

  const { data: stats, isLoading } = useQuery({
    queryKey: ['download-stats', days, brand],
    queryFn: () => getDownloadStats(days, brand || undefined),
  })

  if (isLoading) return <PageSkeleton cards={4} tableRows={4} />
  if (!stats) return null

  const dailyData = (stats.daily_trend || []).map((d) => ({
    date: d.date ? new Date(d.date).toLocaleDateString('en-US', { month: 'numeric', day: 'numeric' }) : '',
    total: d.total,
    success: d.success,
    errors: d.errors,
  }))

  const platformData = (stats.by_platform || [])
    .sort((a, b) => b.total - a.total)
    .slice(0, 15)

  const osEntries = stats.by_os ? Object.entries(stats.by_os).sort((a, b) => b[1] - a[1]) : []

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-xl font-bold">Download Statistics<BrandBadge /></h2>
        <PeriodSelector value={days} onChange={setDays} options={[7, 30, 90, 365]} />
      </div>

      {/* Summary Stats */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
        <StatsCard title="Total Downloads" value={stats.total_downloads.toLocaleString()} icon={<Download size={24} />} />
        <StatsCard title="Successful" value={stats.success_count.toLocaleString()} icon={<CheckCircle size={24} />} />
        <StatsCard title="Errors" value={stats.error_count.toLocaleString()} icon={<XCircle size={24} />} />
        <StatsCard title="Success Rate" value={`${stats.success_rate.toFixed(1)}%`} icon={<Percent size={24} />} />
      </div>

      {/* Daily Trend Chart */}
      {dailyData.length > 0 && (
        <div className="bg-white rounded-lg border border-gray-200 p-5 mb-6">
          <h3 className="text-sm font-semibold text-gray-700 mb-4">Daily Downloads (last {days} days)</h3>
          <ResponsiveContainer width="100%" height={300}>
            <AreaChart data={dailyData}>
              <defs>
                <linearGradient id="successGradient" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#10b981" stopOpacity={0.3} />
                  <stop offset="95%" stopColor="#10b981" stopOpacity={0} />
                </linearGradient>
                <linearGradient id="errorGradient" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#ef4444" stopOpacity={0.3} />
                  <stop offset="95%" stopColor="#ef4444" stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
              <XAxis dataKey="date" fontSize={12} />
              <YAxis fontSize={12} />
              <Tooltip />
              <Legend />
              <Area type="monotone" dataKey="success" stroke="#10b981" fill="url(#successGradient)" strokeWidth={2} name="Success" />
              <Area type="monotone" dataKey="errors" stroke="#ef4444" fill="url(#errorGradient)" strokeWidth={2} name="Errors" />
            </AreaChart>
          </ResponsiveContainer>
        </div>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
        {/* By Platform */}
        {platformData.length > 0 && (
          <div className="bg-white rounded-lg border border-gray-200 p-5">
            <h3 className="text-sm font-semibold text-gray-700 mb-4">Downloads by Platform</h3>
            <ResponsiveContainer width="100%" height={Math.max(280, platformData.length * 30)}>
              <BarChart data={platformData} layout="vertical">
                <XAxis type="number" fontSize={12} />
                <YAxis type="category" dataKey="platform" fontSize={11} width={100} />
                <Tooltip
                  formatter={(value: number, name: string) => {
                    if (name === 'success') return [value, 'Success']
                    if (name === 'errors') return [value, 'Errors']
                    return [value, name]
                  }}
                />
                <Legend />
                <Bar dataKey="success" stackId="a" fill="#10b981" name="success" />
                <Bar dataKey="errors" stackId="a" fill="#ef4444" name="errors" />
              </BarChart>
            </ResponsiveContainer>
          </div>
        )}

        {/* By OS */}
        {osEntries.length > 0 && (
          <div className="bg-white rounded-lg border border-gray-200 p-5">
            <h3 className="text-sm font-semibold text-gray-700 mb-4">Downloads by OS</h3>
            <div className="space-y-3">
              {osEntries.map(([os, count]) => {
                const total = osEntries.reduce((s, [, c]) => s + c, 0)
                const pct = total > 0 ? (count / total) * 100 : 0
                return (
                  <div key={os}>
                    <div className="flex justify-between text-sm mb-1">
                      <span className="font-medium capitalize">{os || 'Unknown'}</span>
                      <span className="text-gray-500">{count.toLocaleString()} ({pct.toFixed(1)}%)</span>
                    </div>
                    <div className="w-full bg-gray-100 rounded-full h-2">
                      <div
                        className="bg-[#c8294f] h-2 rounded-full transition-all"
                        style={{ width: `${pct}%` }}
                      />
                    </div>
                  </div>
                )
              })}
            </div>
          </div>
        )}
      </div>

      {/* Platform Table */}
      {platformData.length > 0 && (
        <div className="bg-white rounded-lg border border-gray-200">
          <div className="p-4 border-b border-gray-200">
            <h3 className="text-sm font-semibold text-gray-700">Platform Breakdown</h3>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-gray-50 text-gray-500 uppercase text-xs">
                <tr>
                  <th className="px-4 py-3 text-left">Platform</th>
                  <th className="px-4 py-3 text-right">Total</th>
                  <th className="px-4 py-3 text-right">Success</th>
                  <th className="px-4 py-3 text-right">Errors</th>
                  <th className="px-4 py-3 text-right">Success Rate</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-200">
                {platformData.map((p) => (
                  <tr key={p.platform} className="hover:bg-gray-50">
                    <td className="px-4 py-3 font-medium capitalize">{p.platform}</td>
                    <td className="px-4 py-3 text-right">{p.total.toLocaleString()}</td>
                    <td className="px-4 py-3 text-right text-green-600">{p.success.toLocaleString()}</td>
                    <td className="px-4 py-3 text-right text-red-500">{p.errors.toLocaleString()}</td>
                    <td className="px-4 py-3 text-right">
                      <span className={p.success_rate >= 90 ? 'text-green-600' : p.success_rate >= 70 ? 'text-yellow-600' : 'text-red-500'}>
                        {p.success_rate.toFixed(1)}%
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
              <tfoot className="bg-gray-50">
                <tr>
                  <td className="px-4 py-3 font-bold">Total</td>
                  <td className="px-4 py-3 text-right font-bold">{stats.total_downloads.toLocaleString()}</td>
                  <td className="px-4 py-3 text-right font-bold text-green-600">{stats.success_count.toLocaleString()}</td>
                  <td className="px-4 py-3 text-right font-bold text-red-500">{stats.error_count.toLocaleString()}</td>
                  <td className="px-4 py-3 text-right font-bold">{stats.success_rate.toFixed(1)}%</td>
                </tr>
              </tfoot>
            </table>
          </div>
        </div>
      )}
    </div>
  )
}
