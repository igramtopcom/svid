import { useState } from 'react'
import { useParams, Link } from 'react-router-dom'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { getTicket, updateTicket, adminReplyTicket } from '@/api/feedback'
import StatusBadge from '@/components/common/StatusBadge'
import LoadingSpinner from '@/components/common/LoadingSpinner'
import { formatDate } from '@/lib/utils'
import { ArrowLeft, Send } from 'lucide-react'

export default function TicketDetail() {
  const { id } = useParams<{ id: string }>()
  const queryClient = useQueryClient()
  const [reply, setReply] = useState('')

  const { data: ticket, isLoading } = useQuery({
    queryKey: ['ticket', id],
    queryFn: () => getTicket(id!),
    refetchInterval: 3000,
  })

  const statusMut = useMutation({
    mutationFn: (status: string) => updateTicket(id!, { status }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['ticket', id] })
      toast.success('Status updated')
    },
  })

  const replyMut = useMutation({
    mutationFn: (msg: string) => adminReplyTicket(id!, msg),
    onSuccess: () => {
      setReply('')
      queryClient.invalidateQueries({ queryKey: ['ticket', id] })
      toast.success('Reply sent')
    },
  })

  if (isLoading) return <LoadingSpinner />
  if (!ticket) return <p className="text-gray-500">Ticket not found</p>

  return (
    <div>
      <Link to="/tickets" className="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700 mb-4">
        <ArrowLeft size={16} /> Back to Tickets
      </Link>

      <div className="bg-white rounded-lg border border-gray-200 p-6 mb-4">
        <div className="flex items-start justify-between mb-4">
          <div>
            <h2 className="text-xl font-bold">{ticket.subject}</h2>
            <p className="text-sm text-gray-500 mt-1">
              Device: {ticket.device_id} &middot; Category: {ticket.category} &middot; Priority: {ticket.priority}
            </p>
            {ticket.ai_session_id && (
              <p className="text-xs text-brand-600 mt-1">
                Escalated from AI Session: <Link to={`/assistant/sessions/${ticket.ai_session_id}`} className="underline">{ticket.ai_session_id.slice(0, 8)}...</Link>
              </p>
            )}
          </div>
          <div className="flex items-center gap-2">
            <select
              value={ticket.status}
              onChange={(e) => statusMut.mutate(e.target.value)}
              className="px-3 py-1.5 border border-gray-300 rounded-md text-sm"
            >
              <option value="open">Open</option>
              <option value="in_progress">In Progress</option>
              <option value="waiting_for_customer">Waiting for Customer</option>
              <option value="resolved">Resolved</option>
              <option value="closed">Closed</option>
            </select>
            <StatusBadge status={ticket.status} />
          </div>
        </div>

        {/* Messages */}
        <div className="space-y-3 mt-6">
          {ticket.messages?.map((msg) => (
            <div
              key={msg.id}
              className={`p-3 rounded-lg text-sm ${
                msg.sender_type === 'admin'
                  ? 'bg-brand-50 border border-brand-200 ml-8'
                  : 'bg-gray-50 border border-gray-200 mr-8'
              }`}
            >
              <div className="flex items-center justify-between mb-1">
                <span className="text-xs font-medium text-gray-500 uppercase">
                  {msg.sender_type}
                </span>
                <span className="text-xs text-gray-400">{formatDate(msg.created_at)}</span>
              </div>
              <p className="whitespace-pre-wrap">{msg.content}</p>
            </div>
          ))}
        </div>
      </div>

      {/* Reply Box */}
      <div className="bg-white rounded-lg border border-gray-200 p-4">
        <div className="flex gap-3">
          <textarea
            value={reply}
            onChange={(e) => setReply(e.target.value)}
            placeholder="Type your reply..."
            rows={3}
            className="flex-1 px-3 py-2 border border-gray-300 rounded-md text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
          />
          <button
            onClick={() => reply.trim() && replyMut.mutate(reply)}
            disabled={!reply.trim() || replyMut.isPending}
            className="self-end px-4 py-2 bg-brand-600 text-white rounded-md text-sm hover:bg-brand-700 disabled:opacity-50 flex items-center gap-2"
          >
            <Send size={16} />
            Reply
          </button>
        </div>
      </div>
    </div>
  )
}
