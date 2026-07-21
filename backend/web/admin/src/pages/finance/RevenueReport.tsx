import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { getRevenueReport } from '@/api/premium'
import { useBrandStore } from '@/store/brand'
import StatsCard from '@/components/common/StatsCard'
import { PageSkeleton } from '@/components/common/LoadingSpinner'
import { formatCents } from '@/lib/utils'
import { DollarSign, TrendingUp, TrendingDown, Minus } from 'lucide-react'
import BrandBadge from '@/components/common/BrandBadge'
import PeriodSelector from '@/components/common/PeriodSelector'
import {
  BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer,
  PieChart, Pie, Cell, Legend,
  AreaChart, Area, CartesianGrid,
} from 'recharts'

const COLORS = ['#c8294f', '#3b82f6', '#f59e0b', '#10b981', '#8b5cf6']

function formatShortDate(dateStr: string): string {
  if (!dateStr) return ''
  const d = new Date(dateStr)
  return `${d.getMonth() + 1}/${d.getDate()}`
}

export default function RevenueReport() {
  const [days, setDays] = useState(30)
  const brand = useBrandStore((s) => s.brand)

  const { data: report, isLoading } = useQuery({
    queryKey: ['revenue-report', days, brand],
    queryFn: () => getRevenueReport(days, brand || undefined),
  })

  if (isLoading) return <PageSkeleton cards={6} tableRows={4} />

  if (!report) return null

  const dailyData = (report.daily_revenue || []).map((d) => ({
    date: formatShortDate(d.date),
    revenue: d.amount_cents / 100,
    count: d.count,
  }))

  const methodData = (report.by_method || []).map((m) => ({
    name: m.payment_method.charAt(0).toUpperCase() + m.payment_method.slice(1),
    value: m.amount_cents / 100,
    count: m.count,
  }))

  const cycleData = (report.by_cycle || []).map((c) => ({
    name: c.billing_cycle.charAt(0).toUpperCase() + c.billing_cycle.slice(1),
    amount: c.amount_cents / 100,
    count: c.count,
  }))

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-xl font-bold">Revenue Report<BrandBadge /></h2>
        <PeriodSelector value={days} onChange={setDays} options={[7, 30, 90, 365]} />
      </div>

      {/* Summary Stats */}
      <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-4 mb-6">
        <StatsCard title="Total Revenue" value={formatCents(report.total_revenue_cents)} icon={<DollarSign size={24} />} />
        <StatsCard title="Today" value={formatCents(report.revenue_today_cents)} icon={<TrendingUp size={24} />} />
        <StatsCard title="This Month" value={formatCents(report.revenue_this_month_cents)} icon={<TrendingUp size={24} />} />
        <StatsCard title="Total Refunded" value={formatCents(report.total_refunded_cents)} icon={<TrendingDown size={24} />} />
        <StatsCard title="Refund Count" value={report.refund_count} icon={<Minus size={24} />} />
        <StatsCard title="Net Revenue" value={formatCents(report.net_revenue_cents)} icon={<DollarSign size={24} />} />
      </div>

      {/* Daily Revenue Chart */}
      {dailyData.length > 0 && (
        <div className="bg-white rounded-lg border border-gray-200 p-5 mb-6">
          <h3 className="text-sm font-semibold text-gray-700 mb-4">Daily Revenue (last {days} days)</h3>
          <ResponsiveContainer width="100%" height={300}>
            <AreaChart data={dailyData}>
              <defs>
                <linearGradient id="revenueGradient" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#c8294f" stopOpacity={0.3} />
                  <stop offset="95%" stopColor="#c8294f" stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
              <XAxis dataKey="date" fontSize={12} />
              <YAxis fontSize={12} tickFormatter={(v) => `$${v}`} />
              <Tooltip
                formatter={(value: number) => [`$${value.toFixed(2)}`, 'Revenue']}
                labelFormatter={(label) => `Date: ${label}`}
              />
              <Area type="monotone" dataKey="revenue" stroke="#c8294f" fill="url(#revenueGradient)" strokeWidth={2} />
            </AreaChart>
          </ResponsiveContainer>
        </div>
      )}

      {/* Breakdown Charts */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
        {/* By Payment Method */}
        {methodData.length > 0 && (
          <div className="bg-white rounded-lg border border-gray-200 p-5">
            <h3 className="text-sm font-semibold text-gray-700 mb-4">Revenue by Payment Method</h3>
            <ResponsiveContainer width="100%" height={280}>
              <PieChart>
                <Pie
                  data={methodData}
                  cx="50%"
                  cy="50%"
                  innerRadius={50}
                  outerRadius={90}
                  dataKey="value"
                  label={({ name, value }) => `${name}: $${value.toFixed(0)}`}
                >
                  {methodData.map((_, i) => (
                    <Cell key={i} fill={COLORS[i % COLORS.length]} />
                  ))}
                </Pie>
                <Tooltip formatter={(value: number) => [`$${value.toFixed(2)}`, 'Revenue']} />
                <Legend />
              </PieChart>
            </ResponsiveContainer>
          </div>
        )}

        {/* By Billing Cycle */}
        {cycleData.length > 0 && (
          <div className="bg-white rounded-lg border border-gray-200 p-5">
            <h3 className="text-sm font-semibold text-gray-700 mb-4">Revenue by Billing Cycle</h3>
            <ResponsiveContainer width="100%" height={280}>
              <BarChart data={cycleData}>
                <XAxis dataKey="name" fontSize={12} />
                <YAxis fontSize={12} tickFormatter={(v) => `$${v}`} />
                <Tooltip
                  formatter={(value: number, name: string) => {
                    if (name === 'amount') return [`$${value.toFixed(2)}`, 'Revenue']
                    return [value, 'Transactions']
                  }}
                />
                <Bar dataKey="amount" fill="#c8294f" radius={[4, 4, 0, 0]} name="amount" />
              </BarChart>
            </ResponsiveContainer>
          </div>
        )}
      </div>

      {/* Revenue Table */}
      {cycleData.length > 0 && (
        <div className="bg-white rounded-lg border border-gray-200">
          <div className="p-4 border-b border-gray-200">
            <h3 className="text-sm font-semibold text-gray-700">Revenue Breakdown</h3>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-gray-50 text-gray-500 uppercase text-xs">
                <tr>
                  <th className="px-4 py-3 text-left">Billing Cycle</th>
                  <th className="px-4 py-3 text-right">Transactions</th>
                  <th className="px-4 py-3 text-right">Revenue</th>
                  <th className="px-4 py-3 text-right">% of Total</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-200">
                {cycleData.map((row) => {
                  const totalRev = cycleData.reduce((s, r) => s + r.amount, 0)
                  const pct = totalRev > 0 ? ((row.amount / totalRev) * 100).toFixed(1) : '0'
                  return (
                    <tr key={row.name} className="hover:bg-gray-50">
                      <td className="px-4 py-3 font-medium capitalize">{row.name}</td>
                      <td className="px-4 py-3 text-right">{row.count}</td>
                      <td className="px-4 py-3 text-right font-medium">${row.amount.toFixed(2)}</td>
                      <td className="px-4 py-3 text-right text-gray-500">{pct}%</td>
                    </tr>
                  )
                })}
              </tbody>
              <tfoot className="bg-gray-50">
                <tr>
                  <td className="px-4 py-3 font-bold">Total</td>
                  <td className="px-4 py-3 text-right font-bold">{cycleData.reduce((s, r) => s + r.count, 0)}</td>
                  <td className="px-4 py-3 text-right font-bold">${cycleData.reduce((s, r) => s + r.amount, 0).toFixed(2)}</td>
                  <td className="px-4 py-3 text-right font-bold">100%</td>
                </tr>
              </tfoot>
            </table>
          </div>
        </div>
      )}
    </div>
  )
}
