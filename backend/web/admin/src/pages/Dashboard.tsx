import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Monitor, Bug, MessageSquare, Zap, Star, AlertTriangle, DollarSign, Shield, CreditCard, Download } from 'lucide-react'
import { getComprehensiveStats, getBrandComparison, getDashboardTrends } from '@/api/devices'
import { useBrandStore } from '@/store/brand'
import StatsCard from '@/components/common/StatsCard'
import BrandBadge from '@/components/common/BrandBadge'
import BrandCard from '@/components/common/BrandCard'
import PeriodSelector from '@/components/common/PeriodSelector'
import ActivityFeed from '@/components/common/ActivityFeed'
import TopCustomers from '@/components/common/TopCustomers'
import { PageSkeleton } from '@/components/common/LoadingSpinner'
import { formatCents } from '@/lib/utils'
import {
  PieChart, Pie, Cell, ResponsiveContainer, BarChart, Bar, XAxis, YAxis, Tooltip,
  AreaChart, Area, CartesianGrid,
} from 'recharts'

const COLORS = ['#c8294f', '#3b82f6', '#f59e0b', '#ef4444', '#8b5cf6', '#22c55e']

function formatShortDate(dateStr: string): string {
  if (!dateStr) return ''
  // API returns full ISO datetime ("2026-03-31T00:00:00Z"), not bare date.
  // Appending "T00:00:00" produced "...ZT00:00:00" → NaN on chart axes.
  const d = new Date(dateStr)
  if (isNaN(d.getTime())) return ''
  return `${d.getMonth() + 1}/${d.getDate()}`
}

export default function Dashboard() {
  const brand = useBrandStore((s) => s.brand)
  const setBrand = useBrandStore((s) => s.setBrand)
  const [trendDays, setTrendDays] = useState(7)

  const { data: s, isLoading } = useQuery({
    queryKey: ['comprehensive-stats', brand],
    queryFn: () => getComprehensiveStats(brand || undefined),
    refetchInterval: 60000,
  })

  const { data: comparison } = useQuery({
    queryKey: ['brand-comparison'],
    queryFn: getBrandComparison,
    enabled: !brand, // only fetch when "All Brands" is selected
    refetchInterval: 60000,
  })

  const { data: trends } = useQuery({
    queryKey: ['dashboard-trends', trendDays, brand],
    queryFn: () => getDashboardTrends(trendDays, brand || undefined),
    refetchInterval: 60000,
  })

  if (isLoading || !s) {
    return <PageSkeleton cards={4} tableRows={6} />
  }

  const osPieData = s.by_os
    ? Object.entries(s.by_os).map(([name, value]) => ({ name, value }))
    : []

  const versionBarData = s.by_version
    ? Object.entries(s.by_version)
        .map(([name, value]) => ({ name, value }))
        .sort((a, b) => b.value - a.value)
        .slice(0, 8)
    : []

  // Sparkline data
  const dailyDeviceData = (trends?.daily_devices || []).map((d) => ({
    date: formatShortDate(d.date),
    value: d.value,
  }))
  const dailyRevenueData = (trends?.daily_revenue || []).map((d) => ({
    date: formatShortDate(d.date),
    value: d.value / 100,
  }))

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-xl font-bold">Dashboard<BrandBadge /></h2>
        <PeriodSelector value={trendDays} onChange={setTrendDays} />
      </div>

      {/* Brand Comparison — shown only when "All Brands" is selected */}
      {!brand && comparison && comparison.brands.length > 0 && (
        <div className="mb-8">
          <h3 className="text-sm font-semibold text-gray-500 uppercase tracking-wider mb-3">Brand Overview</h3>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {comparison.brands.map((b) => (
              <BrandCard key={b.brand} brand={b} onClick={() => setBrand(b.brand)} />
            ))}
          </div>
        </div>
      )}

      {/* Row 1: Core Metrics with trend comparison */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <StatsCard
          title="Total Devices"
          value={s.total_devices}
          icon={<Monitor size={24} />}
          trend={`${s.new_today} new today`}
          changePct={trends?.new_devices.change_pct}
          to="/devices"
        />
        <StatsCard
          title="Active Today"
          value={s.active_today}
          icon={<Zap size={24} />}
          trend={`${s.active_7d} in 7 days`}
          changePct={trends?.active_devices.change_pct}
          to="/devices"
        />
        <StatsCard
          title="Open Bugs"
          value={s.open_bugs}
          icon={<Bug size={24} />}
          trend={`${s.new_bugs_today} new today`}
          changePct={trends?.new_bugs.change_pct}
          lowerIsBetter
          to="/bugs"
        />
        <StatsCard
          title="Open Tickets"
          value={s.open_tickets}
          icon={<MessageSquare size={24} />}
          trend={`${s.new_tickets_today} new today`}
          changePct={trends?.new_tickets.change_pct}
          lowerIsBetter
          to="/tickets"
        />
      </div>

      {/* Row 2: Crash Groups + Download Errors + Revenue */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <StatsCard
          title="Crash Groups (Active)"
          value={s.crash_groups_active}
          icon={<AlertTriangle size={24} />}
          trend={`${s.crash_groups_critical} critical · ${s.crashes_today} crashes today`}
          changePct={trends?.new_crashes.change_pct}
          lowerIsBetter
          to="/crash-groups"
        />
        <StatsCard
          title="Download Errors Today"
          value={s.download_errors_today}
          icon={<Download size={24} />}
          trend={`${s.download_errors_total} total · ${s.download_success_rate}% success rate`}
          changePct={trends?.download_errors.change_pct}
          lowerIsBetter
          to="/download-errors"
        />
        <StatsCard
          title="Revenue Today"
          value={formatCents(s.revenue_today_cents)}
          icon={<DollarSign size={24} />}
          trend={`${formatCents(s.revenue_month_cents)} this month`}
          changePct={trends?.revenue_cents.change_pct}
          to="/finance/revenue"
        />
        <StatsCard
          title="Premium Licenses"
          value={s.premium_licenses}
          icon={<CreditCard size={24} />}
          trend={`${s.active_licenses} active`}
          to="/licenses"
        />
      </div>

      {/* Row 3: Ratings + Downloads */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <StatsCard
          title="Avg Rating"
          value={s.rating_average ? s.rating_average.toFixed(1) : '-'}
          icon={<Star size={24} />}
          trend={`${s.total_ratings} total ratings`}
          to="/ratings"
        />
        <StatsCard
          title="Downloads Today"
          value={s.downloads_today}
          icon={<Download size={24} />}
          trend={`${s.download_success_rate}% success rate`}
          changePct={trends?.downloads.change_pct}
          to="/downloads"
        />
        <StatsCard
          title="Crash Groups Total"
          value={s.crash_groups_total}
          icon={<Shield size={24} />}
          trend={`${s.crash_groups_active} active`}
          to="/crash-groups"
        />
        <StatsCard
          title="Download Errors Total"
          value={s.download_errors_total}
          icon={<AlertTriangle size={24} />}
          to="/download-errors"
        />
      </div>

      {/* Trend Sparklines */}
      {(dailyDeviceData.length > 0 || dailyRevenueData.length > 0) && (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-8">
          {dailyDeviceData.length > 0 && (
            <div className="bg-white rounded-lg border border-gray-200 p-5">
              <div className="flex items-center justify-between mb-4">
                <h3 className="text-sm font-semibold text-gray-700">New Devices (last {trendDays}D)</h3>
                {trends && (
                  <span className="text-xs text-gray-400">
                    {trends.new_devices.current} total ({trends.new_devices.previous} prev)
                  </span>
                )}
              </div>
              <ResponsiveContainer width="100%" height={180}>
                <AreaChart data={dailyDeviceData}>
                  <defs>
                    <linearGradient id="devicesGrad" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="5%" stopColor="var(--brand-500)" stopOpacity={0.3} />
                      <stop offset="95%" stopColor="var(--brand-500)" stopOpacity={0} />
                    </linearGradient>
                  </defs>
                  <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
                  <XAxis dataKey="date" fontSize={11} tickLine={false} />
                  <YAxis fontSize={11} tickLine={false} allowDecimals={false} />
                  <Tooltip />
                  <Area type="monotone" dataKey="value" stroke="var(--brand-500)" fill="url(#devicesGrad)" strokeWidth={2} name="New Devices" />
                </AreaChart>
              </ResponsiveContainer>
            </div>
          )}

          {dailyRevenueData.length > 0 && (
            <div className="bg-white rounded-lg border border-gray-200 p-5">
              <div className="flex items-center justify-between mb-4">
                <h3 className="text-sm font-semibold text-gray-700">Revenue (last {trendDays}D)</h3>
                {trends && (
                  <span className="text-xs text-gray-400">
                    {formatCents(trends.revenue_cents.current)} total ({formatCents(trends.revenue_cents.previous)} prev)
                  </span>
                )}
              </div>
              <ResponsiveContainer width="100%" height={180}>
                <AreaChart data={dailyRevenueData}>
                  <defs>
                    <linearGradient id="revenueGrad" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="5%" stopColor="#10b981" stopOpacity={0.3} />
                      <stop offset="95%" stopColor="#10b981" stopOpacity={0} />
                    </linearGradient>
                  </defs>
                  <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
                  <XAxis dataKey="date" fontSize={11} tickLine={false} />
                  <YAxis fontSize={11} tickLine={false} tickFormatter={(v) => `$${v}`} />
                  <Tooltip formatter={(value: number) => [`$${value.toFixed(2)}`, 'Revenue']} />
                  <Area type="monotone" dataKey="value" stroke="#10b981" fill="url(#revenueGrad)" strokeWidth={2} name="Revenue" />
                </AreaChart>
              </ResponsiveContainer>
            </div>
          )}
        </div>
      )}

      {/* Live Activity + Top Customers */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 mb-8">
        <div className="lg:col-span-2">
          <ActivityFeed />
        </div>
        <div>
          <TopCustomers />
        </div>
      </div>

      {/* Charts + Breakdowns */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* OS Distribution */}
        {osPieData.length > 0 && (
          <div className="bg-white rounded-lg border border-gray-200 p-5">
            <h3 className="text-sm font-semibold text-gray-700 mb-4">Devices by OS</h3>
            <ResponsiveContainer width="100%" height={250}>
              <PieChart>
                <Pie
                  data={osPieData}
                  cx="50%"
                  cy="50%"
                  innerRadius={60}
                  outerRadius={100}
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

        {/* Version Distribution */}
        {versionBarData.length > 0 && (
          <div className="bg-white rounded-lg border border-gray-200 p-5">
            <h3 className="text-sm font-semibold text-gray-700 mb-4">Top App Versions</h3>
            <ResponsiveContainer width="100%" height={250}>
              <BarChart data={versionBarData}>
                <XAxis dataKey="name" fontSize={12} />
                <YAxis fontSize={12} />
                <Tooltip />
                <Bar dataKey="value" fill="#c8294f" radius={[4, 4, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </div>
        )}

        {/* Brand Distribution */}
        {s.by_brand && Object.keys(s.by_brand).length > 0 && (
          <div className="bg-white rounded-lg border border-gray-200 p-5">
            <h3 className="text-sm font-semibold text-gray-700 mb-4">Devices by Brand</h3>
            <div className="space-y-3">
              {Object.entries(s.by_brand).map(([brand, count]) => (
                <div key={brand} className="flex items-center justify-between">
                  <span className="text-sm text-gray-600 capitalize">{brand || 'unknown'}</span>
                  <div className="flex items-center gap-2">
                    <div className="w-32 bg-gray-100 rounded-full h-2">
                      <div
                        className="bg-brand-500 h-2 rounded-full"
                        style={{
                          width: `${s.total_devices > 0 ? (count / s.total_devices) * 100 : 0}%`,
                        }}
                      />
                    </div>
                    <span className="text-sm font-medium w-8 text-right">{count}</span>
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Tier Distribution */}
        {s.by_tier && Object.keys(s.by_tier).length > 0 && (
          <div className="bg-white rounded-lg border border-gray-200 p-5">
            <h3 className="text-sm font-semibold text-gray-700 mb-4">Devices by Tier</h3>
            <div className="space-y-3">
              {Object.entries(s.by_tier).map(([tier, count]) => (
                <div key={tier} className="flex items-center justify-between">
                  <span className="text-sm text-gray-600 capitalize">{tier}</span>
                  <div className="flex items-center gap-2">
                    <div className="w-32 bg-gray-100 rounded-full h-2">
                      <div
                        className="bg-brand-500 h-2 rounded-full"
                        style={{
                          width: `${s.total_devices > 0 ? (count / s.total_devices) * 100 : 0}%`,
                        }}
                      />
                    </div>
                    <span className="text-sm font-medium w-8 text-right">{count}</span>
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Bug Status */}
        {s.bugs_by_status && Object.keys(s.bugs_by_status).length > 0 && (
          <div className="bg-white rounded-lg border border-gray-200 p-5">
            <h3 className="text-sm font-semibold text-gray-700 mb-4">Bug Status</h3>
            <div className="space-y-3">
              {Object.entries(s.bugs_by_status).map(([status, count]) => (
                <div key={status} className="flex items-center justify-between">
                  <span className="text-sm text-gray-600 capitalize">{status.replace(/_/g, ' ')}</span>
                  <span className="text-sm font-medium">{count}</span>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Crash Groups by Status */}
        {s.crash_groups_by_status && Object.keys(s.crash_groups_by_status).length > 0 && (
          <div className="bg-white rounded-lg border border-gray-200 p-5">
            <h3 className="text-sm font-semibold text-gray-700 mb-4">Crash Groups by Status</h3>
            <div className="space-y-3">
              {Object.entries(s.crash_groups_by_status).map(([status, count]) => (
                <div key={status} className="flex items-center justify-between">
                  <span className="text-sm text-gray-600 capitalize">{status.replace(/_/g, ' ')}</span>
                  <span className="text-sm font-medium">{count}</span>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Top Error Codes */}
        {s.top_error_codes && Object.keys(s.top_error_codes).length > 0 && (
          <div className="bg-white rounded-lg border border-gray-200 p-5">
            <h3 className="text-sm font-semibold text-gray-700 mb-4">Top Download Error Codes</h3>
            <div className="space-y-3">
              {Object.entries(s.top_error_codes)
                .sort(([, a], [, b]) => b - a)
                .map(([code, count]) => (
                  <div key={code} className="flex items-center justify-between">
                    <span className="text-sm text-gray-600 font-mono">{code}</span>
                    <span className="text-sm font-medium">{count}</span>
                  </div>
                ))}
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
