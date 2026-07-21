import client from './client'
import type { ApiResponse, PaginatedResponse } from '@/types'
import type { AlertConfig, AlertLog } from '@/types'

export async function listAlertConfigs() {
  const res = await client.get<ApiResponse<AlertConfig[]>>('/alerts')
  return res.data.data
}

export async function createAlertConfig(data: {
  name: string
  metric_type: string
  threshold: number
  window_mins: number
  channel: string
  destination: string
  is_enabled?: boolean
  cooldown_mins?: number
}) {
  const res = await client.post<ApiResponse<AlertConfig>>('/alerts', data)
  return res.data.data
}

export async function getAlertConfig(id: string) {
  const res = await client.get<ApiResponse<AlertConfig>>(`/alerts/${id}`)
  return res.data.data
}

export async function updateAlertConfig(id: string, data: Partial<{
  name: string
  threshold: number
  window_mins: number
  channel: string
  destination: string
  is_enabled: boolean
  cooldown_mins: number
}>) {
  const res = await client.patch<ApiResponse<AlertConfig>>(`/alerts/${id}`, data)
  return res.data.data
}

export async function deleteAlertConfig(id: string) {
  const res = await client.delete<ApiResponse<{ deleted: boolean }>>(`/alerts/${id}`)
  return res.data.data
}

export async function testAlert(id: string) {
  const res = await client.post<ApiResponse<{ sent: boolean }>>(`/alerts/${id}/test`)
  return res.data.data
}

export async function listAlertLogs(params?: { page?: number; per_page?: number; config_id?: string }) {
  const res = await client.get<PaginatedResponse<AlertLog>>('/alerts/logs', { params })
  return res.data.data
}
