import client from './client'
import type { ApiResponse, PaginatedResponse, BugReport, CrashReport, BugStats, DiagnosticLog, CrashGroup, CrashGroupStats } from '@/types'

export async function listBugs(params: {
  page?: number
  per_page?: number
  status?: string
  priority?: string
  brand?: string
  device_id?: string
  os?: string
  app_version?: string
  search?: string
}) {
  const res = await client.get<PaginatedResponse<BugReport>>('/bugs', { params })
  return res.data.data
}

export async function getBug(id: string) {
  const res = await client.get<ApiResponse<BugReport>>(`/bugs/${id}`)
  return res.data.data
}

export async function updateBug(id: string, data: { status?: string; priority?: string; admin_notes?: string }) {
  const res = await client.patch<ApiResponse<BugReport>>(`/bugs/${id}`, data)
  return res.data.data
}

export async function getBugStats(brand?: string) {
  const res = await client.get<ApiResponse<BugStats>>('/bugs/stats', { params: { brand } })
  return res.data.data
}

export async function listCrashes(params: {
  page?: number
  per_page?: number
  severity?: string
  os?: string
  app_version?: string
  brand?: string
  device_id?: string
}) {
  const res = await client.get<PaginatedResponse<CrashReport>>('/crashes', { params })
  return res.data.data
}

export async function getCrash(id: string) {
  const res = await client.get<ApiResponse<CrashReport>>(`/crashes/${id}`)
  return res.data.data
}

export async function getBugLog(id: string) {
  const res = await client.get<ApiResponse<DiagnosticLog>>(`/bugs/${id}/log`)
  return res.data.data
}

export async function getCrashLog(id: string) {
  const res = await client.get<ApiResponse<DiagnosticLog>>(`/crashes/${id}/log`)
  return res.data.data
}

export async function updateCrash(id: string, data: { admin_notes?: string }) {
  const res = await client.patch<ApiResponse<CrashReport>>(`/crashes/${id}`, data)
  return res.data.data
}

// Crash Groups
export async function listCrashGroups(params: {
  page?: number
  per_page?: number
  status?: string
  severity?: string
  search?: string
  brand?: string
}) {
  const res = await client.get<PaginatedResponse<CrashGroup>>('/crash-groups', { params })
  return res.data.data
}

export async function getCrashGroup(id: string) {
  const res = await client.get<ApiResponse<CrashGroup>>(`/crash-groups/${id}`)
  return res.data.data
}

export async function updateCrashGroup(id: string, data: {
  status?: string
  severity?: string
  admin_notes?: string
  assigned_to?: string
}) {
  const res = await client.patch<ApiResponse<CrashGroup>>(`/crash-groups/${id}`, data)
  return res.data.data
}

export async function mergeCrashGroups(target_id: string, source_ids: string[]) {
  const res = await client.post<ApiResponse<{ message: string }>>('/crash-groups/merge', { target_id, source_ids })
  return res.data.data
}

export async function listGroupCrashes(groupId: string, params: { page?: number; per_page?: number }) {
  const res = await client.get<PaginatedResponse<CrashReport>>(`/crash-groups/${groupId}/crashes`, { params })
  return res.data.data
}

export async function getCrashGroupStats(brand?: string) {
  const res = await client.get<ApiResponse<CrashGroupStats>>('/crash-groups/stats', { params: { brand } })
  return res.data.data
}
