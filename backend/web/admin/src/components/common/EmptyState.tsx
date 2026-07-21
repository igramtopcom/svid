import { Inbox } from 'lucide-react'
import type { ReactNode } from 'react'

interface Props {
  message?: string
  description?: string
  icon?: ReactNode
}

export default function EmptyState({ message = 'No data found', description, icon }: Props) {
  return (
    <div className="flex flex-col items-center justify-center py-12 text-gray-400">
      {icon || <Inbox size={48} strokeWidth={1} />}
      <p className="mt-2 text-sm font-medium">{message}</p>
      {description && <p className="mt-1 text-xs text-gray-300 max-w-sm text-center">{description}</p>}
    </div>
  )
}
