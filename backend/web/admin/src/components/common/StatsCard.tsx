import type { ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { TrendingUp, TrendingDown, Minus } from 'lucide-react'
import { cn } from '@/lib/utils'

interface Props {
  title: string
  value: string | number
  icon?: ReactNode
  trend?: string
  changePct?: number | null  // period-over-period % change
  // For metrics where rising values are bad (errors, crashes, open bugs/tickets),
  // pass lowerIsBetter to flip ONLY the color — the up/down arrow still reflects
  // the actual direction. Up + red = "went up, that's bad."
  lowerIsBetter?: boolean
  className?: string
  to?: string
}

function ChangeIndicator({ pct, lowerIsBetter }: { pct: number; lowerIsBetter?: boolean }) {
  if (pct === 0) {
    return (
      <span className="inline-flex items-center gap-0.5 text-xs text-gray-400">
        <Minus size={12} /> 0%
      </span>
    )
  }
  const isUp = pct > 0
  const isGood = lowerIsBetter ? !isUp : isUp
  return (
    <span className={cn('inline-flex items-center gap-0.5 text-xs font-medium', isGood ? 'text-emerald-600' : 'text-red-500')}>
      {isUp ? <TrendingUp size={12} /> : <TrendingDown size={12} />}
      {isUp ? '+' : ''}{pct.toFixed(1)}%
    </span>
  )
}

export default function StatsCard({ title, value, icon, trend, changePct, lowerIsBetter, className, to }: Props) {
  const content = (
    <div className="flex items-center justify-between">
      <div>
        <p className="text-sm text-gray-500">{title}</p>
        <div className="flex items-baseline gap-2 mt-1">
          <p className="text-2xl font-bold">{value}</p>
          {changePct != null && <ChangeIndicator pct={changePct} lowerIsBetter={lowerIsBetter} />}
        </div>
        {trend && <p className="text-xs text-gray-400 mt-1">{trend}</p>}
      </div>
      {icon && <div className="text-gray-400">{icon}</div>}
    </div>
  )

  const baseClass = cn('bg-white rounded-lg border border-gray-200 border-l-4 border-l-brand-500 p-5', className)

  if (to) {
    return (
      <Link to={to} className={cn(baseClass, 'block hover:border-brand-300 hover:shadow-sm transition-all')}>
        {content}
      </Link>
    )
  }

  return <div className={baseClass}>{content}</div>
}
