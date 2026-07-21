import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import {
  Smartphone,
  DollarSign,
  Bug,
  LifeBuoy,
  AlertTriangle,
  Star,
  KeyRound,
  Activity,
} from 'lucide-react'
import type { ReactNode } from 'react'
import { getDashboardActivity } from '@/api/devices'
import { useBrandStore } from '@/store/brand'
import { timeAgo, cn } from '@/lib/utils'
import type { ActivityFeedEvent } from '@/types'

// Maps event type → icon, color, label, detail page path (when available)
const EVENT_META: Record<
  string,
  { icon: ReactNode; label: string; color: string; bg: string; path?: (id: string) => string }
> = {
  device_registered: {
    icon: <Smartphone size={14} />,
    label: 'Device',
    color: 'text-blue-600',
    bg: 'bg-blue-50',
    path: (id) => `/devices/${id}`,
  },
  transaction: {
    icon: <DollarSign size={14} />,
    label: 'Payment',
    color: 'text-emerald-600',
    bg: 'bg-emerald-50',
    path: (id) => `/transactions/${id}`,
  },
  bug_report: {
    icon: <Bug size={14} />,
    label: 'Bug',
    color: 'text-amber-600',
    bg: 'bg-amber-50',
    path: (id) => `/bugs/${id}`,
  },
  ticket: {
    icon: <LifeBuoy size={14} />,
    label: 'Ticket',
    color: 'text-purple-600',
    bg: 'bg-purple-50',
    path: (id) => `/tickets/${id}`,
  },
  crash: {
    icon: <AlertTriangle size={14} />,
    label: 'Crash',
    color: 'text-red-600',
    bg: 'bg-red-50',
    path: (id) => `/crashes/${id}`,
  },
  rating: {
    icon: <Star size={14} />,
    label: 'Rating',
    color: 'text-yellow-600',
    bg: 'bg-yellow-50',
    path: () => `/ratings`,
  },
  license: {
    icon: <KeyRound size={14} />,
    label: 'License',
    color: 'text-indigo-600',
    bg: 'bg-indigo-50',
    path: (id) => `/licenses/${id}`,
  },
}

function severityDot(severity: string): string {
  switch (severity) {
    case 'critical':
      return 'bg-red-600'
    case 'high':
      return 'bg-orange-500'
    case 'medium':
      return 'bg-yellow-500'
    case 'success':
      return 'bg-emerald-500'
    case 'info':
      return 'bg-blue-400'
    default:
      return 'bg-gray-400'
  }
}

function Row({ event }: { event: ActivityFeedEvent }) {
  const meta = EVENT_META[event.type] ?? {
    icon: <Activity size={14} />,
    label: event.type,
    color: 'text-gray-600',
    bg: 'bg-gray-50',
  }

  const inner = (
    <div className="flex items-start gap-3 py-3 px-4 hover:bg-gray-50 transition-colors">
      <div className={cn('flex-shrink-0 rounded-md p-1.5 mt-0.5', meta.bg, meta.color)}>
        {meta.icon}
      </div>
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2 mb-0.5">
          <span className={cn('inline-block w-1.5 h-1.5 rounded-full', severityDot(event.severity))} />
          <span className="text-xs font-medium text-gray-500 uppercase tracking-wide">
            {meta.label}
          </span>
          <span className="text-xs text-gray-400">· {timeAgo(event.timestamp)}</span>
        </div>
        <p className="text-sm text-gray-900 truncate" title={event.title}>
          {event.title || event.description}
        </p>
        {event.metadata && (
          <p className="text-xs text-gray-400 truncate mt-0.5">{event.metadata}</p>
        )}
      </div>
    </div>
  )

  if (meta.path && event.related_id) {
    return (
      <Link to={meta.path(event.related_id)} className="block border-b border-gray-100 last:border-0">
        {inner}
      </Link>
    )
  }
  return <div className="border-b border-gray-100 last:border-0">{inner}</div>
}

export default function ActivityFeed() {
  const brand = useBrandStore((s) => s.brand)

  const { data, isLoading } = useQuery({
    queryKey: ['dashboard-activity', brand],
    queryFn: () => getDashboardActivity(25, brand || undefined),
    refetchInterval: 60_000,
  })

  return (
    <div className="bg-white rounded-lg border border-gray-200">
      <div className="flex items-center justify-between p-4 border-b border-gray-200">
        <div className="flex items-center gap-2">
          <Activity size={16} className="text-brand-600" />
          <h3 className="text-sm font-semibold text-gray-700">Recent Activity</h3>
        </div>
        <span className="text-xs text-gray-400">auto-refresh · 60s</span>
      </div>
      <div className="max-h-[480px] overflow-y-auto">
        {isLoading && (
          <div className="p-8 text-center text-sm text-gray-400">Loading…</div>
        )}
        {!isLoading && (!data || data.events.length === 0) && (
          <div className="p-8 text-center text-sm text-gray-400">No recent activity</div>
        )}
        {data?.events.map((ev, i) => (
          <Row key={`${ev.type}-${ev.related_id}-${i}`} event={ev} />
        ))}
      </div>
    </div>
  )
}
