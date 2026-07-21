import { useState, useEffect } from 'react'
import { NavLink } from 'react-router-dom'
import {
  LayoutDashboard,
  Monitor,
  Bug,
  Zap,
  Layers,
  Settings,
  Package,
  Megaphone,
  Lightbulb,
  Star,
  Bot,
  BookOpen,
  BarChart3,
  Bell,
  LogOut,
  Users,
  CreditCard,
  KeyRound,
  Repeat,
  DollarSign,
  Download,
  Receipt,
  HeadsetIcon,
  Shield,
  AlertTriangle,
  FileText,
  Webhook,
  Activity,
  UserCog,
  ChevronDown,
} from 'lucide-react'
import { useAuthStore } from '@/store/auth'
import type { LucideIcon } from 'lucide-react'

interface NavItem {
  to: string
  icon: LucideIcon
  label: string
}

interface NavSection {
  title: string
  key: string
  items: NavItem[]
}

const sections: NavSection[] = [
  {
    title: 'Tổng quan',
    key: 'overview',
    items: [
      { to: '/', icon: LayoutDashboard, label: 'Dashboard' },
    ],
  },
  {
    title: 'Tài chính',
    key: 'finance',
    items: [
      { to: '/finance/revenue', icon: DollarSign, label: 'Revenue Report' },
      { to: '/subscriptions', icon: Repeat, label: 'Subscriptions' },
      { to: '/transactions', icon: CreditCard, label: 'Transactions' },
      { to: '/invoices', icon: Receipt, label: 'Invoices' },
      { to: '/licenses', icon: KeyRound, label: 'License Keys' },
    ],
  },
  {
    title: 'Khách hàng',
    key: 'customers',
    items: [
      { to: '/customers', icon: Users, label: 'Customers' },
      { to: '/devices', icon: Monitor, label: 'Devices' },
    ],
  },
  {
    title: 'Thống kê lượt tải',
    key: 'downloads',
    items: [
      { to: '/downloads', icon: Download, label: 'Download Stats' },
      { to: '/download-errors', icon: AlertTriangle, label: 'Download Errors' },
    ],
  },
  {
    title: 'Hệ thống',
    key: 'system',
    items: [
      { to: '/bugs', icon: Bug, label: 'Bugs' },
      { to: '/crash-groups', icon: Layers, label: 'Crash Groups' },
      { to: '/crashes', icon: Zap, label: 'Crashes' },
    ],
  },
  {
    title: 'Chăm sóc KH',
    key: 'support',
    items: [
      { to: '/tickets', icon: HeadsetIcon, label: 'Tickets' },
      { to: '/features', icon: Lightbulb, label: 'Feature Requests' },
      { to: '/ratings', icon: Star, label: 'Ratings' },
    ],
  },
  {
    title: 'Quản trị',
    key: 'admin',
    items: [
      { to: '/flags', icon: Settings, label: 'Feature Flags' },
      { to: '/config', icon: Shield, label: 'Remote Config' },
      { to: '/releases', icon: Package, label: 'Releases' },
      { to: '/announcements', icon: Megaphone, label: 'Announcements' },
      { to: '/analytics', icon: BarChart3, label: 'Analytics' },
      { to: '/alerts', icon: Bell, label: 'Alert Rules' },
      { to: '/audit-logs', icon: FileText, label: 'Audit Logs' },
      { to: '/webhook-events', icon: Webhook, label: 'Webhook Events' },
      { to: '/system-health', icon: Activity, label: 'System Health' },
      { to: '/admin-users', icon: UserCog, label: 'Admin Users' },
    ],
  },
  {
    title: 'Khác',
    key: 'other',
    items: [
      { to: '/assistant/sessions', icon: Bot, label: 'AI Chat' },
      { to: '/assistant/knowledge', icon: BookOpen, label: 'Knowledge Base' },
    ],
  },
]

const STORAGE_KEY = 'sidebar-sections'

function loadCollapsed(): Record<string, boolean> {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    return raw ? JSON.parse(raw) : {}
  } catch {
    return {}
  }
}

interface SidebarProps {
  onClose?: () => void
}

export default function Sidebar({ onClose }: SidebarProps) {
  const logout = useAuthStore((s) => s.logout)
  const [collapsed, setCollapsed] = useState<Record<string, boolean>>(loadCollapsed)

  useEffect(() => {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(collapsed))
  }, [collapsed])

  const toggle = (key: string) => {
    setCollapsed((prev) => ({ ...prev, [key]: !prev[key] }))
  }

  return (
    <aside className="w-64 bg-gray-900 text-gray-300 flex flex-col min-h-screen fixed left-0 top-0 bottom-0 overflow-y-auto">
      <div className="p-4 border-b border-gray-700">
        <div className="flex items-center gap-3">
          <img src={import.meta.env.BASE_URL + 'logo.png'} alt="SSvid" width="40" height="40" className="rounded-lg" />
          <div>
            <h1 className="text-xl font-bold text-white">SSvid</h1>
            <p className="text-xs text-gray-500">Admin Dashboard</p>
          </div>
        </div>
      </div>

      <nav className="flex-1 py-2">
        {sections.map((section) => {
          const isCollapsed = collapsed[section.key] === true
          return (
            <div key={section.key}>
              <button
                onClick={() => toggle(section.key)}
                className="w-full flex items-center justify-between px-4 pt-4 pb-1 group"
              >
                <span className="text-xs font-semibold text-gray-500 uppercase tracking-wider group-hover:text-gray-400 transition-colors">
                  {section.title}
                </span>
                <ChevronDown
                  size={14}
                  className={`text-gray-600 transition-transform duration-150 ${isCollapsed ? '-rotate-90' : ''}`}
                />
              </button>
              <div
                className={`overflow-hidden transition-all duration-150 ${
                  isCollapsed ? 'max-h-0' : 'max-h-[500px]'
                }`}
              >
                {section.items.map((item) => {
                  const Icon = item.icon
                  return (
                    <NavLink
                      key={item.to}
                      to={item.to}
                      end={item.to === '/'}
                      onClick={onClose}
                      className={({ isActive }) =>
                        `flex items-center gap-3 px-4 py-2 text-sm transition-colors ${
                          isActive
                            ? 'bg-brand-600 text-white'
                            : 'hover:bg-gray-800 hover:text-white'
                        }`
                      }
                    >
                      <Icon size={18} />
                      {item.label}
                    </NavLink>
                  )
                })}
              </div>
            </div>
          )
        })}
      </nav>

      <div className="p-4 border-t border-gray-700">
        <button
          onClick={logout}
          className="flex items-center gap-3 text-sm text-gray-400 hover:text-white transition-colors w-full"
        >
          <LogOut size={18} />
          Sign Out
        </button>
      </div>
    </aside>
  )
}
