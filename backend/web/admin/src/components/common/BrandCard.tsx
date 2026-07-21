import { Monitor, Zap, DollarSign, CreditCard, Bug, MessageSquare, AlertTriangle, Star } from 'lucide-react'
import type { BrandSummary } from '@/types'

const BRAND_COLORS: Record<string, { bg: string; accent: string; text: string }> = {
  svid: { bg: '#fdf2f4', accent: '#c8294f', text: '#8d1c3a' },
  vidcombo: { bg: '#eff6ff', accent: '#2563eb', text: '#1e40af' },
}

interface Props {
  brand: BrandSummary
  onClick: () => void
}

function formatCents(cents: number): string {
  return '$' + (cents / 100).toFixed(2)
}

export default function BrandCard({ brand, onClick }: Props) {
  const colors = BRAND_COLORS[brand.brand] || { bg: '#f8fafc', accent: '#64748b', text: '#334155' }
  const label = brand.brand === 'vidcombo' ? 'VidCombo' : brand.brand.toUpperCase()

  return (
    <button
      onClick={onClick}
      className="text-left bg-white rounded-xl border-2 border-gray-200 overflow-hidden hover:shadow-lg hover:-translate-y-0.5 transition-all duration-200 cursor-pointer"
    >
      {/* Brand header bar */}
      <div className="px-5 py-3 flex items-center gap-3" style={{ backgroundColor: colors.bg }}>
        <span className="w-3 h-3 rounded-full" style={{ backgroundColor: colors.accent }} />
        <span className="font-bold text-lg" style={{ color: colors.text }}>{label}</span>
        <span className="ml-auto text-xs font-medium px-2 py-0.5 rounded-full" style={{ backgroundColor: colors.accent, color: 'white' }}>
          {brand.total_devices} devices
        </span>
      </div>

      {/* KPI grid */}
      <div className="grid grid-cols-2 gap-x-4 gap-y-3 px-5 py-4">
        <KPI icon={<Zap size={14} />} label="Active Today" value={brand.active_today} color={colors.accent} />
        <KPI icon={<Monitor size={14} />} label="New Today" value={brand.new_today} color={colors.accent} />
        <KPI icon={<DollarSign size={14} />} label="Revenue (Month)" value={formatCents(brand.revenue_month_cents)} color={colors.accent} />
        <KPI icon={<CreditCard size={14} />} label="Premium" value={brand.premium_licenses} color={colors.accent} />
        <KPI icon={<Bug size={14} />} label="Open Bugs" value={brand.open_bugs} color={brand.open_bugs > 0 ? '#ef4444' : colors.accent} />
        <KPI icon={<MessageSquare size={14} />} label="Open Tickets" value={brand.open_tickets} color={brand.open_tickets > 0 ? '#f59e0b' : colors.accent} />
        <KPI icon={<AlertTriangle size={14} />} label="Crash Groups" value={brand.crash_groups_active} color={brand.crash_groups_active > 0 ? '#ef4444' : colors.accent} />
        <KPI icon={<Star size={14} />} label="Rating" value={brand.rating_average ? brand.rating_average.toFixed(1) : '-'} color={colors.accent} />
      </div>
    </button>
  )
}

function KPI({ icon, label, value, color }: { icon: React.ReactNode; label: string; value: string | number; color: string }) {
  return (
    <div className="flex items-center gap-2">
      <span style={{ color }} className="shrink-0">{icon}</span>
      <div className="min-w-0">
        <p className="text-xs text-gray-400 truncate">{label}</p>
        <p className="text-sm font-semibold text-gray-800">{value}</p>
      </div>
    </div>
  )
}
