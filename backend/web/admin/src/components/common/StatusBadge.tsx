import { cn } from '@/lib/utils'

const colorMap: Record<string, string> = {
  // Bug status
  open: 'bg-red-100 text-red-700',
  in_progress: 'bg-yellow-100 text-yellow-700',
  resolved: 'bg-green-100 text-green-700',
  closed: 'bg-gray-100 text-gray-700',
  wont_fix: 'bg-gray-100 text-gray-600',

  // Ticket status
  waiting_for_customer: 'bg-orange-100 text-orange-700',

  // Severity
  critical: 'bg-red-100 text-red-700',
  high: 'bg-orange-100 text-orange-700',
  medium: 'bg-yellow-100 text-yellow-700',
  low: 'bg-blue-100 text-blue-700',

  // Boolean
  active: 'bg-green-100 text-green-700',
  inactive: 'bg-gray-100 text-gray-600',
  enabled: 'bg-green-100 text-green-700',
  disabled: 'bg-gray-100 text-gray-600',

  // Chat
  escalated: 'bg-red-100 text-red-700',

  // Feature request
  planned: 'bg-blue-100 text-blue-700',
  under_review: 'bg-purple-100 text-purple-700',
  implemented: 'bg-green-100 text-green-700',
  declined: 'bg-gray-100 text-gray-600',

  // Announcement type
  info: 'bg-blue-100 text-blue-700',
  warning: 'bg-yellow-100 text-yellow-700',
  maintenance: 'bg-orange-100 text-orange-700',

  // Release
  stable: 'bg-green-100 text-green-700',
  beta: 'bg-yellow-100 text-yellow-700',
  alpha: 'bg-orange-100 text-orange-700',

  // Payment / Transaction
  pending: 'bg-yellow-100 text-yellow-700',
  completed: 'bg-green-100 text-green-700',
  failed: 'bg-red-100 text-red-700',
  cancelled: 'bg-gray-100 text-gray-600',
  refunded: 'bg-purple-100 text-purple-700',
  refund_pending: 'bg-orange-100 text-orange-700',
  paid: 'bg-green-100 text-green-700',
  void: 'bg-gray-100 text-gray-600',
  uncollectible: 'bg-red-100 text-red-700',
  past_due: 'bg-orange-100 text-orange-700',

  // Subscription
  expired: 'bg-red-100 text-red-700',
}

interface Props {
  status: string
  className?: string
}

export default function StatusBadge({ status, className }: Props) {
  if (!status) return null
  const color = colorMap[status] || 'bg-gray-100 text-gray-700'
  return (
    <span
      className={cn(
        'inline-flex items-center px-2 py-0.5 rounded text-xs font-medium',
        color,
        className
      )}
    >
      {status.replace(/_/g, ' ')}
    </span>
  )
}
