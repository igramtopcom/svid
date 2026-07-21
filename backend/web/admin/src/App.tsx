import { lazy, Suspense, type ReactNode } from 'react'
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { QueryClient, QueryClientProvider, MutationCache } from '@tanstack/react-query'
import { Toaster, toast } from 'sonner'
import { useAuthStore } from '@/store/auth'
import ErrorBoundary from '@/components/common/ErrorBoundary'
import Layout from '@/components/layout/Layout'
import LoadingSpinner from '@/components/common/LoadingSpinner'

// Route-based code splitting — each page loads on demand
const Login = lazy(() => import('@/pages/Login'))
const Dashboard = lazy(() => import('@/pages/Dashboard'))
const DeviceList = lazy(() => import('@/pages/devices/DeviceList'))
const DeviceDetail = lazy(() => import('@/pages/devices/DeviceDetail'))
const BugList = lazy(() => import('@/pages/bugs/BugList'))
const BugDetail = lazy(() => import('@/pages/bugs/BugDetail'))
const CrashList = lazy(() => import('@/pages/bugs/CrashList'))
const CrashDetail = lazy(() => import('@/pages/bugs/CrashDetail'))
const CrashGroupList = lazy(() => import('@/pages/bugs/CrashGroupList'))
const CrashGroupDetail = lazy(() => import('@/pages/bugs/CrashGroupDetail'))
const FeatureFlags = lazy(() => import('@/pages/product/FeatureFlags'))
const RemoteConfigPage = lazy(() => import('@/pages/product/RemoteConfig'))
const Releases = lazy(() => import('@/pages/product/Releases'))
const Announcements = lazy(() => import('@/pages/product/Announcements'))
const TicketList = lazy(() => import('@/pages/feedback/TicketList'))
const TicketDetail = lazy(() => import('@/pages/feedback/TicketDetail'))
const FeatureRequests = lazy(() => import('@/pages/feedback/FeatureRequests'))
const Ratings = lazy(() => import('@/pages/feedback/Ratings'))
const Sessions = lazy(() => import('@/pages/assistant/Sessions'))
const KnowledgeBasePage = lazy(() => import('@/pages/assistant/KnowledgeBase'))
const Analytics = lazy(() => import('@/pages/analytics/Analytics'))
const AlertSettings = lazy(() => import('@/pages/settings/AlertSettings'))
const AuditLogs = lazy(() => import('@/pages/settings/AuditLogs'))
const WebhookEvents = lazy(() => import('@/pages/settings/WebhookEvents'))
const SystemHealth = lazy(() => import('@/pages/settings/SystemHealth'))
const AdminUsers = lazy(() => import('@/pages/settings/AdminUsers'))
const LicenseDetail = lazy(() => import('@/pages/premium/LicenseDetail'))
const TransactionList = lazy(() => import('@/pages/premium/TransactionList'))
const TransactionDetail = lazy(() => import('@/pages/premium/TransactionDetail'))
const SubscriptionList = lazy(() => import('@/pages/premium/SubscriptionList'))
const LicenseKeyList = lazy(() => import('@/pages/premium/LicenseKeyList'))
const CustomerList = lazy(() => import('@/pages/premium/CustomerList'))
const CustomerDetail = lazy(() => import('@/pages/premium/CustomerDetail'))
const InvoiceList = lazy(() => import('@/pages/premium/InvoiceList'))
const InvoiceDetail = lazy(() => import('@/pages/premium/InvoiceDetail'))
const RevenueReport = lazy(() => import('@/pages/finance/RevenueReport'))
const DownloadStatsPage = lazy(() => import('@/pages/analytics/DownloadStatsPage'))
const DownloadErrorsPage = lazy(() => import('@/pages/analytics/DownloadErrorsPage'))

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      retry: 1,
      staleTime: 30_000,
      refetchOnWindowFocus: false,
    },
  },
  mutationCache: new MutationCache({
    onError: (error: unknown) => {
      const err = error as { response?: { data?: { error?: { message?: string } } } }
      const msg = err?.response?.data?.error?.message || 'Something went wrong'
      toast.error(msg)
    },
  }),
})

function ProtectedRoute({ children }: { children: ReactNode }) {
  const isAuth = useAuthStore((s) => s.isAuthenticated)()
  if (!isAuth) return <Navigate to="/login" replace />
  return <>{children}</>
}

export default function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <Toaster position="top-right" richColors closeButton duration={3000} />
      <ErrorBoundary>
      <BrowserRouter basename="/dashboard-ui">
        <Suspense fallback={<LoadingSpinner />}>
        <Routes>
          <Route path="/login" element={<Login />} />
          <Route
            element={
              <ProtectedRoute>
                <Layout />
              </ProtectedRoute>
            }
          >
            <Route path="/" element={<Dashboard />} />
            <Route path="/devices" element={<DeviceList />} />
            <Route path="/devices/:id" element={<DeviceDetail />} />

            {/* Finance */}
            <Route path="/finance/revenue" element={<RevenueReport />} />
            <Route path="/subscriptions" element={<SubscriptionList />} />
            <Route path="/transactions" element={<TransactionList />} />
            <Route path="/transactions/:id" element={<TransactionDetail />} />
            <Route path="/invoices" element={<InvoiceList />} />
            <Route path="/invoices/:id" element={<InvoiceDetail />} />
            <Route path="/licenses" element={<LicenseKeyList />} />
            <Route path="/licenses/:id" element={<LicenseDetail />} />

            {/* Customers */}
            <Route path="/customers" element={<CustomerList />} />
            <Route path="/customers/:email" element={<CustomerDetail />} />

            {/* Bug Reports */}
            <Route path="/bugs" element={<BugList />} />
            <Route path="/bugs/:id" element={<BugDetail />} />
            <Route path="/crash-groups" element={<CrashGroupList />} />
            <Route path="/crash-groups/:id" element={<CrashGroupDetail />} />
            <Route path="/crashes" element={<CrashList />} />
            <Route path="/crashes/:id" element={<CrashDetail />} />

            {/* Product Control */}
            <Route path="/flags" element={<FeatureFlags />} />
            <Route path="/config" element={<RemoteConfigPage />} />
            <Route path="/releases" element={<Releases />} />
            <Route path="/announcements" element={<Announcements />} />

            {/* Feedback */}
            <Route path="/tickets" element={<TicketList />} />
            <Route path="/tickets/:id" element={<TicketDetail />} />
            <Route path="/features" element={<FeatureRequests />} />
            <Route path="/ratings" element={<Ratings />} />

            {/* AI Assistant */}
            <Route path="/assistant/sessions" element={<Sessions />} />
            <Route path="/assistant/knowledge" element={<KnowledgeBasePage />} />

            {/* Download Stats */}
            <Route path="/downloads" element={<DownloadStatsPage />} />
            <Route path="/download-errors" element={<DownloadErrorsPage />} />

            {/* Analytics */}
            <Route path="/analytics" element={<Analytics />} />

            {/* Settings */}
            <Route path="/alerts" element={<AlertSettings />} />
            <Route path="/audit-logs" element={<AuditLogs />} />
            <Route path="/webhook-events" element={<WebhookEvents />} />
            <Route path="/system-health" element={<SystemHealth />} />
            <Route path="/admin-users" element={<AdminUsers />} />

            {/* Legacy redirects */}
            <Route path="/premium" element={<Navigate to="/subscriptions" replace />} />
            <Route path="/premium/:id" element={<LicenseDetail />} />
          </Route>
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
        </Suspense>
      </BrowserRouter>
      </ErrorBoundary>
    </QueryClientProvider>
  )
}
