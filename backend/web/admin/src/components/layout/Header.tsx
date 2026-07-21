import { useState, useEffect, useRef, useCallback } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuthStore } from '@/store/auth'
import { useBrandStore } from '@/store/brand'
import { globalSearch } from '@/api/premium'
import { User, Search, KeyRound, CreditCard, Users, Bell, Menu } from 'lucide-react'
import type { GlobalSearchResult } from '@/types'

interface SSENotification {
  type: string
  data: Record<string, unknown>
  timestamp: string
}

interface HeaderProps {
  onMenuClick?: () => void
  showMenu?: boolean
}

export default function Header({ onMenuClick, showMenu }: HeaderProps) {
  const admin = useAuthStore((s) => s.admin)
  const token = useAuthStore((s) => s.token)
  const brand = useBrandStore((s) => s.brand)
  const setBrand = useBrandStore((s) => s.setBrand)
  const navigate = useNavigate()
  const [query, setQuery] = useState('')
  const [results, setResults] = useState<GlobalSearchResult | null>(null)
  const [showResults, setShowResults] = useState(false)
  const [loading, setLoading] = useState(false)
  const timerRef = useRef<ReturnType<typeof setTimeout>>()
  const containerRef = useRef<HTMLDivElement>(null)
  const searchInputRef = useRef<HTMLInputElement>(null)
  const [notifications, setNotifications] = useState<SSENotification[]>([])
  const [showNotifs, setShowNotifs] = useState(false)
  const [unreadCount, setUnreadCount] = useState(0)
  const notifRef = useRef<HTMLDivElement>(null)
  const eventSourceRef = useRef<EventSource | null>(null)

  useEffect(() => {
    if (!query.trim()) {
      setResults(null)
      setShowResults(false)
      return
    }

    setLoading(true)
    clearTimeout(timerRef.current)
    timerRef.current = setTimeout(async () => {
      try {
        const data = await globalSearch(query)
        setResults(data)
        setShowResults(true)
      } catch {
        setResults(null)
      } finally {
        setLoading(false)
      }
    }, 300)

    return () => clearTimeout(timerRef.current)
  }, [query])

  // Close on click outside
  useEffect(() => {
    function handleClick(e: MouseEvent) {
      if (containerRef.current && !containerRef.current.contains(e.target as Node)) {
        setShowResults(false)
      }
      if (notifRef.current && !notifRef.current.contains(e.target as Node)) {
        setShowNotifs(false)
      }
    }
    document.addEventListener('mousedown', handleClick)
    return () => document.removeEventListener('mousedown', handleClick)
  }, [])

  // Cmd+K shortcut to focus search
  useEffect(() => {
    function handleKeyDown(e: KeyboardEvent) {
      if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
        e.preventDefault()
        searchInputRef.current?.focus()
      }
    }
    document.addEventListener('keydown', handleKeyDown)
    return () => document.removeEventListener('keydown', handleKeyDown)
  }, [])

  // SSE connection for real-time notifications with exponential backoff
  useEffect(() => {
    if (!token) return

    let retryDelay = 1000
    let retryTimer: ReturnType<typeof setTimeout>
    let closed = false

    function connect() {
      if (closed || !token) return
      const url = `/admin/v1/notifications/stream?token=${encodeURIComponent(token)}`
      const es = new EventSource(url)
      eventSourceRef.current = es

      es.onopen = () => {
        retryDelay = 1000 // reset backoff on successful connect
      }

      es.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data)
          const notif: SSENotification = {
            type: data.type || 'notification',
            data: data.data || data,
            timestamp: new Date().toISOString(),
          }
          setNotifications((prev) => [notif, ...prev].slice(0, 50))
          setUnreadCount((prev) => prev + 1)
        } catch {
          // ignore parse errors
        }
      }

      es.onerror = () => {
        es.close()
        eventSourceRef.current = null
        if (!closed) {
          retryTimer = setTimeout(connect, retryDelay)
          retryDelay = Math.min(retryDelay * 2, 30000) // max 30s backoff
        }
      }
    }

    connect()

    return () => {
      closed = true
      clearTimeout(retryTimer)
      eventSourceRef.current?.close()
      eventSourceRef.current = null
    }
  }, [token])

  const clearNotifications = useCallback(() => {
    setUnreadCount(0)
  }, [])

  const getNotifLabel = (type: string) => {
    switch (type) {
      case 'new_ticket': return 'New Ticket'
      case 'ticket_message': return 'Ticket Reply'
      case 'ticket_escalated': return 'Ticket Escalated'
      case 'new_rating': return 'New Rating'
      default: return type.replace(/_/g, ' ')
    }
  }

  const getNotifRoute = (notif: SSENotification): string | null => {
    const d = notif.data
    if (d.ticket_id) return `/tickets/${d.ticket_id}`
    if (d.id && notif.type.includes('ticket')) return `/tickets/${d.id}`
    return null
  }

  const handleNavigate = (path: string) => {
    navigate(path)
    setQuery('')
    setShowResults(false)
  }

  const totalResults = results
    ? (results.licenses?.length || 0) + (results.transactions?.length || 0) + (results.customers?.length || 0)
    : 0

  return (
    <header className="h-14 bg-white border-b border-gray-200 flex items-center justify-between px-4 md:px-6 sticky top-0 z-10">
      <div className="flex items-center gap-3">
        {/* Mobile menu button */}
        {showMenu && (
          <button onClick={onMenuClick} className="md:hidden p-1.5 rounded-lg hover:bg-gray-100 text-gray-500">
            <Menu size={20} />
          </button>
        )}

        {/* Search */}
        <div className="relative" ref={containerRef}>
          <div className="flex items-center gap-2 bg-gray-100 rounded-lg px-3 py-1.5">
            <Search size={16} className="text-gray-400" />
            <input
              ref={searchInputRef}
              type="text"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              onFocus={() => results && setShowResults(true)}
              placeholder="Search... (Cmd+K)"
              className="bg-transparent text-sm w-48 md:w-80 outline-none placeholder-gray-400"
            />
            {loading && <div className="animate-spin h-3.5 w-3.5 border-2 border-gray-300 border-t-gray-600 rounded-full" />}
          </div>

        {/* Results dropdown */}
        {showResults && results && totalResults > 0 && (
          <div className="absolute top-full left-0 mt-1 w-[500px] bg-white rounded-lg shadow-lg border border-gray-200 max-h-96 overflow-y-auto z-50">
            {/* Licenses */}
            {results.licenses?.length > 0 && (
              <div>
                <div className="px-3 py-2 bg-gray-50 text-xs font-semibold text-gray-500 uppercase flex items-center gap-1.5">
                  <KeyRound size={12} /> Licenses ({results.licenses.length})
                </div>
                {results.licenses.map((lic) => (
                  <button key={lic.id} onClick={() => handleNavigate(`/licenses/${lic.id}`)}
                    className="w-full px-3 py-2 text-left hover:bg-gray-50 flex items-center justify-between text-sm">
                    <span className="font-mono text-xs text-indigo-600">{lic.license_key.slice(0, 25)}...</span>
                    <span className="text-xs text-gray-500 capitalize">{lic.billing_cycle} · {lic.tier}</span>
                  </button>
                ))}
              </div>
            )}

            {/* Transactions */}
            {results.transactions?.length > 0 && (
              <div>
                <div className="px-3 py-2 bg-gray-50 text-xs font-semibold text-gray-500 uppercase flex items-center gap-1.5">
                  <CreditCard size={12} /> Transactions ({results.transactions.length})
                </div>
                {results.transactions.map((txn) => (
                  <button key={txn.id} onClick={() => handleNavigate(`/transactions/${txn.id}`)}
                    className="w-full px-3 py-2 text-left hover:bg-gray-50 flex items-center justify-between text-sm">
                    <span className="font-mono text-xs">{txn.id.slice(0, 12)}...</span>
                    <span className="text-xs text-gray-500">${(txn.amount_cents / 100).toFixed(2)} · {txn.status}</span>
                  </button>
                ))}
              </div>
            )}

            {/* Customers */}
            {results.customers?.length > 0 && (
              <div>
                <div className="px-3 py-2 bg-gray-50 text-xs font-semibold text-gray-500 uppercase flex items-center gap-1.5">
                  <Users size={12} /> Customers ({results.customers.length})
                </div>
                {results.customers.map((cust) => (
                  <button key={cust.contact_email} onClick={() => handleNavigate(`/customers/${encodeURIComponent(cust.contact_email)}`)}
                    className="w-full px-3 py-2 text-left hover:bg-gray-50 flex items-center justify-between text-sm">
                    <span>{cust.contact_email}</span>
                    <span className="text-xs text-gray-500">{cust.license_count} license(s) · ${(cust.total_spent_cents / 100).toFixed(2)}</span>
                  </button>
                ))}
              </div>
            )}
          </div>
        )}

        {showResults && results && totalResults === 0 && query.trim() && (
          <div className="absolute top-full left-0 mt-1 w-[500px] bg-white rounded-lg shadow-lg border border-gray-200 p-4 text-center text-sm text-gray-500 z-50">
            No results found for "{query}"
          </div>
        )}
        </div>
      </div>

      {/* Right section: brand filter + notifications + admin */}
      <div className="flex items-center gap-4">
        {/* Brand Filter — hidden if admin is scoped to a specific brand */}
        {!admin?.brand_scope && (
          <div className="flex items-center gap-2">
            <span className="w-2.5 h-2.5 rounded-full" style={{ backgroundColor: 'var(--brand-500)' }} />
            <select
              value={brand}
              onChange={(e) => setBrand(e.target.value)}
              className="text-sm bg-gray-100 border border-gray-200 rounded-lg px-3 py-1.5 text-gray-700 outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500"
            >
              <option value="">All Brands</option>
              <option value="ssvid">SSvid</option>
              <option value="vidcombo">VidCombo</option>
            </select>
          </div>
        )}

        {/* Notification Bell */}
        <div className="relative" ref={notifRef}>
          <button
            onClick={() => { setShowNotifs(!showNotifs); clearNotifications() }}
            className="relative p-1.5 rounded-lg hover:bg-gray-100 text-gray-500 hover:text-gray-700 transition-colors"
          >
            <Bell size={18} />
            {unreadCount > 0 && (
              <span className="absolute -top-0.5 -right-0.5 w-4 h-4 bg-red-500 text-white text-[10px] font-bold rounded-full flex items-center justify-center">
                {unreadCount > 9 ? '9+' : unreadCount}
              </span>
            )}
          </button>

          {showNotifs && (
            <div className="absolute right-0 top-full mt-1 w-96 bg-white rounded-lg shadow-lg border border-gray-200 max-h-[400px] overflow-y-auto z-50">
              <div className="px-4 py-3 border-b flex items-center justify-between">
                <h3 className="text-sm font-semibold text-gray-700">Notifications</h3>
                {notifications.length > 0 && (
                  <button
                    onClick={() => setNotifications([])}
                    className="text-xs text-gray-400 hover:text-gray-600"
                  >
                    Clear all
                  </button>
                )}
              </div>
              {notifications.length === 0 ? (
                <div className="p-6 text-center text-sm text-gray-400">
                  No notifications yet
                </div>
              ) : (
                notifications.map((notif, i) => {
                  const route = getNotifRoute(notif)
                  return (
                    <div
                      key={i}
                      onClick={() => {
                        if (route) {
                          navigate(route)
                          setShowNotifs(false)
                        }
                      }}
                      className={`px-4 py-3 border-b last:border-0 hover:bg-gray-50 ${route ? 'cursor-pointer' : ''}`}
                    >
                      <div className="flex items-center justify-between">
                        <span className="text-xs font-semibold text-indigo-600 uppercase">{getNotifLabel(notif.type)}</span>
                        <span className="text-xs text-gray-400">
                          {new Date(notif.timestamp).toLocaleTimeString()}
                        </span>
                      </div>
                      {notif.data.subject ? (
                        <p className="text-sm text-gray-700 mt-1 truncate">{String(notif.data.subject)}</p>
                      ) : null}
                      {notif.data.content ? (
                        <p className="text-xs text-gray-500 mt-0.5 truncate">{String(notif.data.content).slice(0, 80)}</p>
                      ) : null}
                    </div>
                  )
                })
              )}
            </div>
          )}
        </div>

        {/* Admin info */}
        <div className="flex items-center gap-2 text-sm text-gray-600">
          <User size={16} />
          <span>{admin?.name || admin?.email}</span>
        </div>
      </div>
    </header>
  )
}
