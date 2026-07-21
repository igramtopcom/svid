import client from './client'
import type {
  ApiResponse,
  PaginatedResponse,
  License,
  EnhancedTransaction,
  TransactionStats,
  PremiumStats,
  Subscription,
  SubscriptionStats,
  Customer,
  CustomerDetail,
  CustomerStats,
  GlobalSearchResult,
  RevenueReport,
  Invoice,
  InvoiceStats,
  MRRPoint,
} from '@/types'

// --- Licenses ---

export async function listLicenses(params?: {
  page?: number
  per_page?: number
  tier?: string
  payment_method?: string
  search?: string
  sort_by?: string
  sort_dir?: string
  brand?: string
}) {
  const res = await client.get<PaginatedResponse<License>>('/licenses', { params })
  return res.data.data
}

export async function getLicense(id: string) {
  const res = await client.get<ApiResponse<License>>(`/licenses/${id}`)
  return res.data.data
}

export async function updateLicense(id: string, data: Partial<License>) {
  const res = await client.patch<ApiResponse<License>>(`/licenses/${id}`, data)
  return res.data.data
}

export async function createLicense(data: { billing_cycle: string; contact_email?: string; notes?: string }) {
  const res = await client.post<ApiResponse<License>>('/licenses', data)
  return res.data.data
}

export interface LicenseDevice {
  id: string
  license_id: string
  device_id: string
  registered_at: string
  last_verified_at: string
}

export async function listLicenseDevices(licenseId: string) {
  const res = await client.get<ApiResponse<LicenseDevice[]>>(`/licenses/${licenseId}/devices`)
  return res.data.data
}

export async function removeLicenseDevice(licenseId: string, deviceId: string) {
  const res = await client.delete<ApiResponse<{ success: boolean }>>(`/licenses/${licenseId}/devices/${deviceId}`)
  return res.data.data
}

// --- Transactions ---

export async function listTransactions(params?: {
  page?: number
  per_page?: number
  status?: string
  payment_method?: string
  search?: string
  date_from?: string
  date_to?: string
  sort_by?: string
  sort_dir?: string
  brand?: string
}) {
  const res = await client.get<PaginatedResponse<EnhancedTransaction>>('/transactions', { params })
  return res.data.data
}

export async function getTransaction(id: string) {
  const res = await client.get<ApiResponse<EnhancedTransaction>>(`/transactions/${id}`)
  return res.data.data
}

export async function getTransactionStats(brand?: string) {
  const res = await client.get<ApiResponse<TransactionStats>>('/transactions/stats', { params: { brand } })
  return res.data.data
}

export async function refundTransaction(id: string, cancelLicense = false) {
  const res = await client.post<ApiResponse<EnhancedTransaction>>(`/transactions/${id}/refund`, { cancel_license: cancelLicense })
  return res.data.data
}

// --- Premium Stats ---

export async function getPremiumStats(brand?: string) {
  const res = await client.get<ApiResponse<PremiumStats>>('/premium/stats', { params: { brand } })
  return res.data.data
}

// --- Subscriptions ---

export async function listSubscriptions(params?: {
  page?: number
  per_page?: number
  status?: string
  search?: string
  sort_by?: string
  sort_dir?: string
  brand?: string
}) {
  const res = await client.get<PaginatedResponse<Subscription>>('/subscriptions', { params })
  return res.data.data
}

export async function getSubscriptionStats(brand?: string) {
  const res = await client.get<ApiResponse<SubscriptionStats>>('/subscriptions/stats', { params: { brand } })
  return res.data.data
}

export async function getMRRTrend(months = 12, brand?: string) {
  const res = await client.get<ApiResponse<MRRPoint[]>>('/subscriptions/mrr-trend', { params: { months, brand } })
  return res.data.data
}

// --- Customers ---

export async function listCustomers(params?: {
  page?: number
  per_page?: number
  search?: string
  sort_by?: string
  sort_dir?: string
  brand?: string
}) {
  const res = await client.get<PaginatedResponse<Customer>>('/customers', { params })
  return res.data.data
}

export async function getCustomer(email: string) {
  const res = await client.get<ApiResponse<CustomerDetail>>(`/customers/${encodeURIComponent(email)}`)
  return res.data.data
}

export async function getCustomerStats(brand?: string) {
  const res = await client.get<ApiResponse<CustomerStats>>('/customers/stats', { params: { brand } })
  return res.data.data
}

// --- Invoices ---

export async function listInvoices(params?: {
  page?: number
  per_page?: number
  status?: string
  search?: string
  sort_by?: string
  sort_dir?: string
  brand?: string
}) {
  const res = await client.get<PaginatedResponse<Invoice>>('/invoices', { params })
  return res.data.data
}

export async function getInvoiceStats(brand?: string) {
  const res = await client.get<ApiResponse<InvoiceStats>>('/invoices/stats', { params: { brand } })
  return res.data.data
}

export async function getInvoice(id: string) {
  const res = await client.get<ApiResponse<Invoice>>(`/invoices/${id}`)
  return res.data.data
}

// --- Revenue Report ---

export async function getRevenueReport(days = 30, brand?: string) {
  const res = await client.get<ApiResponse<RevenueReport>>('/finance/revenue', { params: { days, brand } })
  return res.data.data
}

// --- Global Search ---

export async function globalSearch(query: string) {
  const res = await client.get<ApiResponse<GlobalSearchResult>>('/search', { params: { q: query } })
  return res.data.data
}
