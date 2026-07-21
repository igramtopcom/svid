import client from './client'
import type { ApiResponse, PaginatedResponse, AuditLogEntry, WebhookEvent, SystemHealth, AdminUser, ApiKeyInfo } from '@/types'

// --- Audit Logs ---
export async function listAuditLogs(params?: {
  page?: number
  per_page?: number
  admin_id?: string
  action?: string
  resource_type?: string
  date_from?: string
  date_to?: string
}) {
  const res = await client.get<PaginatedResponse<AuditLogEntry>>('/audit-logs', { params })
  return res.data.data
}

// --- Webhook Events ---
export async function listWebhookEvents(params?: {
  page?: number
  per_page?: number
  event_type?: string
  status?: string
}) {
  const res = await client.get<PaginatedResponse<WebhookEvent>>('/webhook-events', { params })
  return res.data.data
}

// --- System Health ---
export async function getSystemHealth() {
  const res = await client.get<ApiResponse<SystemHealth>>('/system/health')
  return res.data.data
}

// --- Admin Management ---
export async function listAdmins() {
  const res = await client.get<ApiResponse<AdminUser[]>>('/admins')
  return res.data.data
}

export async function createAdmin(data: { email: string; password: string; name: string; brand_scope?: string }) {
  const res = await client.post<ApiResponse<AdminUser>>('/admins', data)
  return res.data.data
}

export async function updateAdmin(id: string, data: { name?: string; password?: string; brand_scope?: string }) {
  const res = await client.patch<ApiResponse<{ message: string }>>(`/admins/${id}`, data)
  return res.data.data
}

export async function deleteAdmin(id: string) {
  const res = await client.delete<ApiResponse<{ message: string }>>(`/admins/${id}`)
  return res.data.data
}

// --- API Keys ---
export async function listApiKeys(deviceId: string) {
  const res = await client.get<ApiResponse<ApiKeyInfo[]>>(`/api-keys/device/${deviceId}`)
  return res.data.data
}

export async function revokeApiKey(id: string) {
  const res = await client.delete<ApiResponse<{ message: string }>>(`/api-keys/${id}`)
  return res.data.data
}
